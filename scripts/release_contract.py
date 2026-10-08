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
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


DIGEST = r"sha256:[0-9a-f]{64}"
SHA = r"[0-9a-f]{40}"
TAG = r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?"
BUILD_JOB = "Build and scan one OCI layout without registry write access"
PUBLISH_JOB = "Publish only the scanned OCI handoff"
SCAN_PREDICATE = "https://github.com/sky121666/sky-PersonalLedger/attestations/docker-scan/v1"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command_category(args):
    """Describe only allowlisted executable/subcommand names, never user arguments."""
    for prefix in (("gh", "api"), ("gh", "attestation", "verify"), ("gh", "release", "download"), ("gh", "release", "create"),
                   ("docker", "buildx", "imagetools", "inspect"), ("docker", "compose")):
        if tuple(args[:len(prefix)]) == prefix:
            return " ".join(prefix)
    return {"git": "git", "bash": "compose generator"}.get(args[0], "subprocess")


def failure_detail(stderr):
    """Extract bounded diagnostic enums without copying URLs, headers or credentials."""
    text = stderr.decode("utf-8", errors="replace")
    statuses = sorted(set(re.findall(r"\bHTTP(?:/[12](?:\.\d)?)?\s+([45]\d\d)\b|\bstatus(?: code)?[:=]?\s+([45]\d\d)\b", text, re.I)))
    codes = sorted({code for pair in statuses for code in pair if code})
    reason = "unclassified"
    for pattern, label in (
        (r"unauthorized|authentication|bad credentials|HTTP\s+401", "authentication"),
        (r"forbidden|permission|HTTP\s+403", "permission"),
        (r"unknown flag|unknown option|unrecognized argument", "unsupported-cli-option"),
        (r"executable file not found|command not found|helper not found", "tool-unavailable"),
        (r"timed? ?out|timeout|connection|network|TLS|certificate|resolve host", "transport"),
        (r"not found|manifest unknown|name unknown|HTTP\s+404", "not-found-unconfirmed"),
    ):
        if re.search(pattern, text, re.I):
            reason = label
            break
    return f"reason={reason}; http={','.join(codes) or 'unavailable'}"


def command(args, *, input=None, env=None, stage="release command"):
    result = subprocess.run(args, input=input, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, check=False)
    # Stage labels are call-site constants. Never echo arguments, output or environment.
    require(result.returncode == 0,
            f"{stage}: {command_category(args)} failed (exit {result.returncode}; "
            f"{failure_detail(result.stderr)}); stopped without retry")
    return result.stdout


def api(path, *, optional=False, stage="GitHub state lookup"):
    result = subprocess.run(["gh", "api", path], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if optional and result.returncode and b"HTTP 404" in result.stderr:
        return None
    require(result.returncode == 0,
            f"{stage}: gh api failed (exit {result.returncode}; {failure_detail(result.stderr)}); "
            "cannot establish remote state")
    return json.loads(result.stdout)


def repo():
    value = os.environ.get("GITHUB_REPOSITORY", "")
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value), "Set GITHUB_REPOSITORY=owner/repo")
    return value


def git(source, *args):
    stages = {"ls-remote": "remote tag identity", "fetch": "default branch fetch",
              "merge-base": "source ancestry", "show": "source version"}
    return command(["git", "-C", str(source), *args],
                   stage=stages.get(args[0], "local source identity")).decode().strip()


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
            raise ValueError(f"registry manifest lookup: HTTP {error.code}; did not prove manifest absence") from None
    except HTTPError as error:
        status = error.code
        error.close()
        raise ValueError(f"registry absence lookup: HTTP {status}; cannot prove image absence") from None
    except (URLError, TimeoutError, KeyError):
        raise ValueError("Public registry lookup failed; cannot prove image absence") from None


