#!/usr/bin/env python3
"""Regression checks for durable, signed scan evidence; all remote calls mocked."""
import copy
import json
import os
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import release_contract as contract

REPO = "example/ledger"
SHA = "a" * 40
DIGEST = "sha256:" + "b" * 64
TAG = "v1.0.10"
PREDICATE = "https://github.com/sky121666/sky-PersonalLedger/attestations/docker-scan/v1"


def proof():
    return [{"attestation": {"bundle": {"fixture": "signature bytes are checked by gh"}},
             "verificationResult": {"signature": {"certificate": {
                 "buildConfigURI": f"https://github.com/{REPO}/.github/workflows/release-web.yml@refs/tags/{TAG}",
                 "buildConfigDigest": SHA, "buildSignerDigest": SHA,
                 "buildSignerURI": f"https://github.com/{REPO}/.github/workflows/docker.yml@refs/tags/{TAG}",
                 "subjectAlternativeName": f"https://github.com/{REPO}/.github/workflows/docker.yml@refs/tags/{TAG}",
                 "sourceRepositoryURI": "https://github.com/" + REPO,
                 "sourceRepositoryDigest": SHA, "sourceRepositoryRef": "refs/tags/" + TAG}},
                 "statement": {
                 "predicateType": PREDICATE,
                 "subject": [{"name": f"ghcr.io/{REPO}", "digest": {"sha256": DIGEST[7:]}}],
                 "predicate": {"schema_version": 1, "repository": REPO,
                     "source_sha": SHA, "version": "1.0.10", "tooling_sha": SHA,
                     "run_id": "123", "run_attempt": "1",
                     "workflow_ref": f"{REPO}/.github/workflows/release-web.yml@refs/tags/{TAG}",
                     "platforms": ["linux/amd64", "linux/arm64"],
                     "scanner": "trivy", "severity": ["HIGH", "CRITICAL"],
                     "ignore_unfixed": True, "vuln_type": ["os", "library"],
                     "scan_exit_codes": {"amd64": 0, "arm64": 0},
                     "handoff_digest": DIGEST}}}}]


def recovery_proof(tooling="c" * 40, branch="main"):
    data = proof()
    caller = f"{REPO}/.github/workflows/release-web-recovery.yml@refs/heads/{branch}"
    signer = f"https://github.com/{REPO}/.github/workflows/docker.yml@refs/heads/{branch}"
    data[0]["verificationResult"]["statement"]["predicate"].update(tooling_sha=tooling, workflow_ref=caller)
    data[0]["verificationResult"]["signature"]["certificate"].update(
        buildConfigURI="https://github.com/" + caller,
        buildConfigDigest=tooling, buildSignerDigest=tooling,
        buildSignerURI=signer, subjectAlternativeName=signer,
        sourceRepositoryDigest=tooling, sourceRepositoryRef="refs/heads/" + branch)
    return data


