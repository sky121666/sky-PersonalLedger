#!/usr/bin/env python3
"""Offline behavior tests for the release smoke's business-data assertions."""

from copy import deepcopy
from decimal import Decimal
import io
import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import Mock

sys.dont_write_bytecode = True
import docker_persistence_probe as probe


class FixtureAPI:
    def __init__(self):
        self.initialized = False
        self.calls = []

    def call(self, method, path, **kwargs):
        self.calls.append((method, path, kwargs))
        if path == "/auth/status":
            return {"initialized": self.initialized}
        if path == "/auth/init":
            assert not self.initialized
            self.initialized = True
            self.password = kwargs["body"]["password"]
            return {"access_token": "synthetic-access-token", "refresh_token": "synthetic-refresh-token"}
        if path == "/auth/login":
            assert self.password == kwargs["body"]["password"]
            return {"access_token": "synthetic-new-access-token"}
        if path == "/accounts":
            self.account = dict(kwargs["body"], id="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", current_balance=100)
            return deepcopy(self.account)
        if path == "/transactions":
            self.transaction = dict(kwargs["body"], id="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
            self.account["current_balance"] = Decimal("87.66")
            return deepcopy(self.transaction)
        if path.startswith("/accounts/"):
            return deepcopy(self.account)
        if path.startswith("/transactions/"):
            return deepcopy(self.transaction)
        raise AssertionError("Unexpected API request")


class PersistenceProbeTests(unittest.TestCase):
    def test_seed_and_reauthenticated_verification_keep_records_and_balance(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            api = FixtureAPI()
            probe.seed(api, state_path, "synthetic-setup-token")
            self.assertEqual(stat.S_IMODE(state_path.stat().st_mode), 0o600)
            state = json.loads(state_path.read_text())
            self.assertEqual(set(state), {"password", "account_id", "transaction_id"})
            self.assertNotIn("synthetic-access-token", state_path.read_text())
            self.assertNotIn("synthetic-refresh-token", state_path.read_text())
            # A separate API object represents a new process backed by persisted data.
            recreated = deepcopy(api)
            recreated.calls.clear()
            probe.verify(recreated, state_path)
            self.assertEqual([(method, path) for method, path, _ in recreated.calls], [
                ("POST", "/auth/login"), ("GET", "/accounts/" + state["account_id"]),
                ("GET", "/transactions/" + state["transaction_id"]),
            ])

    def test_missing_or_mutated_persisted_business_data_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            seeded = FixtureAPI()
            probe.seed(seeded, state_path, "synthetic-setup-token")
            cases = [("account", "current_balance", 100), ("account", "name", "wrong"),
                     ("transaction", "id", "cccccccc-cccc-cccc-cccc-cccccccccccc"),
                     ("transaction", "amount", 12.35), ("transaction", "account_id", "other"),
                     ("transaction", "remark", ""), ("transaction", "type", "income")]
            for record, field, value in cases:
                recreated = deepcopy(seeded)
                getattr(recreated, record)[field] = value
                with self.subTest(record=record, field=field), self.assertRaises(ValueError):
                    probe.verify(recreated, state_path)
            recreated = deepcopy(seeded)
            recreated.transaction = {}
            with self.assertRaises(ValueError):
                probe.verify(recreated, state_path)

    def test_seed_refuses_existing_deployment_or_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            api = FixtureAPI()
            api.initialized = True
            with self.assertRaisesRegex(ValueError, "fresh isolated"):
                probe.seed(api, state_path, "synthetic-setup-token")
            self.assertEqual(len(api.calls), 1)
            state_path.write_text("already seeded")
            with self.assertRaisesRegex(ValueError, "refusing to reseed"):
                probe.seed(api, state_path, "synthetic-setup-token")
            self.assertEqual(len(api.calls), 1)

    def test_http_client_requires_success_and_never_follows_redirects(self):
        api = probe.LocalAPI(18080)
        api.opener = Mock()
        api.opener.open.return_value = io.BytesIO(b'{"code":0,"data":{"amount":12.34}}')
        self.assertEqual(api.call("GET", "/accounts/id", token="synthetic-token")["amount"], Decimal("12.34"))
        request = api.opener.open.call_args.args[0]
        self.assertEqual(request.full_url, "http://127.0.0.1:18080/api/v1/accounts/id")
        self.assertEqual(request.get_header("Authorization"), "Bearer synthetic-token")
        api.opener.open.return_value = io.BytesIO(b'{"code":50001,"data":{},"message":"private-response"}')
        with self.assertRaisesRegex(ValueError, "unsuccessful response"):
            api.call("GET", "/accounts/id")
        with self.assertRaisesRegex(ValueError, "must not redirect"):
            probe.NoRedirects().redirect_request(None, None, None, None, None, None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