def image_digest(image):
    result = subprocess.run(["docker", "buildx", "imagetools", "inspect", image, "--raw"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        # Even familiar CLI missing-manifest messages need an independent, exact
        # registry response. Local errors and authentication failures never authorize a push.
        missing_hint = (re.search(rb"manifest unknown|name unknown", result.stderr, re.I)
                        or result.stderr.strip() == f"ERROR: {image}: not found".encode())
        if missing_hint and public_manifest_absent(image):
            return None
        raise ValueError(f"version image lookup: docker buildx imagetools inspect failed "
                         f"(exit {result.returncode}; {failure_detail(result.stderr)}); image absence is NOT proven")
    manifest = json.loads(result.stdout)
    platforms = {(x.get("platform", {}).get("os"), x.get("platform", {}).get("architecture"))
                 for x in manifest.get("manifests", [])}
    require({("linux", "amd64"), ("linux", "arm64")} <= platforms, "Both linux architectures are required")
    return "sha256:" + hashlib.sha256(result.stdout).hexdigest()


def require_image_absent(tag):
    require(image_digest(f"ghcr.io/{repo().lower()}:{tag[1:]}") is None,
            "Image tag already exists; refusing to overwrite the immutable version")
    print("Registry confirmed the version manifest is absent")


def check_image(tag, digest, sha):
    require(re.fullmatch(DIGEST, digest), "Expected a full sha256 image digest")
    require(re.fullmatch(SHA, sha), "Expected a full source commit")
    image = f"ghcr.io/{repo().lower()}"
    require(image_digest(f"{image}:{tag[1:]}") == digest, "Version image tag changed or is missing")
    immutable = f"{image}@{digest}"
    # Query registry configs without pulling different platforms into one local image store.
    configs_raw = command(["docker", "buildx", "imagetools", "inspect", immutable,
                           "--format", "{{json .Image}}"], stage="both image architecture identities")
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


def requires_scan_proof(tag):
    # Old releases did not sign scan evidence. Never pretend their expired logs
    # can be reconstructed; retain the explicit legacy verification boundary.
    return tuple(map(int, tag[1:].split("-", 1)[0].split("."))) >= (1, 0, 10)


def scan_proof_name(tag):
    return f"docker-scan-proof-{tag}.jsonl"


def proof_bundle_bytes(results):
    bundles = [entry.get("attestation", {}).get("bundle") for entry in results]
    require(bundles and all(isinstance(bundle, dict) and bundle for bundle in bundles),
            "Verified scan attestation has no downloadable signature bundle")
    return b"".join((json.dumps(bundle, separators=(",", ":")) + "\n").encode() for bundle in bundles)


def trusted_main_ancestor(repository, tooling_sha, default=None):
    """Anchor a commit to GitHub's actual protected default-branch history."""
    if default is None:
        default = api(f"repos/{repository}", stage="trusted release default branch").get("default_branch", "")
    require(isinstance(default, str) and re.fullmatch(r"[A-Za-z0-9_./-]+", default),
            "Invalid trusted default branch")
    branch = api(f"repos/{repository}/branches/{quote(default, safe='')}",
                 stage="protected release branch identity")
    require(branch.get("name") == default and branch.get("protected") is True,
            "Release tooling must belong to the protected default branch")
    head = branch.get("commit", {}).get("sha", "")
    require(isinstance(head, str) and re.fullmatch(SHA, head), "Invalid protected release head")
    comparison = api(f"repos/{repository}/compare/{tooling_sha}...{head}",
                     stage="release tooling main ancestry")
    require(comparison.get("merge_base_commit", {}).get("sha") == tooling_sha,
            "Release tooling commit is not in protected main history")
    return default


def scan_source_policy(repository, tag, sha, predicate):
    """Claims may select a policy, but never define its trusted source.

    Normal releases are anchored to the already verified product tag. Recovery
    tooling must be an ancestor of the current protected default-branch head.
    The resulting ref and digests are enforced against the signed certificate.
    """
    workflow = predicate.get("workflow_ref", "")
    tooling_sha = predicate.get("tooling_sha", "")
    normal = f"{repository}/.github/workflows/release-web.yml@refs/tags/{tag}"
    if workflow == normal:
        if tooling_sha != sha:
            return None
        trusted_main_ancestor(repository, sha)
        return {"source_ref": f"refs/tags/{tag}", "tooling_sha": sha,
                "caller_uri": "https://github.com/" + normal}
    if not workflow.startswith(f"{repository}/.github/workflows/release-web-recovery.yml@refs/heads/"):
        return None
    default = api(f"repos/{repository}", stage="trusted recovery default branch").get("default_branch", "")
    require(isinstance(default, str) and re.fullmatch(r"[A-Za-z0-9_./-]+", default),
            "Invalid trusted default branch")
    expected = f"{repository}/.github/workflows/release-web-recovery.yml@refs/heads/{default}"
    if workflow != expected:
        return None
    trusted_main_ancestor(repository, tooling_sha, default)
    return {"source_ref": f"refs/heads/{default}", "tooling_sha": tooling_sha,
            "caller_uri": "https://github.com/" + expected}


def certificate_matches_policy(result, repository, policy):
    """These flat fields are signed Fulcio certificate extensions, not claims.

    gh 2.88.1 uses sigstore-go v1.1.4 CertificateSummary with anonymously
    embedded Extensions; there is intentionally no nested `extensions` object.
    """
    certificate = result.get("verificationResult", {}).get("signature", {}).get("certificate", {})
    expected = {"buildConfigURI": policy["caller_uri"],
                "buildConfigDigest": policy["tooling_sha"],
                "buildSignerURI": f"https://github.com/{repository}/.github/workflows/docker.yml@{policy['source_ref']}",
                "buildSignerDigest": policy["tooling_sha"],
                "subjectAlternativeName": f"https://github.com/{repository}/.github/workflows/docker.yml@{policy['source_ref']}",
                "sourceRepositoryURI": "https://github.com/" + repository,
                "sourceRepositoryDigest": policy["tooling_sha"],
                "sourceRepositoryRef": policy["source_ref"]}
    return isinstance(certificate, dict) and all(certificate.get(key) == value for key, value in expected.items())


def verify_scan_attestation(tag, sha, digest, *, publisher=None, bundle_file=None):
    """Trust gh's signature/certificate verification, then enforce our scan policy.

    Predicate fields are claims by the pinned protected workflow, not standalone
    signatures. The reusable signer and its exact commit are checked by gh.
    """
    require(re.fullmatch(SHA, sha) and re.fullmatch(DIGEST, digest), "Invalid scan proof identity")
    repository = repo()
    argv = ["gh", "attestation", "verify", f"oci://ghcr.io/{repository.lower()}@{digest}",
            "--repo", repository, "--predicate-type", SCAN_PREDICATE,
            "--signer-workflow", f"{repository}/.github/workflows/docker.yml",
            "--deny-self-hosted-runners", "--format", "json"]
    if bundle_file:
        argv += ["--bundle", str(bundle_file)]
    if publisher:
        require(re.fullmatch(SHA, publisher.get("head_sha", "")), "Invalid publisher tooling identity")
        argv += ["--signer-digest", publisher["head_sha"]]
    results = json.loads(command(argv, stage="signed Docker scan proof verification"))
    require(isinstance(results, list) and results, "No verified Docker scan attestations")
    selected = []
    for entry in results:
        statement = entry.get("verificationResult", {}).get("statement", {}) if isinstance(entry, dict) else {}
        predicate = statement.get("predicate", {})
        if not isinstance(predicate, dict):
            continue
        expected = {"schema_version": 1, "repository": repository, "source_sha": sha,
                    "version": tag[1:], "platforms": ["linux/amd64", "linux/arm64"],
                    "scanner": "trivy", "severity": ["HIGH", "CRITICAL"],
                    "ignore_unfixed": True, "vuln_type": ["os", "library"],
                    "scan_exit_codes": {"amd64": 0, "arm64": 0}, "handoff_digest": digest}
        if any(predicate.get(key) != value for key, value in expected.items()):
            continue
        if statement.get("predicateType") != SCAN_PREDICATE or statement.get("subject") != [
                {"name": f"ghcr.io/{repository.lower()}", "digest": {"sha256": digest[7:]}}]:
            continue
        run_id, attempt = str(predicate.get("run_id", "")), str(predicate.get("run_attempt", ""))
        tooling_sha = predicate.get("tooling_sha", "")
        workflow = predicate.get("workflow_ref", "")
        if not (run_id.isdigit() and int(run_id) > 0 and attempt.isdigit() and int(attempt) > 0
                and isinstance(tooling_sha, str) and re.fullmatch(SHA, tooling_sha)
                and isinstance(workflow, str)):
            continue
        if not (workflow == f"{repository}/.github/workflows/release-web.yml@refs/tags/{tag}" or
                re.fullmatch(re.escape(repository) + r"/\.github/workflows/release-web-recovery\.yml@refs/heads/[A-Za-z0-9_./-]+", workflow)):
            continue
        if publisher and (run_id != str(publisher["id"]) or attempt != str(publisher["run_attempt"])
                          or tooling_sha != publisher["head_sha"]):
            continue
        # The first gh call has already verified these certificate fields.
        # Filter inconsistent branch claims before querying GitHub ancestry:
        # a forged recovery claim must not poison an otherwise valid bundle set.
        claimed = {"source_ref": workflow.rsplit("@", 1)[1], "tooling_sha": tooling_sha,
                   "caller_uri": "https://github.com/" + workflow}
        if not certificate_matches_policy(entry, repository, claimed):
            continue
        policy = scan_source_policy(repository, tag, sha, predicate)
        if policy is None:
            continue
        # Verify this exact bundle against an independent trust anchor. A
        # signature from another branch cannot authorize its own tooling SHA.
        with tempfile.TemporaryDirectory(prefix="ledger-proof-verify-") as directory:
            bundle = Path(directory) / "proof.jsonl"
            bundle.write_bytes(proof_bundle_bytes([entry]))
            pinned = list(argv)
            if "--signer-digest" in pinned:
                pinned[pinned.index("--signer-digest") + 1] = policy["tooling_sha"]
            else:
                pinned += ["--signer-digest", policy["tooling_sha"]]
            pinned += ["--source-ref", policy["source_ref"],
                       "--source-digest", policy["tooling_sha"]]
            if "--bundle" in pinned:
                pinned[pinned.index("--bundle") + 1] = str(bundle)
            else:
                pinned += ["--bundle", str(bundle)]
            verified = json.loads(command(pinned, stage="scan proof trusted source certificate verification"))
            require(isinstance(verified, list) and verified
                    and all(isinstance(item, dict) and certificate_matches_policy(item, repository, policy)
                            for item in verified),
                    "Signed certificate does not bind the approved caller, ref and trusted source")
        selected.append(entry)
    require(selected, "Signed scan proof does not bind the source, run, digest and required scan policy")
    proof_bundle_bytes(selected)
    return selected


def validate_metadata(release, tag):
    require(release.get("tag_name") == tag and release.get("draft") is False,
            "Release tag/draft mismatch")
    require(release.get("prerelease") is ("-" in tag), "Release prerelease mismatch")
    # Optional signed-mobile assets may coexist; never modify or validate their signatures here.
    names = list(asset_names(tag))
    if requires_scan_proof(tag):
        names.append(scan_proof_name(tag))
    for name in names:
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
                                  env={k: v for k, v in os.environ.items() if not k.startswith("LEDGER_")},
                                  stage="release Compose parsing"))


