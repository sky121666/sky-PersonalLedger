#!/usr/bin/env python3
"""Release inventory and executed backup proof validation; no network or Git mutations."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BASE_REF = 'v1.0.9'
BASE_COMMIT = '134c4fdbcfb6860672af9c044fcad96aa606b8cc'
INVARIANTS = (
    'backup_format_2_4', 'soft_deleted_expense_preserved', 'active_transactions_preserved',
    'balances_preserved', 'statistics_preserved', 'member_and_payer_preserved',
    'partial_restore_rejected_without_changes', 'ai_history_preserved',
    'provider_secrets_excluded', 'credential_markers_excluded',
)


def git(root, *args):
    executable = os.environ.get('LEDGER_GIT', 'git')
    return subprocess.check_output([executable, '-C', str(root), *args])


def nul_paths(output):
    return {os.fsdecode(item) for item in output.split(b'\0') if item}


def changed_paths(root, base, candidate='HEAD'):
    # Disable rename collapsing so both removed and added names are inventoried.
    return (nul_paths(git(root, 'diff', '--no-renames', '--name-only', '-z', base, candidate))
            | nul_paths(git(root, 'diff', '--no-renames', '--name-only', '-z', candidate))
            | nul_paths(git(root, 'ls-files', '--others', '--exclude-standard', '-z')))


def forbidden_path(path):
    allowed = {'.env.example', 'mobile/android/key.properties.example',
               'mobile/android/gradle/wrapper/gradle-wrapper.jar', 'mobile/ios/Podfile.lock', 'mobile/macos/Podfile.lock'}
    if path in allowed or Path(path).name == '.env.example':
        return False
    return bool(re.search(r'(^|/)(\.env($|\.)|key\.properties$|local\.properties$|google-services\.json$|GoogleService-Info\.plist$|[^/]*\.(db|db-shm|db-wal|sqlite|sqlite3|apk|ipa|aab|jks|keystore|p12|pem|key|crt|tsbuildinfo|pyc)$|(__pycache__|node_modules|\.dart_tool|\.gradle|build|dist)($|/))', path)
                or re.fullmatch(r'web/vite\.config\.(js|d\.ts)', path))


def version(root):
    return (root / 'VERSION').read_text().strip()


def inventory(root, file, write=False, candidate='HEAD', list_paths=False):
    base = git(root, 'rev-parse', BASE_REF + '^{}').decode().strip()
    if base != os.environ.get('RELEASE_INVENTORY_BASE_COMMIT', BASE_COMMIT):
        raise ValueError('baseline tag differs from the pinned release base commit')
    actual = changed_paths(root, base, candidate)
    if write:
        try:
            actual.add(file.resolve().relative_to(root.resolve()).as_posix())
        except ValueError:
            pass
        value = {'schema_version': 1, 'base_ref': BASE_REF, 'base_commit': base,
                 'version': version(root), 'paths': sorted(actual)}
        unsafe = sorted(p for p in actual if forbidden_path(p))
        if unsafe:
            raise ValueError('Forbidden changed paths: ' + json.dumps(unsafe, ensure_ascii=False))
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    else:
        value = json.loads(file.read_text())
        if value.get('schema_version') != 1 or value.get('base_ref') != BASE_REF or value.get('base_commit') != base:
            raise ValueError('inventory baseline/schema does not match the immutable ' + BASE_REF + ' tag')
        if value.get('version') != version(root):
            raise ValueError('inventory version differs from VERSION')
        paths = value.get('paths')
        if not isinstance(paths, list) or any(not isinstance(p, str) for p in paths) or len(paths) != len(set(paths)):
            raise ValueError('inventory paths must be unique exact strings')
        missing = sorted(actual - set(paths))
        if missing:
            raise ValueError('Changed paths missing from inventory: ' + json.dumps(missing, ensure_ascii=False))
        extra = sorted(set(paths) - actual)
        if extra:
            raise ValueError('Inventory paths no longer in the candidate change set; regenerate: ' + json.dumps(extra, ensure_ascii=False))
    unsafe = sorted(p for p in actual if forbidden_path(p))
    if unsafe:
        raise ValueError('Forbidden changed paths: ' + json.dumps(unsafe, ensure_ascii=False))
    print(f'Release inventory covers {len(actual)} actual paths from {BASE_REF} ({base}) to {candidate} plus working changes.')
    if list_paths:
        for path in sorted(actual):
            print(json.dumps(path, ensure_ascii=False))


def runtime_paths(root):
    candidates = (nul_paths(git(root, 'ls-files', '-z'))
                  | nul_paths(git(root, 'ls-files', '--others', '--exclude-standard', '-z')))
    explicit = {'VERSION', 'scripts/backup_operator_drill.py', 'scripts/release_evidence.py',
                'scripts/check-backup-operator-drill-local.sh', 'scripts/check-backup-operator-drill.sh'}
    return sorted(p for p in candidates if p in explicit or
                  (p.startswith('backend/') and (p.endswith('.go') and not p.endswith('_test.go') or p in {'backend/go.mod', 'backend/go.sum'})))


def source_identity(root):
    paths = runtime_paths(root)
    records = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in paths if (root / path).is_file()}
    fingerprint = hashlib.sha256(json.dumps(records, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode()).hexdigest()
    changed = (nul_paths(git(root, 'diff', '--name-only', '-z', 'HEAD'))
               | nul_paths(git(root, 'ls-files', '--others', '--exclude-standard', '-z')))
    return {'source_commit': git(root, 'rev-parse', 'HEAD').decode().strip(),
            'source_fingerprint': fingerprint, 'runtime_source_count': len(records),
            'source_dirty': bool(changed & set(paths))}


def verify_drill(root, file, expected_commit=None, require_clean=False, max_age_hours=48):
    proof = json.loads(file.read_text())
    identity = source_identity(root)
    if proof.get('schema_version') != 1 or proof.get('kind') != 'personal-ledger-backup-http-drill':
        raise ValueError('drill proof schema/kind mismatch; historical Markdown is not execution evidence')
    if proof.get('version') != version(root) or proof.get('backup_format') != '2.4':
        raise ValueError('drill version/backup format mismatch')
    commit = expected_commit or identity['source_commit']
    if not re.fullmatch(r'[0-9a-f]{40}', commit) or proof.get('source_commit') != commit or identity['source_commit'] != commit:
        raise ValueError('drill source commit mismatch')
    if proof.get('source_fingerprint') != identity['source_fingerprint'] or proof.get('runtime_source_count') != identity['runtime_source_count']:
        raise ValueError('drill runtime source fingerprint mismatch')
    if require_clean and (proof.get('source_dirty') is not False or identity['source_dirty']):
        raise ValueError('published drill proof requires clean runtime sources')
    timestamp = datetime.fromisoformat(proof['executed_at'].replace('Z', '+00:00'))
    if timestamp.tzinfo is None:
        raise ValueError('drill execution time requires timezone')
    age = (datetime.now(timezone.utc) - timestamp).total_seconds()
    if age < -300 or age > max_age_hours * 3600:
        raise ValueError('drill execution time is stale or in the future')
    checks = proof.get('invariants', {})
    if not isinstance(checks, dict) or any(checks.get(key) is not True for key in INVARIANTS):
        raise ValueError('drill is missing a successfully executed invariant')
    print(f'Current backup HTTP drill proof verified: {commit}, {identity["source_fingerprint"]}, {proof["executed_at"]}')
    return proof


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['inventory', 'drill'])
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--file', type=Path, required=True)
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--candidate', default='HEAD')
    parser.add_argument('--list-paths', action='store_true')
    parser.add_argument('--expected-commit')
    parser.add_argument('--require-clean', action='store_true')
    parser.add_argument('--max-age-hours', type=float, default=48)
    args = parser.parse_args()
    root = args.root.resolve()
    file = args.file if args.file.is_absolute() else root / args.file
    try:
        if args.action == 'inventory':
            inventory(root, file, args.write, args.candidate, args.list_paths)
        else:
            verify_drill(root, file, args.expected_commit, args.require_clean, args.max_age_hours)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print('Release evidence rejected: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
