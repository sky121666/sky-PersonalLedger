#!/usr/bin/env python3
"""Docker/Web release contracts. All commands except publish are remote read-only."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


DIGEST = r"sha256:[0-9a-f]{64}"
SHA = r"[0-9a-f]{40}"
TAG = r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?"
BUILD_JOB = "Build and scan one OCI layout without registry write access"
PUBLISH_JOB = "Publish only the scanned OCI handoff"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(args, *, input=None, env=None):
    result = subprocess.run(args, input=input, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, check=False)
    # Never echo subprocess stderr: commands may receive credentials via environment.
    require(result.returncode == 0, f"{args[0]} operation failed (exit {result.returncode}); stopped without retry")
    return result.stdout


def api(path, *, optional=False):
    result = subprocess.run(["gh", "api", path], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if optional and result.returncode and b"HTTP 404" in result.stderr:
        return None
    require(result.returncode == 0, "GitHub read failed; cannot establish remote state")
    return json.loads(result.stdout)


def repo():
    value = os.environ.get("GITHUB_REPOSITORY", "")
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value), "Set GITHUB_REPOSITORY=owner/repo")
    return value


def git(source, *args):
    return command(["git", "-C", str(source), *args]).decode().strip()


def identity(source, tag, expected_sha="", expected_object=""):
    require(re.fullmatch(TAG, tag), "Expected an immutable vX.Y.Z tag")
    reference = f"refs/tags/{tag}"
    require(git(source, "cat-file", "-t", reference) == "tag", "Release tag must be annotated")
    obj = git(source, "rev-parse", reference)
    sha = git(source, "rev-list", "-n", "1", reference)
    require(git(source, "rev-parse", "HEAD") == sha, "Source checkout does not match the release tag")
    remote = dict(line.split()[::-1] for line in git(source, "ls-remote", "origin", reference, reference + "^{}").splitlines())
    require(remote.get(reference) == obj and remote.get(reference + "^{}") == sha,
            "Remote tag object or peeled commit changed")
    require(not expected_sha or sha == expected_sha, "Unexpected release source commit")
    require(not expected_object or obj == expected_object, "Unexpected release tag object")
    require(git(source, "show", f"{sha}:VERSION") == tag[1:], "Tag and source VERSION differ")
    return sha, obj


def public_manifest_absent(image):
    """Confirm GHCR's exact error code; a generic HTTP/CLI 404 is not evidence."""
    match = re.fullmatch(r"ghcr\.io/([a-z0-9_.-]+/[a-z0-9_.-]+):([A-Za-z0-9_.-]+)", image)
    require(match is not None, "Invalid public GHCR version reference")
    repository, version = match.groups()
    try:
        query = urlencode({"service": "ghcr.io", "scope": f"repository:{repository}:pull"})
        with urlopen(f"https://ghcr.io/token?{query}", timeout=30) as response:
            token = json.load(response)["token"]
        request = Request(f"https://ghcr.io/v2/{repository}/manifests/{version}", headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json",
        })
        try:
            with urlopen(request, timeout=30):
                return False  # The image appeared; don't infer absence from the earlier CLI error.
        except HTTPError as error:
            with error:
                if error.code == 404:
                    codes = {entry.get("code") for entry in json.load(error).get("errors", [])}
                    return codes == {"MANIFEST_UNKNOWN"}
            raise ValueError("Registry did not prove manifest absence") from None
    except HTTPError as error:
        error.close()
        raise ValueError("Public registry lookup failed; cannot prove image absence") from None
    except (URLError, TimeoutError, KeyError):
        raise ValueError("Public registry lookup failed; cannot prove image absence") from None