def verify_assets(tag, digest, sha=""):
    require(re.fullmatch(TAG, tag) and re.fullmatch(DIGEST, digest), "Invalid tag or digest")
    release = api(f"repos/{repo()}/releases/tags/{tag}", stage="public Release metadata")
    validate_metadata(release, tag)
    name, checksum_name = asset_names(tag)
    def download(filename):
        return command(["gh", "release", "download", tag, "--repo", repo(), "--pattern", filename, "--output", "-"],
                       stage="public Compose checksum download" if filename.endswith(".sha256") else "public Compose download")
    compose, checksum = download(name), download(checksum_name)
    validate_checksum(compose, checksum, name)
    validate_compose(compose_config(compose), f"ghcr.io/{repo().lower()}@{digest}")
    if requires_scan_proof(tag):
        sha = sha or git(".", "rev-list", "-n", "1", f"refs/tags/{tag}")
        with tempfile.TemporaryDirectory(prefix="ledger-public-proof-") as directory:
            proof = Path(directory) / scan_proof_name(tag)
            proof.write_bytes(download(proof.name))
            verify_scan_attestation(tag, sha, digest, bundle_file=proof)
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
    source_run = api(f"repos/{repository}/actions/runs/{args.run_id}", stage="original tag workflow run")
    validate_source_run(source_run, args.tag, sha, repository)
    gates = api(f"repos/{repository}/actions/runs?head_sha={sha}&event=push&status=success&per_page=100",
                stage="successful source quality gates")["workflow_runs"]
    for path in ("quality-gate.yml", "public-git-safety.yml"):
        require(any(r.get("path") == f".github/workflows/{path}" and r.get("head_sha") == sha
                    and r.get("head_branch") == default_branch and r.get("conclusion") == "success"
                    and r.get("event") == "push" for r in gates), f"Missing successful source gate: {path}")
    release = api(f"repos/{repository}/releases/tags/{args.tag}", optional=True, stage="existing Release state")
    digest = image_digest(f"ghcr.io/{repository.lower()}:{args.tag[1:]}")
    mode = recovery_mode(release is not None, digest, args.digest, args.publisher_run_id)
    require(not args.verify_only or mode == "verify", "Read-only verification requires a complete existing release; publishing is forbidden")
    if mode != "build":
        publisher = api(f"repos/{repository}/actions/runs/{args.publisher_run_id}", stage="publisher workflow run")
        # Pin jobs to the same attempt, and include all pages (no first-page success shortcut).
        attempt = publisher["run_attempt"]
        pages = json.loads(command(["gh", "api", "--paginate", "--slurp",
                                   f"repos/{repository}/actions/runs/{args.publisher_run_id}/attempts/{attempt}/jobs?per_page=100"],
                                  stage="publisher attempt jobs pagination"))
        jobs = [job for page in pages for job in page["jobs"]]
        build, publish = validate_publisher(publisher, jobs, repository, args.tag, sha, default_branch)
        git(args.source, "merge-base", "--is-ancestor", publisher["head_sha"], f"origin/{default_branch}")
        if requires_scan_proof(args.tag):
            verify_scan_attestation(args.tag, sha, digest, publisher=publisher)
        else:
            logs = [command(["gh", "api", f"repos/{repository}/actions/jobs/{job}/logs"], stage=stage).decode()
                    for job, stage in ((build, "publisher build and scan log"), (publish, "publisher push log"))]
            validate_logs(*logs, sha, digest)
        if release is not None:
            verify_assets(args.tag, digest, sha)  # Incomplete or inconsistent Release: stop; never overwrite/upload.
    outputs = {"mode": mode, "version": args.tag[1:], "repository": repository.lower(),
               "release_tag": args.tag, "release_sha": sha, "tag_object": obj, "image_digest": digest or ""}
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
        for key, value in outputs.items():
            handle.write(f"{key}={value}\n")
    print(f"Recovery state: {mode}; source={sha}; image={digest or 'absent'}")