class ScanProofTests(unittest.TestCase):
    def setUp(self):
        def trusted_api(path, **_kwargs):
            if path == f"repos/{REPO}":
                return {"default_branch": "main"}
            if path == f"repos/{REPO}/branches/main":
                return {"name": "main", "protected": True, "commit": {"sha": SHA}}
            if path.startswith(f"repos/{REPO}/compare/"):
                ancestor = path.rsplit("/", 1)[1].split("...", 1)[0]
                return {"merge_base_commit": {"sha": ancestor}}
            raise AssertionError("Unexpected trusted-source request: " + path)
        api_patch = patch.object(contract, "api", side_effect=trusted_api)
        self.api = api_patch.start()
        self.addCleanup(api_patch.stop)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_signed_proof_uses_precise_identity_policy(self, command):
        command.return_value = json.dumps(proof()).encode()
        contract.verify_scan_attestation(TAG, SHA, DIGEST,
            publisher={"id": 123, "run_attempt": 1, "head_sha": SHA})
        argv = command.call_args.args[0]
        for flag in ("--predicate-type", "--signer-workflow", "--signer-digest", "--deny-self-hosted-runners"):
            self.assertIn(flag, argv)
        self.assertIn(f"{REPO}/.github/workflows/docker.yml", argv)
        self.assertIn(f"oci://ghcr.io/{REPO}@{DIGEST}", argv)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_tampered_or_incomplete_claims_rejected(self, command):
        changes = [("source_sha", "c" * 40), ("repository", "other/repo"),
                   ("handoff_digest", "sha256:" + "c" * 64), ("version", "1.0.9"),
                   ("platforms", ["linux/amd64"]), ("scanner", "unverified"),
                   ("scan_exit_codes", {"amd64": 0, "arm64": 1}),
                   ("severity", ["CRITICAL"]), ("run_id", "124"),
                   ("run_attempt", "2"), ("tooling_sha", "c" * 40),
                   ("workflow_ref", f"{REPO}/.github/workflows/random.yml@refs/tags/{TAG}")]
        for key, value in changes:
            data = proof()
            data[0]["verificationResult"]["statement"]["predicate"][key] = value
            command.return_value = json.dumps(data).encode()
            with self.subTest(key=key), self.assertRaises(ValueError):
                contract.verify_scan_attestation(TAG, SHA, DIGEST,
                    publisher={"id": 123, "run_attempt": 1, "head_sha": SHA})
        for data in ([], [{}], [{"predicate": proof()[0]["verificationResult"]["statement"]["predicate"]}]):
            command.return_value = json.dumps(data).encode()
            with self.assertRaises(ValueError):
                contract.verify_scan_attestation(TAG, SHA, DIGEST)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command", side_effect=ValueError("signature verification failed"))
    def test_signature_failure_never_falls_back_to_unsigned_json_or_logs(self, command):
        with self.assertRaisesRegex(ValueError, "signature"):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)
        self.assertEqual(command.call_count, 1)

    def test_new_versions_require_proof_legacy_boundary_is_explicit(self):
        self.assertFalse(contract.requires_scan_proof("v1.0.9"))
        for tag in (TAG, "v1.0.10-rc.1", "v1.1.0", "v2.0.0"):
            self.assertTrue(contract.requires_scan_proof(tag))

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_tag_signature_binds_certificate_source_ref_and_trusted_digest(self, command):
        command.return_value = json.dumps(proof()).encode()
        contract.verify_scan_attestation(TAG, SHA, DIGEST)
        argv = command.call_args.args[0]
        for flag, value in (("--source-ref", "refs/tags/" + TAG),
                            ("--source-digest", SHA), ("--signer-digest", SHA)):
            self.assertIn(flag, argv)
            self.assertEqual(argv[argv.index(flag) + 1], value)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_unmerged_branch_signature_cannot_self_authorize_tooling_sha(self, command):
        data = proof()
        data[0]["verificationResult"]["statement"]["predicate"]["tooling_sha"] = "c" * 40
        command.return_value = json.dumps(data).encode()
        with self.assertRaises(ValueError):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    @patch.object(contract, "api")
    def test_recovery_requires_protected_default_branch_and_main_ancestry(self, api, command):
        claimed = "c" * 40
        data = recovery_proof(claimed)
        command.return_value = json.dumps(data).encode()
        api.side_effect = [{"default_branch": "main"},
                           {"name": "main", "protected": True, "commit": {"sha": SHA}},
                           {"merge_base_commit": {"sha": "d" * 40}}]
        with self.assertRaises(ValueError):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)
        self.assertTrue(api.called)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    @patch.object(contract, "api", return_value={"default_branch": "main"})
    def test_recovery_feature_branch_cannot_claim_publish_authority(self, api, command):
        data = recovery_proof(branch="feature")
        command.return_value = json.dumps(data).encode()
        with self.assertRaises(ValueError):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_tag_from_unmerged_commit_cannot_self_authorize(self, command):
        command.return_value = json.dumps(proof()).encode()
        self.api.side_effect = [{"default_branch": "main"},
                               {"name": "main", "protected": True, "commit": {"sha": "c" * 40}},
                               {"merge_base_commit": {"sha": "d" * 40}}]
        with self.assertRaisesRegex(ValueError, "main history"):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_unprotected_default_branch_does_not_grant_release_authority(self, command):
        command.return_value = json.dumps(proof()).encode()
        self.api.side_effect = [{"default_branch": "main"},
                               {"name": "main", "protected": False, "commit": {"sha": SHA}}]
        with self.assertRaisesRegex(ValueError, "protected default branch"):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_signed_certificate_caller_and_ref_cannot_be_spoofed_by_predicate(self, command):
        for field, value in (("buildConfigURI", f"https://github.com/{REPO}/.github/workflows/other.yml@refs/tags/{TAG}"),
                             ("sourceRepositoryRef", "refs/heads/feature"),
                             ("sourceRepositoryDigest", "c" * 40),
                             ("buildSignerDigest", "c" * 40),
                             ("buildConfigDigest", "c" * 40),
                             ("buildSignerURI", f"https://github.com/{REPO}/.github/workflows/docker.yml@refs/heads/feature"),
                             ("subjectAlternativeName", f"https://github.com/{REPO}/.github/workflows/docker.yml@refs/heads/feature"),
                             ("sourceRepositoryURI", "https://github.com/other/repo")):
            data = proof()
            data[0]["verificationResult"]["signature"]["certificate"][field] = value
            command.return_value = json.dumps(data).encode()
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "Signed"):
                contract.verify_scan_attestation(TAG, SHA, DIGEST)
        data = proof()
        del data[0]["verificationResult"]["signature"]
        command.return_value = json.dumps(data).encode()
        with self.assertRaisesRegex(ValueError, "Signed"):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_valid_recovery_binds_tooling_main_separately_from_product_tag(self, command):
        tooling = "c" * 40
        data = recovery_proof(tooling)
        command.return_value = json.dumps(data).encode()
        contract.verify_scan_attestation(TAG, SHA, DIGEST)
        argv = command.call_args.args[0]
        for flag, value in (("--source-ref", "refs/heads/main"),
                            ("--source-digest", tooling), ("--signer-digest", tooling)):
            self.assertEqual(argv[argv.index(flag) + 1], value)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_forged_branch_recovery_claim_does_not_poison_valid_tag_proof(self, command):
        forged = recovery_proof("e" * 40)
        certificate = forged[0]["verificationResult"]["signature"]["certificate"]
        certificate["sourceRepositoryRef"] = "refs/heads/feature"
        certificate["buildConfigURI"] = f"https://github.com/{REPO}/.github/workflows/release-web-recovery.yml@refs/heads/feature"
        good = proof()
        command.side_effect = [json.dumps(forged + good).encode(), json.dumps(good).encode()]
        selected = contract.verify_scan_attestation(TAG, SHA, DIGEST)
        self.assertEqual(selected, good)
        self.assertEqual(self.api.call_count, 3)
        self.assertFalse(any("e" * 40 in call.args[0] for call in self.api.call_args_list))

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_strict_certificate_verification_failure_never_uses_basic_result(self, command):
        command.side_effect = [json.dumps(proof()).encode(), ValueError("strict certificate failure")]
        with self.assertRaisesRegex(ValueError, "strict certificate failure"):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)
        self.assertEqual(command.call_count, 2)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_second_verified_certificate_cannot_drift_from_first_policy(self, command):
        drift = proof()
        drift[0]["verificationResult"]["signature"]["certificate"]["sourceRepositoryRef"] = "refs/heads/feature"
        command.side_effect = [json.dumps(proof()).encode(), json.dumps(drift).encode()]
        with self.assertRaisesRegex(ValueError, "Signed certificate"):
            contract.verify_scan_attestation(TAG, SHA, DIGEST)

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_consistent_feature_certificate_is_skipped_before_ancestry_query(self, command):
        good = proof()
        command.side_effect = [json.dumps(recovery_proof(branch="feature") + good).encode(),
                               json.dumps(good).encode()]
        self.assertEqual(contract.verify_scan_attestation(TAG, SHA, DIGEST), good)
        comparisons = [call.args[0] for call in self.api.call_args_list if "/compare/" in call.args[0]]
        self.assertEqual(comparisons, [f"repos/{REPO}/compare/{SHA}...{SHA}"])

    @patch.dict(os.environ, GITHUB_REPOSITORY=REPO)
    @patch.object(contract, "command")
    def test_existing_bundle_is_replaced_by_exact_selected_bundle_for_strict_check(self, command):
        calls = []
        def verify(argv, **_kwargs):
            calls.append(argv)
            if len(calls) == 2:
                from pathlib import Path
                exact = argv[argv.index("--bundle") + 1]
                self.assertNotEqual(exact, "/original/proof.jsonl")
                self.assertEqual(json.loads(Path(exact).read_text()), proof()[0]["attestation"]["bundle"])
                for flag in ("--bundle", "--source-ref", "--source-digest", "--signer-digest"):
                    self.assertEqual(argv.count(flag), 1)
            return json.dumps(proof()).encode()
        command.side_effect = verify
        contract.verify_scan_attestation(TAG, SHA, DIGEST,
            publisher={"id": 123, "run_attempt": 1, "head_sha": SHA}, bundle_file="/original/proof.jsonl")


if __name__ == "__main__":
    unittest.main(verbosity=2)
