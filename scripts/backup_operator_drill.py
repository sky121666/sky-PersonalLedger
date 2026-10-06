#!/usr/bin/env python3
"""Actual HTTP backup roundtrip against two temporary SQLite servers and a local fake AI."""
from contextlib import ExitStack
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid

sys.dont_write_bytecode = True

from release_evidence import INVARIANTS, source_identity, verify_drill, version

ROOT = Path(__file__).resolve().parents[1]
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def request(base, path, token=None, data=None, method=None, multipart=False, expected=200):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if multipart:
        boundary = 'ledger-' + uuid.uuid4().hex
        payload = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="backup.json"\r\nContent-Type: application/json\r\n\r\n'.encode()
                   + data + f'\r\n--{boundary}--\r\n'.encode())
        headers['Content-Type'] = 'multipart/form-data; boundary=' + boundary
    elif data is not None:
        payload = json.dumps(data).encode()
        headers['Content-Type'] = 'application/json'
    else:
        payload = None
    query = urllib.request.Request(base + '/api/v1' + path, payload, headers, method=method)
    try:
        response = HTTP.open(query, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read()
        if not (200 <= response.status < 300 if expected == 200 else response.status == expected):
            raise AssertionError(f'{path}: expected HTTP {expected}, got {response.status}')
        body = json.loads(raw)
        if expected == 200 and path != '/backup':
            assert body.get('code') == 0, (path, body)
            return body.get('data')
        return body


class FakeAI(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        content = json.dumps({'summary': 'Synthetic household report for the isolated release drill.'})
        payload = json.dumps({'choices': [{'message': {'content': content}}]}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def stop_process(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)


def backend(stack, temp, binary, name):
    directory = temp / name
    directory.mkdir()
    for folder in ('uploads', 'backups', 'web'):
        (directory / folder).mkdir()
    port = free_port()
    base = f'http://127.0.0.1:{port}'
    # Drop all ambient app configuration; every app path belongs to this temp directory.
    env = {key: value for key, value in os.environ.items() if not key.startswith('LEDGER_')}
    env.update({
        'TZ': 'UTC', 'LEDGER_SERVER_PORT': str(port), 'LEDGER_SERVER_MODE': 'debug',
        'LEDGER_SERVER_WEB_PATH': str(directory / 'web'), 'LEDGER_DATABASE_DRIVER': 'sqlite',
        'LEDGER_DATABASE_PATH': str(directory / 'ledger.db'), 'LEDGER_SETUP_CONFIG_PATH': str(directory / 'config.yaml'),
        'LEDGER_JWT_SECRET': 'isolated-drill-secret-32-characters-' + name,
        'LEDGER_STORAGE_UPLOAD_PATH': str(directory / 'uploads'), 'LEDGER_STORAGE_BACKUP_PATH': str(directory / 'backups'),
        'LEDGER_CORS_ALLOWED_ORIGINS': '*', 'LEDGER_SECURITY_ALLOW_PRIVATE_OUTBOUND': 'true',
    })
    log = stack.enter_context((directory / 'server.log').open('wb'))
    process = subprocess.Popen([str(binary)], cwd=directory, env=env, stdout=log, stderr=subprocess.STDOUT)
    stack.callback(stop_process, process)
    for _ in range(120):
        if process.poll() is not None:
            raise AssertionError('Temporary backend exited: ' + (directory / 'server.log').read_text()[-4000:])
        try:
            request(base, '/auth/status')
            break
        except (OSError, AssertionError):
            time.sleep(0.1)
    else:
        raise AssertionError('Temporary backend did not become ready')
    token = request(base, '/auth/init', data={'password': 'IsolatedDrillPass123!'})['access_token']
    return base, token, directory


def snapshot(base, token, month):
    return {path: request(base, path, token) for path in
            ('/accounts', '/transactions?page_size=100', '/family/members', '/statistics/overview?month=' + month, '/ai/reports')}


def main():
    os.umask(0o077)
    output = Path(os.environ.get('BACKUP_OPERATOR_DRILL_PROOF_FILE', str(Path(tempfile.gettempdir()) / 'personal-ledger-backup-drill-proof.json'))).resolve()
    if output.is_relative_to(ROOT.resolve()):
        raise ValueError('Drill proof must be written outside the checkout, in runner temp or /tmp')
    identity = source_identity(ROOT)
    checks = {}
    with tempfile.TemporaryDirectory(prefix='ledger-backup-http-drill-') as temp_name, ExitStack() as stack:
        temp = Path(temp_name)
        binary = temp / 'ledger-server'
        build = subprocess.run([os.environ.get('LEDGER_GO', 'go'), 'build', '-o', str(binary), './cmd/server'], cwd=ROOT / 'backend', text=True, capture_output=True)
        if build.returncode:
            raise AssertionError('Isolated backend build failed:\n' + build.stderr[-6000:])
        fake = ThreadingHTTPServer(('127.0.0.1', 0), FakeAI)
        stack.callback(fake.server_close)
        stack.callback(fake.shutdown)
        threading.Thread(target=fake.serve_forever, daemon=True).start()
        source, token, source_dir = backend(stack, temp, binary, 'source')
        target, target_token, target_dir = backend(stack, temp, binary, 'target')
        member = request(source, '/family/members', token, {'name': 'Owner A', 'relationship': 'family', 'is_default': True})['id']
        payer = request(source, '/family/members', token, {'name': 'Payer B', 'relationship': 'family'})['id']
        account = request(source, '/accounts', token, {'name': 'Drill wallet', 'type': 'cash', 'initial_balance': 1000})['id']
        category = request(source, '/categories', token, {'name': 'Drill expense', 'type': 'expense'})['id']
        now = datetime.now(timezone.utc)
        month = now.strftime('%Y-%m')
        date = month + '-01T12:00:00Z'
        common = {'type': 'expense', 'account_id': account, 'category_id': category,
                  'member_id': member, 'paid_by_member_id': payer, 'transaction_date': date}
        active_id = request(source, '/transactions', token, {**common, 'amount': 25, 'remark': 'active A-owned B-paid'})['id']
        deleted_id = request(source, '/transactions', token, {**common, 'amount': 50, 'remark': 'deleted expense'})['id']
        request(source, '/transactions/' + deleted_id, token, method='DELETE')
        key = 'synthetic-drill-provider-key'
        provider_id = request(source, '/ai/providers', token, {'name': 'Drill local AI', 'provider_type': 'openai_compatible',
                              'base_url': f'http://127.0.0.1:{fake.server_port}', 'api_key': key, 'model': 'drill-model', 'enabled': True})['id']
        report = request(source, '/ai/reports/generate', token, {'provider_id': provider_id, 'report_type': 'weekly',
                         'period_start': month + '-01', 'period_end': month + '-07'})
        assert report['status'] == 'completed', report
        before = snapshot(source, token, month)
        backup = request(source, '/backup', token)
        assert backup['version'] == '2.4'
        checks['backup_format_2_4'] = True
        deleted = next(row for row in backup['transactions'] if row['id'] == deleted_id)
        assert deleted['deleted_at'] is not None
        encoded = json.dumps(backup).encode()
        for marker in ('IsolatedDrillPass123!', key, 'password_hash', 'refresh_token', 'api_token', 'api_key', 'APIKey'):
            assert marker.encode() not in encoded, 'Backup contains a credential marker'
        checks['credential_markers_excluded'] = True
        request(target, '/restore', target_token, encoded, multipart=True)
        after = snapshot(target, target_token, month)
        active_before = before['/transactions?page_size=100']['list']
        active_after = after['/transactions?page_size=100']['list']
        assert [row['id'] for row in active_after] == [row['id'] for row in active_before] == [active_id]
        checks['active_transactions_preserved'] = True
        assert after['/accounts']['net_assets'] == before['/accounts']['net_assets'] == 975
        checks['balances_preserved'] = True
        stats_path = '/statistics/overview?month=' + month
        assert after[stats_path] == before[stats_path] and after[stats_path]['expense'] == 25
        checks['statistics_preserved'] = True
        assert active_after[0]['member_id'] == member and active_after[0]['paid_by_member_id'] == payer and member != payer
        checks['member_and_payer_preserved'] = True
        with sqlite3.connect(target_dir / 'ledger.db') as database:
            row = database.execute('SELECT deleted_at FROM transactions WHERE id = ?', (deleted_id,)).fetchone()
            assert row and row[0] is not None
        restored_backup = request(target, '/backup', target_token)
        assert next(row for row in restored_backup['transactions'] if row['id'] == deleted_id)['deleted_at'] == deleted['deleted_at']
        checks['soft_deleted_expense_preserved'] = True
        assert any(row['id'] == report['id'] and row['status'] == 'completed' for row in after['/ai/reports'])
        checks['ai_history_preserved'] = True
        assert request(target, '/ai/providers', target_token) == []
        checks['provider_secrets_excluded'] = True
        partial = dict(backup)
        del partial['accounts']
        request(target, '/restore', target_token, json.dumps(partial).encode(), multipart=True, expected=400)
        assert snapshot(target, target_token, month) == after
        checks['partial_restore_rejected_without_changes'] = True
        assert source_identity(ROOT) == identity, 'Runtime sources changed during the drill; rerun after edits finish'
        assert set(checks) == set(INVARIANTS)
        proof = {'schema_version': 1, 'kind': 'personal-ledger-backup-http-drill', 'version': version(ROOT),
                 **identity, 'backup_format': '2.4', 'executed_at': datetime.now(timezone.utc).isoformat(),
                 'invariants': checks, 'measurements': {'net_assets': 975, 'month_expense': 25,
                 'active_transactions': 1, 'deleted_transactions': 1, 'backup_bytes': len(encoded),
                 'backup_sha256': hashlib.sha256(encoded).hexdigest()}}
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name(output.name + '.tmp-' + uuid.uuid4().hex)
        temporary.write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
        temporary.replace(output)
    verify_drill(ROOT, output)
    print('Backup HTTP drill passed. Machine proof: ' + str(output))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('Backup HTTP drill failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
