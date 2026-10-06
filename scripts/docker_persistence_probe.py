#!/usr/bin/env python3
"""Seed/verify synthetic ledger data only on the isolated loopback Docker smoke."""

import argparse
from decimal import Decimal
import json
import os
from pathlib import Path
import re
import secrets
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


ACCOUNT_NAME = "Release persistence smoke cash"
TRANSACTION_REMARK = "release-persistence-smoke-expense"


def require(condition, message):
    if not condition:
        raise ValueError(message)


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError("Smoke API must not redirect to another deployment")


class LocalAPI:
    def __init__(self, port):
        require(1 <= port <= 65535, "Expected the isolated smoke's loopback port")
        self.base = f"http://127.0.0.1:{port}/api/v1"
        self.opener = build_opener(ProxyHandler({}), NoRedirects())

    def call(self, method, path, *, body=None, token="", setup_token=""):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        if setup_token:
            headers["X-Setup-Token"] = setup_token
        request = Request(self.base + path, method=method, headers=headers,
                          data=None if body is None else json.dumps(body).encode())
        try:
            with self.opener.open(request, timeout=20) as response:
                result = json.load(response, parse_float=Decimal)
        except HTTPError as error:
            code = error.code
            error.close()
            raise ValueError(f"Smoke API {method} failed with HTTP {code}; response omitted") from None
        except (URLError, TimeoutError):
            raise ValueError("Isolated smoke API connection failed") from None
        require(result.get("code") == 0 and "data" in result, "Smoke API returned an unsuccessful response")
        return result["data"]


def record_id(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f-]{36}", value),
            "Smoke API did not return a valid record id")
    return value


def seed(api, state_path, setup_token):
    require(not state_path.exists(), "Persistence seed state already exists; refusing to reseed")
    status = api.call("GET", "/auth/status", setup_token=setup_token)
    require(status.get("initialized") is False, "Seed requires a fresh isolated smoke deployment")
    password = "LedgerSmoke-" + secrets.token_hex(24)
    auth = api.call("POST", "/auth/init", body={"password": password}, setup_token=setup_token)
    token = auth["access_token"]
    account = api.call("POST", "/accounts", token=token, body={
        "name": ACCOUNT_NAME, "type": "cash", "initial_balance": 100,
    })
    account_id = record_id(account["id"])
    transaction = api.call("POST", "/transactions", token=token, body={
        "type": "expense", "amount": 12.34, "account_id": account_id,
        "transaction_date": "2026-08-31T12:00:00+08:00", "remark": TRANSACTION_REMARK,
    })
    state = {"password": password, "account_id": account_id, "transaction_id": record_id(transaction["id"])}
    # Only a random password for this disposable deployment is saved. Never save session tokens.
    with open(state_path, "x", encoding="utf-8", opener=lambda path, flags: os.open(path, flags, 0o600)) as output:
        json.dump(state, output)
    verify(api, state_path)


def verify(api, state_path):
    state = json.loads(state_path.read_text(encoding="utf-8"))
    account_id, transaction_id = (record_id(state[key]) for key in ("account_id", "transaction_id"))
    # Reauthenticate after recreation; do not rely on the original in-memory session.
    auth = api.call("POST", "/auth/login", body={"password": state["password"]})
    token = auth["access_token"]
    account = api.call("GET", "/accounts/" + account_id, token=token)
    transaction = api.call("GET", "/transactions/" + transaction_id, token=token)
    require(account.get("id") == account_id and account.get("name") == ACCOUNT_NAME
            and account.get("type") == "cash", "Persisted smoke account identity changed")
    require(Decimal(str(account.get("initial_balance"))) == Decimal("100")
            and Decimal(str(account.get("current_balance"))) == Decimal("87.66"),
            "Persisted smoke account balances changed")
    require(transaction.get("id") == transaction_id and transaction.get("account_id") == account_id
            and transaction.get("type") == "expense" and transaction.get("remark") == TRANSACTION_REMARK
            and Decimal(str(transaction.get("amount"))) == Decimal("12.34"),
            "Persisted smoke transaction changed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("seed", "verify"))
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--state", type=Path, required=True)
    args = parser.parse_args()
    api = LocalAPI(args.port)
    if args.operation == "seed":
        seed(api, args.state, os.environ["SMOKE_SETUP_TOKEN"])
    else:
        verify(api, args.state)
    print(f"Synthetic ledger persistence {args.operation}: PASS")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, ArithmeticError):
        # The state contains a synthetic password. Do not include exception payloads.
        raise SystemExit("Docker persistence probe failed; synthetic ledger data could not be verified") from None
