"""Dummy-only launch-boundary regressions. Never copy the ambient environment."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

WRAPPER = Path(__file__).resolve().parents[1] / "Tools/run-local.py"
CANARY = "JOEY_DUMMY_CREDENTIAL_DO_NOT_USE_20261031"


class ToolEnvironmentTests(unittest.TestCase):
    def parent(self):
        return {
            "HOME": str(Path.home()), "TMPDIR": tempfile.gettempdir(),
            "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8",
            "OPENAI_API_KEY": CANARY, "UNRELATED_SECRET": CANARY,
            "AWS_SECRET_ACCESS_KEY": CANARY, "BASH_ENV": "/unused-canary-startup",
        }

    def launch(self, command):
        return subprocess.run([sys.executable, str(WRAPPER), *command],
                              env=self.parent(), capture_output=True, text=True)

    def assert_clean(self, result):
        self.assertNotIn(CANARY, result.stdout + result.stderr)
        for name in ["OPENAI_API_KEY", "UNRELATED_SECRET", "AWS_SECRET_ACCESS_KEY", "BASH_ENV"]:
            self.assertNotIn(name, result.stdout + result.stderr)

    def test_normal_child_environment_and_output(self):
        code = "import os,json; print(json.dumps(dict(os.environ),sort_keys=True))"
        result = self.launch([sys.executable, "-c", code])
        self.assertEqual(result.returncode, 0)
        self.assert_clean(result)
        values = json.loads(result.stdout)
        self.assertEqual(values["HOME"], str(Path.home()))
        self.assertIn("/opt/homebrew/bin", values["PATH"])

    def test_launcher_preserves_direct_process_identity(self):
        # Joey's supervisor validates its parent PID; an extra waiting wrapper
        # changes that relationship and incorrectly triggers orphan cleanup.
        process = subprocess.Popen(
            [sys.executable, str(WRAPPER), sys.executable, "-c",
             "import os; print(os.getpid())"], env=self.parent(),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(int(stdout.strip()), process.pid)
        self.assertNotIn(CANARY, stdout + stderr)

    def test_error_output_cannot_echo_unrelated_environment(self):
        code = "import os,sys; print(dict(os.environ)); print(dict(os.environ),file=sys.stderr); sys.exit(7)"
        result = self.launch([sys.executable, "-c", code])
        self.assertEqual(result.returncode, 7)
        self.assert_clean(result)

    def test_actual_xctest_diagnostic_uses_only_dummy_parent(self):
        command = ["/Applications/Xcode.app/Contents/Developer/usr/bin/xctest", "-help"]
        # Positive control establishes that this diagnostic prints its inherited
        # environment. The parent contains synthetic values only, never live keys.
        control = subprocess.run(command, env=self.parent(), capture_output=True, text=True)
        self.assertNotEqual(control.returncode, 0)
        self.assertIn(CANARY, control.stdout + control.stderr)
        result = self.launch(command)
        self.assertNotEqual(result.returncode, 0)
        self.assert_clean(result)

    def test_shell_startup_cannot_restore_exported_secrets(self):
        result = self.launch(["/bin/zsh", "-lc", "true"])
        self.assertEqual(result.returncode, 2)
        self.assert_clean(result)


if __name__ == "__main__":
    unittest.main()
