#!/usr/bin/env python3
"""Offline contracts using isolated Git fixtures, never this checkout's history."""
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

SOURCE = Path(__file__).resolve().parents[1]
GIT = '/Library/Developer/CommandLineTools/usr/bin/git' if Path('/Library/Developer/CommandLineTools/usr/bin/git').exists() else 'git'
BASELINE_DOC = 'docs/quality/release-change-inventory-2026-05-27.md'


class EvidenceContracts(unittest.TestCase):
    def setUp(self):
        git_environment = patch.dict(os.environ, {'LEDGER_GIT': GIT})
        git_environment.start()
        self.addCleanup(git_environment.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'backend').mkdir()
        (self.root / 'docs/quality').mkdir(parents=True)
        for name in ('check-release-change-inventory.sh', 'check-backup-operator-drill.sh', 'release_evidence.py'):
            if (SOURCE / 'scripts' / name).exists():
                shutil.copy2(SOURCE / 'scripts' / name, self.root / 'scripts' / name)
        shutil.copy2(SOURCE / BASELINE_DOC, self.root / BASELINE_DOC)
        shutil.copy2(SOURCE / 'docs/quality/backup-operator-drill-2026-05-27.md', self.root / 'docs/quality/backup-operator-drill-2026-05-27.md')
        (self.root / 'VERSION').write_text('1.0.10\n')
        (self.root / 'backend/main.go').write_text('package main\n')
        self.git('init', '-q')
        self.git('config', 'user.name', 'Evidence Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('add', '.')
        self.git('commit', '-qm', 'baseline')
        self.git('tag', 'v1.0.9')
        self.base = self.git('rev-parse', 'HEAD').strip()
        self.changed = 'backend/clean-unlisted.go'
        (self.root / self.changed).write_text('package main\n// candidate\n')
        self.git('add', self.changed)
        self.git('commit', '-qm', 'candidate')

    def git(self, *args):
        return subprocess.check_output([GIT, '-C', str(self.root), *args], text=True)

    def checker(self, script, **env):
        return subprocess.run(['bash', str(self.root / 'scripts' / script)], cwd=self.root,
                              env={**os.environ, 'LEDGER_GIT': GIT, 'RELEASE_INVENTORY_BASE_COMMIT': self.base, **env}, text=True, capture_output=True)

    def manifest(self, paths):
        path = self.root / 'docs/quality/release-change-inventory.json'
        path.write_text(json.dumps({'schema_version': 1, 'base_ref': 'v1.0.9', 'base_commit': self.base,
                                    'version': '1.0.10', 'paths': paths}))
        return path

    def test_clean_committed_change_cannot_pass_historical_inventory(self):
        self.assertEqual(self.git('status', '--porcelain'), '')
        result = self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1', RELEASE_CHANGE_INVENTORY_FILE=BASELINE_DOC)
        self.assertNotEqual(result.returncode, 0, 'clean checkout silently drops every committed change')

    def test_symlinked_dependency_cache_is_forbidden(self):
        outside = tempfile.TemporaryDirectory()
        self.addCleanup(outside.cleanup)
        (self.root / 'web').mkdir()
        (self.root / 'web/node_modules').symlink_to(outside.name, target_is_directory=True)
        self.manifest([self.changed, 'docs/quality/release-change-inventory.json', 'web/node_modules'])
        result = self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1')
        self.assertNotEqual(result.returncode, 0, 'a dependency symlink must not become release source')
        self.assertIn('Forbidden', result.stderr)

    def test_generated_vite_config_is_forbidden(self):
        (self.root / 'web').mkdir()
        for name in ('vite.config.js', 'vite.config.d.ts'):
            with self.subTest(name=name):
                path = self.root / 'web' / name
                path.write_text('// Generated from vite.config.ts\n')
                self.manifest([self.changed, 'docs/quality/release-change-inventory.json', 'web/' + name])
                result = self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Forbidden', result.stderr)
                path.unlink()

    def test_current_manifest_requires_exact_committed_path(self):
        self.manifest(['docs/quality/release-change-inventory.json', self.changed + '.extra'])
        result = self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(self.changed, result.stderr)

    def test_moving_the_baseline_tag_cannot_redefine_release_scope(self):
        head = self.git('rev-parse', 'HEAD').strip()
        self.git('tag', '-f', 'v1.0.9', head)
        path = self.manifest(['docs/quality/release-change-inventory.json'])
        value = json.loads(path.read_text())
        value['base_commit'] = head
        path.write_text(json.dumps(value))
        result = self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('pinned release base', result.stderr)

    def test_current_manifest_covers_clean_and_unusual_paths(self):
        unusual = 'backend/file with spaces\nand newline.go'
        (self.root / unusual).write_text('package main\n')
        manifest = self.manifest([self.changed, unusual, 'docs/quality/release-change-inventory.json'])
        result = self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(manifest.read_text())
        self.assertIn(unusual, value['paths'])

    def proof(self):
        module_path = SOURCE / 'scripts/release_evidence.py'
        spec = importlib.util.spec_from_file_location('current_release_evidence', module_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        value = {'schema_version': 1, 'kind': 'personal-ledger-backup-http-drill', 'version': '1.0.10',
                 **module.source_identity(self.root), 'backup_format': '2.4',
                 'executed_at': datetime.now(timezone.utc).isoformat(),
                 'invariants': {key: True for key in module.INVARIANTS}}
        path = Path(self.temp.name) / 'proof.json'
        path.write_text(json.dumps(value))
        return path, value

    def test_valid_current_drill_proof_passes(self):
        proof, _ = self.proof()
        result = self.checker('check-backup-operator-drill.sh', BACKUP_OPERATOR_DRILL_PROOF_FILE=str(proof), BACKUP_OPERATOR_DRILL_REQUIRE_CLEAN='1')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changed_runtime_source_rejects_previously_valid_proof(self):
        proof, _ = self.proof()
        (self.root / 'backend/main.go').write_text('package main\n// different runtime\n')
        result = self.checker('check-backup-operator-drill.sh', BACKUP_OPERATOR_DRILL_PROOF_FILE=str(proof))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('fingerprint', result.stderr)

    def test_expected_commit_cannot_hide_a_different_checkout(self):
        proof, value = self.proof()
        (self.root / 'docs/another-note.md').write_text('Documentation-only commit\n')
        self.git('add', 'docs/another-note.md')
        self.git('commit', '-qm', 'different checkout with same runtime')
        result = self.checker('check-backup-operator-drill.sh',
                              BACKUP_OPERATOR_DRILL_PROOF_FILE=str(proof),
                              BACKUP_OPERATOR_DRILL_EXPECTED_COMMIT=value['source_commit'])
        self.assertNotEqual(result.returncode, 0, 'expected SHA must also bind the actual checkout')

    def test_tampered_fingerprint_and_missing_invariant_are_rejected(self):
        proof, value = self.proof()
        for field, replacement in [('source_fingerprint', '0' * 64), ('invariants', {}), ('source_commit', 'f' * 40)]:
            changed = {**value, field: replacement}
            proof.write_text(json.dumps(changed))
            result = self.checker('check-backup-operator-drill.sh', BACKUP_OPERATOR_DRILL_PROOF_FILE=str(proof))
            self.assertNotEqual(result.returncode, 0, field)

    def test_old_execution_and_missing_proof_are_rejected(self):
        proof, value = self.proof()
        value['executed_at'] = (datetime.now(timezone.utc) - timedelta(days=3)).isoformat()
        proof.write_text(json.dumps(value))
        result = self.checker('check-backup-operator-drill.sh', BACKUP_OPERATOR_DRILL_PROOF_FILE=str(proof))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('stale', result.stderr)
        proof.unlink()
        self.assertNotEqual(self.checker('check-backup-operator-drill.sh', BACKUP_OPERATOR_DRILL_PROOF_FILE=str(proof)).returncode, 0)

    def test_inventory_staged_and_untracked_paths_are_required(self):
        (self.root / 'backend/staged.go').write_text('package main\n')
        self.git('add', 'backend/staged.go')
        (self.root / 'backend/untracked.go').write_text('package main\n')
        self.manifest([self.changed, 'docs/quality/release-change-inventory.json'])
        result = self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('backend/staged.go', result.stderr)
        self.assertIn('backend/untracked.go', result.stderr)

    def test_wrong_baseline_version_and_secret_paths_are_rejected(self):
        path = self.manifest([self.changed, 'docs/quality/release-change-inventory.json'])
        value = json.loads(path.read_text())
        for field, replacement in [('base_commit', '0' * 40), ('version', '0.0.0')]:
            path.write_text(json.dumps({**value, field: replacement}))
            self.assertNotEqual(self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1').returncode, 0)
        (self.root / '.env').write_text('SYNTHETIC_FIXTURE=1\n')
        path.write_text(json.dumps({**value, 'paths': value['paths'] + ['.env']}))
        self.assertNotEqual(self.checker('check-release-change-inventory.sh', STRICT_RELEASE_SCOPE='1').returncode, 0)

    def test_historical_markdown_cannot_pass_strict_current_drill(self):
        result = self.checker('check-backup-operator-drill.sh', STRICT_BACKUP_OPERATOR_DRILL='1',
                              BACKUP_OPERATOR_DRILL_FILE='docs/quality/backup-operator-drill-2026-05-27.md')
        self.assertNotEqual(result.returncode, 0, 'historical prose is not executed current-source evidence')


if __name__ == '__main__':
    unittest.main()
