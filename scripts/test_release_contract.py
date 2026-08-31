#!/usr/bin/env python3
"""Offline regression tests: no GitHub writes, registry access or Docker daemon."""

import io
import hashlib
import json
import os
from pathlib import Path
import sys
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import release_contract as contract


REPO = "example/ledger"
TAG = "v1.2.3"
SHA = "a" * 40
OBJECT = "b" * 40
DIGEST = "sha256:" + "c" * 64
IMAGE = f"ghcr.io/{REPO}@{DIGEST}"
NAME = f"docker-compose-{TAG}.yml"


def metadata():
    return {"tag_name": TAG, "draft": False, "prerelease": False,
            "assets": [{"name": name, "state": "uploaded", "size": 42}
                       for name in contract.asset_names(TAG)]}


def source_run():
    return {"repository": {"full_name": REPO}, "path": ".github/workflows/release-web.yml",
            "event": "push", "head_sha": SHA, "head_branch": TAG,
            "status": "completed", "conclusion": "failure", "run_attempt": 1}


def publisher_jobs():
    return [{"id": i, "name": "Docker / " + suffix, "status": "completed", "conclusion": "success"}
            for i, suffix in enumerate((contract.BUILD_JOB, contract.PUBLISH_JOB), start=1)]


class ReleaseContractTests(unittest.TestCase):
    def test_recovery_modes(self):
        self.assertEqual(contract.recovery_mode(False, None, "", ""), "build")
        self.assertEqual(contract.recovery_mode(False, DIGEST, DIGEST, "123"), "resume")
        self.assertEqual(contract.recovery_mode(True, DIGEST, DIGEST, "123"), "verify")

    def test_ambiguous_states_never_rebuild(self):
        for args in [(True, None, "", ""), (False, None, DIGEST, "123"),
                     (False, None, "", "123"), (False, DIGEST, "", "123"),
                     (True, DIGEST, DIGEST, ""), (False, DIGEST, DIGEST, "not-a-run"),
                     (False, DIGEST, "sha256:" + "d" * 64, "123")]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                contract.recovery_mode(*args)

    def test_checksum_accepts_comment_and_image_digest_repetition(self):
        compose = f"# Immutable release image: {IMAGE}\nservices:\n  personal-ledger:\n    image: {IMAGE}\n".encode()
        checksum = f"{hashlib.sha256(compose).hexdigest()}  {NAME}\n".encode()
        contract.validate_checksum(compose, checksum, NAME)
        contract.validate_compose({"services": {"personal-ledger": {"image": IMAGE}}}, IMAGE)

    def test_checksum_rejects_corruption_extra_lines_and_paths(self):
        content = b"compose fixture"
        digest = hashlib.sha256(content).hexdigest()
        for sidecar in [f"{'0' * 64}  {NAME}\n", f"{digest}  ../{NAME}\n",
                        f"{digest}  /tmp/{NAME}\n", f"{digest}  {NAME}\n{digest}  other.yml\n"]:
            with self.subTest(sidecar=sidecar), self.assertRaises(ValueError):
                contract.validate_checksum(content, sidecar.encode(), NAME)

    def test_compose_rejects_mutable_wrong_service_and_build(self):
        for services in [{"personal-ledger": {"image": "ghcr.io/example/ledger:latest"}},
                         {"other": {"image": IMAGE}},
                         {"personal-ledger": {"image": IMAGE, "build": "."}},
                         {"personal-ledger": {"image": IMAGE}, "sidecar": {"image": IMAGE}}]:
            with self.subTest(services=services), self.assertRaises(ValueError):
                contract.validate_compose({"services": services}, IMAGE)

    def test_metadata_allows_untouched_mobile_assets(self):
        release = metadata()
        release["assets"].append({"name": "optional.apk", "state": "uploaded", "size": 99})
        contract.validate_metadata(release, TAG)

    def test_metadata_rejects_partial_or_wrong_release(self):
        for key, value in [("draft", True), ("prerelease", True), ("tag_name", "v2.0.0"),
                           ("assets", []), ("assets", metadata()["assets"][:1]),
                           ("assets", metadata()["assets"] * 2)]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                contract.validate_metadata(dict(metadata(), **{key: value}), TAG)
        for field, value in [("state", "new"), ("size", 0)]:
            release = metadata()
            release["assets"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                contract.validate_metadata(release, TAG)

    def test_source_run_accepts_completed_partial_or_full_outcomes(self):
        for conclusion in ("startup_failure", "failure", "cancelled", "success"):
            contract.validate_source_run(dict(source_run(), conclusion=conclusion), TAG, SHA, REPO)

    def test_source_run_rejects_wrong_identity_or_pending(self):
        for key, value in [("repository", {"full_name": "other/repo"}), ("head_sha", OBJECT),
                           ("head_branch", "main"), ("path", ".github/workflows/other.yml"),
                           ("event", "pull_request"), ("status", "in_progress"), ("conclusion", "skipped")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                contract.validate_source_run(dict(source_run(), **{key: value}), TAG, SHA, REPO)

    def test_successful_jobs_in_failed_publisher_run_are_usable(self):
        self.assertEqual(contract.validate_publisher(source_run(), publisher_jobs(), REPO, TAG, SHA, "main"), [1, 2])
        recovery = dict(source_run(), path=".github/workflows/release-web-recovery.yml",
                        event="workflow_dispatch", head_branch="main", head_sha=OBJECT)
        self.assertEqual(contract.validate_publisher(recovery, publisher_jobs(), REPO, TAG, SHA, "main"), [1, 2])

    def test_publisher_rejects_untrusted_runs(self):
        for key, value in [("repository", {"full_name": "other/repo"}), ("head_sha", OBJECT),
                           ("head_branch", "feature"), ("path", ".github/workflows/random.yml"),
                           ("event", "workflow_dispatch"), ("status", "in_progress")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                contract.validate_publisher(dict(source_run(), **{key: value}), publisher_jobs(), REPO, TAG, SHA, "main")

    def test_publisher_rejects_missing_duplicate_or_failed_jobs(self):
        cases = [[], publisher_jobs()[:1], publisher_jobs() * 2]
        for i in (0, 1):
            jobs = publisher_jobs()
            jobs[i]["conclusion"] = "failure"
            cases.append(jobs)
        for jobs in cases:
            with self.subTest(jobs=jobs), self.assertRaises(ValueError):
                contract.validate_publisher(source_run(), jobs, REPO, TAG, SHA, "main")

    def test_log_identity_is_bound_to_concrete_environment(self):
        build = f"2026-08-24T09:16:23.000Z   EXPECTED_SOURCE_SHA: {SHA}\n"
        publish = f"2026-08-24T09:20:23.000Z   EXPECTED_IMAGE_DIGEST: {DIGEST}\n"
        contract.validate_logs(build, publish, SHA, DIGEST)
        for altered in ["", build.replace(SHA, OBJECT), f'2026-08-24T09:00:00Z echo "EXPECTED_SOURCE_SHA: {SHA}"\n',
                        build + build.replace(SHA, OBJECT)]:
            with self.subTest(altered=altered), self.assertRaises(ValueError):
                contract.validate_logs(altered, publish, SHA, DIGEST)
        with self.assertRaises(ValueError):
            contract.validate_logs(build, "", SHA, DIGEST)

    @patch.object(contract, "git")
    def test_tag_and_checkout_are_pinned(self, git):
        remote = f"{OBJECT}\trefs/tags/{TAG}\n{SHA}\trefs/tags/{TAG}^{{}}"
        git.side_effect = ["tag", OBJECT, SHA, SHA, remote, TAG[1:]]
        self.assertEqual(contract.identity("source", TAG, SHA, OBJECT), (SHA, OBJECT))
        for results in [["commit"], ["tag", OBJECT, SHA, OBJECT],
                        ["tag", OBJECT, SHA, SHA, remote.replace(OBJECT, "d" * 40)]]:
            git.side_effect = results
            with self.assertRaises(ValueError):
                contract.identity("source", TAG, SHA, OBJECT)

    @patch.object(contract.subprocess, "run")
    def test_registry_transport_and_auth_failures_are_not_absence(self, run):
        for stderr in [b"unauthorized", b"HTTP 403", b"HTTP 404", b"network timeout", b"not found"]:
            run.return_value = SimpleNamespace(returncode=1, stderr=stderr)
            with self.subTest(stderr=stderr), self.assertRaises(ValueError):
                contract.image_digest("image")
        run.return_value = SimpleNamespace(returncode=1, stderr=b"manifest unknown")
        self.assertIsNone(contract.image_digest("image"))

    @patch.object(contract.subprocess, "run")
    def test_registry_requires_both_architectures_and_exact_bytes(self, run):
        manifest = {"manifests": [{"platform": {"os": "linux", "architecture": arch}} for arch in ("amd64", "arm64")]}
        raw = json.dumps(manifest).encode()
        run.return_value = SimpleNamespace(returncode=0, stdout=raw)
        self.assertEqual(contract.image_digest("image"), "sha256:" + hashlib.sha256(raw).hexdigest())
        manifest["manifests"].pop()
        run.return_value.stdout = json.dumps(manifest).encode()
        with self.assertRaises(ValueError):
            contract.image_digest("image")

    @patch.object(contract, "public_manifest_absent")
    @patch.object(contract.subprocess, "run")
    def test_buildx_not_found_requires_registry_confirmation(self, run, absent):
        run.return_value = SimpleNamespace(returncode=1, stderr=b"ERROR: ghcr.io/example/ledger:1.2.3: not found\n")
        absent.return_value = False
        with self.assertRaises(ValueError):
            contract.image_digest("ghcr.io/example/ledger:1.2.3")
        absent.return_value = True
        self.assertIsNone(contract.image_digest("ghcr.io/example/ledger:1.2.3"))

    @patch.object(contract, "urlopen")
    def test_public_manifest_absence_needs_exact_error_code(self, urlopen):
        def error(code, body):
            return contract.HTTPError("https://ghcr.io/v2/example/ledger/manifests/1.2.3", code, "", {}, io.BytesIO(json.dumps(body).encode()))
        for codes in [["MANIFEST_UNKNOWN"], ["NAME_UNKNOWN"], ["UNAUTHORIZED"], []]:
            urlopen.side_effect = [io.BytesIO(b'{"token":"anonymous-test-fixture"}'), error(404, {"errors": [{"code": c} for c in codes]})]
            self.assertEqual(contract.public_manifest_absent("ghcr.io/example/ledger:1.2.3"), codes == ["MANIFEST_UNKNOWN"])
        urlopen.side_effect = [error(401, {})]
        with self.assertRaises(ValueError):
            contract.public_manifest_absent("ghcr.io/example/ledger:1.2.3")

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    @patch.object(contract, "image_digest", return_value=DIGEST)
    def test_remote_architecture_labels_not_local_docker_store(self, image_digest, command):
        configs = {f"linux/{arch}": {"os": "linux", "architecture": arch,
                   "config": {"Labels": {"org.opencontainers.image.revision": SHA,
                       "org.opencontainers.image.version": TAG[1:],
                       "org.opencontainers.image.source": f"https://github.com/{REPO}"}}}
                   for arch in ("amd64", "arm64")}
        command.return_value = json.dumps(configs).encode()
        contract.check_image(TAG, DIGEST, SHA)
        self.assertNotIn("pull", command.call_args.args[0])
        configs["linux/arm64"]["config"]["Labels"]["org.opencontainers.image.revision"] = OBJECT
        command.return_value = json.dumps(configs).encode()
        with self.assertRaises(ValueError):
            contract.check_image(TAG, DIGEST, SHA)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "api", return_value=metadata())
    @patch.object(contract, "image_digest", return_value=DIGEST)
    @patch.object(contract, "identity", return_value=(SHA, OBJECT))
    @patch.object(contract, "command")
    def test_publish_never_updates_existing_release(self, command, identity, digest, api):
        with self.assertRaises(ValueError):
            contract.publish(SimpleNamespace(source="source", tag=TAG, sha=SHA, tag_object=OBJECT, digest=DIGEST))
        command.assert_not_called()

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "api", return_value=None)
    @patch.object(contract, "image_digest", return_value=DIGEST)
    @patch.object(contract, "identity", return_value=(SHA, OBJECT))
    @patch.object(contract, "compose_config", return_value={"services": {"personal-ledger": {"image": IMAGE}}})
    @patch.object(contract, "command")
    def test_publish_uses_create_only_without_target_and_does_not_retry(self, command, compose, identity, digest, api):
        creations = []
        def execute(argv, **kwargs):
            if argv[0] == "bash":
                Path(argv[-1]).write_bytes(b"generated compose fixture")
                self.assertEqual(kwargs["env"]["RELEASE_COMPOSE_SOURCE"], str(Path("source/docker-compose.yml").resolve()))
                return b""
            creations.append(argv)
            self.assertEqual(argv[:4], ["gh", "release", "create", TAG])
            self.assertIn("--verify-tag", argv)
            for forbidden in ("--target", "--clobber", "edit", "upload"):
                self.assertNotIn(forbidden, argv)
            raise ValueError("Simulated ambiguous write result")
        command.side_effect = execute
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            contract.publish(SimpleNamespace(source="source", tag=TAG, sha=SHA, tag_object=OBJECT, digest=DIGEST))
        self.assertEqual(len(creations), 1)

    @patch.object(contract, "command")
    def test_external_compose_includes_are_not_resolved(self, command):
        for content in [b"include: ./outside.yml\n", b"services:\n  personal-ledger:\n    extends: other.yml\n"]:
            with self.assertRaises(ValueError):
                contract.compose_config(content)
        command.assert_not_called()

    def plan_fixture(self, mode, *, bad_assets=False, bad_logs=False, missing_gate=False, untrusted=False, verify_only=False):
        """Exercise orchestration and emitted state, not just the state helper."""
        args = SimpleNamespace(source="source", tag=TAG, run_id="10", verify_only=verify_only,
                               digest="" if mode == "build" else DIGEST,
                               publisher_run_id="" if mode == "build" else "20")
        def read_api(path, **kwargs):
            if path.endswith("runs/10") or path.endswith("runs/20"):
                return source_run()
            if "actions/runs?" in path:
                gates = [{"path": ".github/workflows/" + filename, "head_sha": SHA,
                          "head_branch": "main", "conclusion": "success", "event": "push"}
                         for filename in ("quality-gate.yml", "public-git-safety.yml")]
                return {"workflow_runs": gates[:1] if missing_gate else gates}
            if "releases/tags/" in path:
                return metadata() if mode == "verify" else None
            self.fail(f"Unexpected API path: {path}")
        def read_command(argv, **kwargs):
            if "--slurp" in argv:
                self.assertIn("attempts/1/jobs?per_page=100", argv[-1])
                return json.dumps([{"jobs": publisher_jobs()[:1]}, {"jobs": publisher_jobs()[1:]}]).encode()
            if argv[-1].endswith("jobs/1/logs"):
                return f"2026-08-24T09:00:00Z   EXPECTED_SOURCE_SHA: {OBJECT if bad_logs else SHA}\n".encode()
            if argv[-1].endswith("jobs/2/logs"):
                return f"2026-08-24T09:00:00Z   EXPECTED_IMAGE_DIGEST: {DIGEST}\n".encode()
            self.fail(f"Unexpected command (no remote writes allowed): {argv[0]}")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            environment = {"GITHUB_REPOSITORY": REPO, "DEFAULT_BRANCH": "main", "GITHUB_SHA": SHA,
                           "GITHUB_REF": "refs/heads/feature" if untrusted else "refs/heads/main",
                           "GITHUB_WORKFLOW_REF": f"{REPO}/.github/workflows/release-web-recovery.yml@refs/heads/main",
                           "GITHUB_OUTPUT": str(output)}
            with patch.dict(os.environ, environment), patch.object(contract, "identity", return_value=(SHA, OBJECT)), \
                 patch.object(contract, "git", return_value=SHA), patch.object(contract, "api", side_effect=read_api), \
                 patch.object(contract, "command", side_effect=read_command), \
                 patch.object(contract, "image_digest", return_value=None if mode == "build" else DIGEST), \
                 patch.object(contract, "verify_assets", side_effect=ValueError("Partial assets") if bad_assets else None) as verify:
                if bad_assets or bad_logs or missing_gate or untrusted or (verify_only and mode != "verify"):
                    with self.assertRaises(ValueError):
                        contract.recover_plan(args)
                    self.assertFalse(output.exists(), "Failure must not authorize downstream jobs")
                else:
                    contract.recover_plan(args)
                    self.assertIn(f"mode={mode}\n", output.read_text())
                    self.assertIn(f"tag_object={OBJECT}\n", output.read_text())
                    self.assertEqual(verify.call_count, int(mode == "verify"))

    def test_recovery_orchestration_all_three_modes(self):
        for mode in ("build", "resume", "verify"):
            with self.subTest(mode=mode):
                self.plan_fixture(mode)

    def test_recovery_orchestration_never_authorizes_incomplete_assets(self):
        self.plan_fixture("verify", bad_assets=True)

    def test_recovery_orchestration_never_authorizes_unproven_publisher(self):
        self.plan_fixture("resume", bad_logs=True)

    def test_recovery_orchestration_requires_source_gates_and_trusted_ref(self):
        self.plan_fixture("build", missing_gate=True)
        self.plan_fixture("verify", untrusted=True)

    def test_verify_only_can_never_authorize_build_or_resume(self):
        for mode in ("build", "resume", "verify"):
            with self.subTest(mode=mode):
                self.plan_fixture(mode, verify_only=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