def publish(args):
    sha, _ = identity(args.source, args.tag, args.sha, args.tag_object)
    require(image_digest(f"ghcr.io/{repo().lower()}:{args.tag[1:]}") == args.digest, "Published digest changed")
    require(api(f"repos/{repo()}/releases/tags/{args.tag}", optional=True, stage="pre-create Release state") is None,
            "Release already exists; use read-only verification, never overwrite it")
    name, checksum_name = asset_names(args.tag)
    with tempfile.TemporaryDirectory(prefix="ledger-release-publish-") as directory:
        compose = Path(directory) / name
        environment = dict(os.environ, RELEASE_IMAGE=f"ghcr.io/{repo().lower()}@{args.digest}",
                           RELEASE_COMPOSE_SOURCE=str(Path(args.source).resolve() / "docker-compose.yml"))
        # Always execute this tooling snapshot's generator, not scripts from the old tag.
        command(["bash", str(Path(__file__).with_name("generate-release-compose.sh")), str(compose)],
                env=environment, stage="version Compose generation")
        content = compose.read_bytes()
        validate_compose(compose_config(content), environment["RELEASE_IMAGE"])
        checksum = Path(directory) / checksum_name
        checksum.write_text(f"{hashlib.sha256(content).hexdigest()}  {name}\n", encoding="ascii")
        assets = [str(compose), str(checksum)]
        if requires_scan_proof(args.tag):
            # Recovery can resume a prior publisher, so verify the signature
            # independently when this run did not produce the existing image.
            verified = verify_scan_attestation(args.tag, sha, args.digest)
            proof = Path(directory) / scan_proof_name(args.tag)
            proof.write_bytes(proof_bundle_bytes(verified))
            assets.append(str(proof))
        body = (f"Docker/Web 自托管发布；不包含签名 APK/AAB/IPA。\n\n"
                f"源码提交：`{sha}`\n\n镜像：`{environment['RELEASE_IMAGE']}`\n\n"
                f"请下载 `{name}` 与 `.sha256` 并校验后部署。\n\n"
                f"[文档与截图](https://github.com/{repo()}/tree/{args.tag}/README.md)\n")
        if requires_scan_proof(args.tag):
            body += (f"\n[本版本变更与限制](https://github.com/{repo()}/blob/{args.tag}/docs/release/{args.tag}.md)\n\n"
                     f"扫描签名证明：`{scan_proof_name(args.tag)}`。\n\n"
                     "升级前停止写入并保存数据库、附件、配置与凭据密钥的一致性副本。新备份格式为 2.4；"
                     "回滚到 v1.0.9 应使用升级前副本，不能将 2.4 文件改标为 2.3。\n")
        args_list = ["gh", "release", "create", args.tag, *assets, "--repo", repo(),
                     "--verify-tag", "--title", f"Release {args.tag}", "--generate-notes", "--notes-file", "-"]
        if "-" in args.tag:
            args_list.append("--prerelease")
        # Deliberately no --target: the existing, verified annotated tag is authoritative.
        # If this call fails, the Release may already exist. Never retry a write automatically.
        command(args_list, input=body.encode(), stage="create-only GitHub Release write")
        print(f"Release create returned success: {args.tag}; public verification runs separately")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("recover-plan", "verify-assets", "verify-image", "verify-tag", "require-image-absent", "publish"))
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
    if args.operation not in {"recover-plan", "verify-tag", "require-image-absent"}:
        require(re.fullmatch(DIGEST, args.digest), "Invalid image digest")
    if args.operation == "recover-plan":
        recover_plan(args)
    elif args.operation == "verify-assets":
        verify_assets(args.tag, args.digest, args.sha)
    elif args.operation == "verify-image":
        check_image(args.tag, args.digest, args.sha)
    elif args.operation == "verify-tag":
        print(identity(args.source, args.tag, args.sha, args.tag_object)[0])
    elif args.operation == "require-image-absent":
        require_image_absent(args.tag)
    else:
        require(re.fullmatch(SHA, args.sha) and re.fullmatch(SHA, args.tag_object), "Publish requires pinned tag identity")
        publish(args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, UnicodeError) as error:
        raise SystemExit(f"Release contract failed: {error}") from None
