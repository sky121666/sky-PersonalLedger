import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / "scripts/check-toolchain-consistency.sh"


class ToolchainConsistencyTests(unittest.TestCase):
    def run_check(self, runtime=True, shim=None):
        with tempfile.TemporaryDirectory(prefix="ledger-toolchain-test-") as folder:
            env = dict(os.environ)
            if shim:
                name, version = shim
                executable = Path(folder) / name
                executable.write_text(f"#!/bin/sh\nprintf '%s\\n' '{version}'\n")
                executable.chmod(0o755)
                env["PATH"] = folder + os.pathsep + env["PATH"]
            return subprocess.run(
                ["bash", str(CHECK), *(["--runtime"] if runtime else [])],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_project_runtime_is_accepted(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_stale_node_is_rejected(self):
        result = self.run_check(shim=("node", "v22.23.1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Active Node v22.23.1 does not match", result.stderr)

    def test_stale_pnpm_is_rejected(self):
        result = self.run_check(shim=("pnpm", "11.21.0"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Active pnpm must match packageManager", result.stderr)

    def test_static_release_checks_do_not_require_active_pnpm(self):
        result = self.run_check(runtime=False, shim=("pnpm", "11.21.0"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
