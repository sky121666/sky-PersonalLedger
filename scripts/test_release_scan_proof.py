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
             "verificationResult": {"statement": {
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


class ScanProofTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