def image_digest(image):
    result = subprocess.run(["docker", "buildx", "imagetools", "inspect", image, "--raw"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        # A generic 404/not-found can be an auth or transport failure, not absence.
        if re.search(rb"manifest unknown|name unknown", result.stderr, re.I):
            return None
        if result.stderr.strip() == f"ERROR: {image}: not found".encode() and public_manifest_absent(image):
            return None
        raise ValueError("Registry inspection failed; image absence is NOT proven")
    manifest = json.loads(result.stdout)
    platforms = {(x.get("platform", {}).get("os"), x.get("platform", {}).get("architecture"))
                 for x in manifest.get("manifests", [])}
    require({("linux", "amd64"), ("linux", "arm64")} <= platforms, "Both linux architectures are required")
    return "sha256:" + hashlib.sha256(result.stdout).hexdigest()


def check_image(tag, digest, sha):
    require(re.fullmatch(DIGEST, digest), "Expected a full sha256 image digest")
    require(re.fullmatch(SHA, sha), "Expected a full source commit")
    image = f"ghcr.io/{repo().lower()}"
    require(image_digest(f"{image}:{tag[1:]}") == digest, "Version image tag changed or is missing")
    immutable = f"{image}@{digest}"
    # Query registry configs without pulling different platforms into one local image store.
    configs_raw = command(["docker", "buildx", "imagetools", "inspect", immutable,
                           "--format", "{{json .Image}}"])
    configs = json.loads(configs_raw)
    for arch in ("amd64", "arm64"):
        data = configs.get(f"linux/{arch}", {})
        require((data.get("os"), data.get("architecture")) == ("linux", arch), "Image architecture mismatch")
        labels = data.get("config", {}).get("Labels", {})
        for key, expected in {"revision": sha, "version": tag[1:], "source": f"https://github.com/{repo()}"}.items():
            require(labels.get(f"org.opencontainers.image.{key}") == expected, f"Image {arch} {key} mismatch")
    print(f"Both architecture identities verified: {tag} @ {digest}")


def asset_names(tag):
    name = f"docker-compose-{tag}.yml"
    return name, name + ".sha256"


def validate_metadata(release, tag):
    require(release.get("tag_name") == tag and release.get("draft") is False,
            "Release tag/draft mismatch")
    require(release.get("prerelease") is ("-" in tag), "Release prerelease mismatch")
    # Optional signed-mobile assets may coexist; never modify or validate their signatures here.
    for name in asset_names(tag):
        entries = [a for a in release.get("assets", []) if a.get("name") == name]
        require(len(entries) == 1 and entries[0].get("state") == "uploaded"
                and entries[0].get("size", 0) > 0, f"Missing, duplicate or incomplete Docker asset: {name}")


def validate_checksum(compose, checksum, name):
    match = re.fullmatch(r"([0-9a-f]{64}) [ *]" + re.escape(name) + r"\n?", checksum.decode("ascii"))
    require(match is not None, "Checksum must reference only the expected Compose basename")
    require(hashlib.sha256(compose).hexdigest() == match[1], "Downloaded Compose checksum mismatch")


def validate_compose(config, image):
    services = config.get("services", {})
    require(set(services) == {"personal-ledger"}, "Unexpected release Compose services")
    service = services["personal-ledger"]
    require(service.get("image") == image and "build" not in service,
            "Compose service image differs from expected immutable digest")


def compose_config(compose):
    # No user .env, interpolation, include or extends is resolved. Parse actual YAML via Compose.
    # --no-interpolate keeps credentials and user configuration out of both parsing and output.
    require(not re.search(rb"(?m)^\s*(?:include|extends)\s*:", compose), "External Compose includes are forbidden")
    with tempfile.TemporaryDirectory(prefix="ledger-release-verify-") as directory:
        path = Path(directory) / "compose.yml"
        path.write_bytes(compose)
        return json.loads(command(["docker", "compose", "--env-file", "/dev/null", "-f", str(path),
                                   "config", "--no-interpolate", "--no-env-resolution", "--format", "json"],
                                  env={k: v for k, v in os.environ.items() if not k.startswith("LEDGER_")}))


def verify_assets(tag, digest):
    require(re.fullmatch(TAG, tag) and re.fullmatch(DIGEST, digest), "Invalid tag or digest")
    release = api(f"repos/{repo()}/releases/tags/{tag}")
    validate_metadata(release, tag)
    name, checksum_name = asset_names(tag)
    def download(filename):
        return command(["gh", "release", "download", tag, "--repo", repo(), "--pattern", filename, "--output", "-"])
    compose, checksum = download(name), download(checksum_name)
    validate_checksum(compose, checksum, name)
    validate_compose(compose_config(compose), f"ghcr.io/{repo().lower()}@{digest}")
    print(f"Public Docker/Web assets verified: {tag} @ {digest}")


def validate_source_run(run, tag, sha, repository):
    require(run.get("repository", {}).get("full_name") == repository, "Source run belongs to another repository")
    require(run.get("path") == ".github/workflows/release-web.yml" and run.get("event") == "push"
            and run.get("head_branch") == tag and run.get("head_sha") == sha,
            "Source run must be the tag's Docker/Web workflow")
    require(run.get("status") == "completed" and run.get("conclusion") in
            {"startup_failure", "failure", "cancelled", "success"}, "Source run must have finished")


def validate_publisher(run, jobs, repository, tag, sha, default_branch):
    require(run.get("repository", {}).get("full_name") == repository, "Publisher repository mismatch")
    require(run.get("status") == "completed", "Publisher run is still running")
    if run.get("path") == ".github/workflows/release-web.yml":
        require(run.get("event") == "push" and run.get("head_sha") == sha
                and run.get("head_branch") == tag, "Publisher tag/source mismatch")
    else:
        require(run.get("path") == ".github/workflows/release-web-recovery.yml"
                and run.get("event") == "workflow_dispatch" and run.get("head_branch") == default_branch,
                "Publisher must be the trusted release or recovery workflow")
    selected = []
    for suffix in (BUILD_JOB, PUBLISH_JOB):
        matches = [j for j in jobs if j.get("name", "").endswith(" / " + suffix)]
        require(len(matches) == 1 and matches[0].get("status") == "completed"
                and matches[0].get("conclusion") == "success", f"Missing successful publisher evidence: {suffix}")
        selected.append(matches[0]["id"])
    return selected


def validate_logs(build_log, publish_log, sha, digest):
    # Read only concrete timestamped env lines, never the echoed shell source.
    def values(log, name, pattern):
        return set(re.findall(r"(?m)^\S+Z\s+" + name + r": (" + pattern + r")\s*$", log))
    require(values(build_log, "EXPECTED_SOURCE_SHA", SHA) == {sha}, "Build log does not bind the tag source")
    require(values(publish_log, "EXPECTED_IMAGE_DIGEST", DIGEST) == {digest}, "Publisher log does not bind the scanned digest")


def recovery_mode(has_release, actual_digest, expected_digest, publisher_id):
    if actual_digest is None:
        require(not has_release, "Release exists but its version image is missing")
        require(not expected_digest and not publisher_id, "Expected a previously published image but none exists")
        return "build"
    require(re.fullmatch(DIGEST, expected_digest or "") and actual_digest == expected_digest,
            "Existing image requires its exact expected_digest; never overwrite it")
    require(re.fullmatch(r"[0-9]+", publisher_id or ""), "Existing image requires publisher_run_id")
    return "verify" if has_release else "resume"


def recover_plan(args):
    repository = repo()
    default_branch = os.environ["DEFAULT_BRANCH"]
    require(os.environ.get("GITHUB_REF") == f"refs/heads/{default_branch}", "Recovery must run from default branch")
    require(os.environ.get("GITHUB_WORKFLOW_REF") == f"{repository}/.github/workflows/release-web-recovery.yml@refs/heads/{default_branch}",
            "Untrusted recovery workflow ref")
    require(git(".", "rev-parse", "HEAD") == os.environ["GITHUB_SHA"], "Recovery tooling checkout mismatch")
    sha, obj = identity(args.source, args.tag)
    git(args.source, "fetch", "--no-tags", "origin", f"refs/heads/{default_branch}:refs/remotes/origin/{default_branch}")
    git(args.source, "merge-base", "--is-ancestor", sha, f"origin/{default_branch}")
    require(re.fullmatch(r"[0-9]+", args.run_id), "Expected numeric source run id")
    source_run = api(f"repos/{repository}/actions/runs/{args.run_id}")
    validate_source_run(source_run, args.tag, sha, repository)
    gates = api(f"repos/{repository}/actions/runs?head_sha={sha}&event=push&status=success&per_page=100")["workflow_runs"]
    for path in ("quality-gate.yml", "public-git-safety.yml"):
        require(any(r.get("path") == f".github/workflows/{path}" and r.get("head_sha") == sha
                    and r.get("head_branch") == default_branch and r.get("conclusion") == "success"
                    and r.get("event") == "push" for r in gates), f"Missing successful source gate: {path}")
    release = api(f"repos/{repository}/releases/tags/{args.tag}", optional=True)
    digest = image_digest(f"ghcr.io/{repository.lower()}:{args.tag[1:]}")
    mode = recovery_mode(release is not None, digest, args.digest, args.publisher_run_id)
    require(not args.verify_only or mode == "verify", "Read-only verification requires a complete existing release; publishing is forbidden")
    if mode != "build":
        publisher = api(f"repos/{repository}/actions/runs/{args.publisher_run_id}")
        # Pin jobs to the same attempt, and include all pages (no first-page success shortcut).
        attempt = publisher["run_attempt"]
        pages = json.loads(command(["gh", "api", "--paginate", "--slurp",
                                   f"repos/{repository}/actions/runs/{args.publisher_run_id}/attempts/{attempt}/jobs?per_page=100"]))
        jobs = [job for page in pages for job in page["jobs"]]
        build, publish = validate_publisher(publisher, jobs, repository, args.tag, sha, default_branch)
        git(args.source, "merge-base", "--is-ancestor", publisher["head_sha"], f"origin/{default_branch}")
        logs = [command(["gh", "api", f"repos/{repository}/actions/jobs/{job}/logs"]).decode() for job in (build, publish)]
        validate_logs(*logs, sha, digest)
        if release is not None:
            verify_assets(args.tag, digest)  # Incomplete or inconsistent Release: stop; never overwrite/upload.
    outputs = {"mode": mode, "version": args.tag[1:], "repository": repository.lower(),
               "release_tag": args.tag, "release_sha": sha, "tag_object": obj, "image_digest": digest or ""}
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
        for key, value in outputs.items():
            handle.write(f"{key}={value}\n")
    print(f"Recovery state: {mode}; source={sha}; image={digest or 'absent'}")


def publish(args):
    sha, _ = identity(args.source, args.tag, args.sha, args.tag_object)
    require(image_digest(f"ghcr.io/{repo().lower()}:{args.tag[1:]}") == args.digest, "Published digest changed")
    require(api(f"repos/{repo()}/releases/tags/{args.tag}", optional=True) is None,
            "Release already exists; use read-only verification, never overwrite it")
    name, checksum_name = asset_names(args.tag)
    with tempfile.TemporaryDirectory(prefix="ledger-release-publish-") as directory:
        compose = Path(directory) / name
        environment = dict(os.environ, RELEASE_IMAGE=f"ghcr.io/{repo().lower()}@{args.digest}",
                           RELEASE_COMPOSE_SOURCE=str(Path(args.source).resolve() / "docker-compose.yml"))
        # Always execute this tooling snapshot's generator, not scripts from the old tag.
        command(["bash", str(Path(__file__).with_name("generate-release-compose.sh")), str(compose)], env=environment)
        content = compose.read_bytes()
        validate_compose(compose_config(content), environment["RELEASE_IMAGE"])
        checksum = Path(directory) / checksum_name
        checksum.write_text(f"{hashlib.sha256(content).hexdigest()}  {name}\n", encoding="ascii")
        body = (f"Docker/Web 自托管发布；不包含签名 APK/AAB/IPA。\n\n"
                f"源码提交：`{sha}`\n\n镜像：`{environment['RELEASE_IMAGE']}`\n\n"
                f"请下载 `{name}` 与 `.sha256` 并校验后部署。\n\n"
                f"[文档与截图](https://github.com/{repo()}/tree/{args.tag}/README.md)\n")
        args_list = ["gh", "release", "create", args.tag, str(compose), str(checksum), "--repo", repo(),
                     "--verify-tag", "--title", f"Release {args.tag}", "--generate-notes", "--notes-file", "-"]
        if "-" in args.tag:
            args_list.append("--prerelease")
        # Deliberately no --target: the existing, verified annotated tag is authoritative.
        # If this call fails, the Release may already exist. Never retry a write automatically.
        command(args_list, input=body.encode())
        print(f"Release create returned success: {args.tag}; public verification runs separately")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("recover-plan", "verify-assets", "verify-image", "verify-tag", "publish"))
    parser.add_argument("--tag", required=True)
    parser.add_argument("--digest", default="")
    parser.add_argument("--source", default=".")
    parser.add_argument("--sha", default="")
    parser.add_argument("--tag-object", default="")
    parser.add_argument("--run-id", default="")
    parser.add_argument("--publisher-run-id", default="")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    require(not args.verify_only or args.operation == "recover-plan", "--verify-only is valid only for recover-plan")
    require(re.fullmatch(TAG, args.tag), "Invalid release tag")
    if args.operation not in {"recover-plan", "verify-tag"}:
        require(re.fullmatch(DIGEST, args.digest), "Invalid image digest")
    if args.operation == "recover-plan":
        recover_plan(args)
    elif args.operation == "verify-assets":
        verify_assets(args.tag, args.digest)
    elif args.operation == "verify-image":
        check_image(args.tag, args.digest, args.sha)
    elif args.operation == "verify-tag":
        print(identity(args.source, args.tag, args.sha, args.tag_object)[0])
    else:
        require(re.fullmatch(SHA, args.sha) and re.fullmatch(SHA, args.tag_object), "Publish requires pinned tag identity")
        publish(args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, UnicodeError) as error:
        raise SystemExit(f"Release contract failed: {error}") from None
