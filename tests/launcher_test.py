"""Exercise launcher process ownership without opening a Godot window."""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
LAUNCHERS = (("run.sh", ()), ("run.sh", ("--editor",)), ("tools/launch.sh", ()))


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="fractal-launcher-"))
        self.godot = self.folder / "godot"
        self.godot.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys, time\n"
            "if '--import' in sys.argv: sys.exit(0)\n"
            "print(json.dumps({'pid': os.getpid(), 'parent': os.getppid(), "
            "'stdin_null': os.fstat(0) == os.stat('/dev/null')}), flush=True)\n"
            "if '--quit' in sys.argv: sys.exit(37)\n"
            "while True: time.sleep(0.05)\n"
        )
        self.godot.chmod(0o755)

    def tearDown(self):
        self.godot.unlink()
        self.folder.rmdir()

    def launch(self, script, extra=()):
        args = [str(REPO / script)]
        return subprocess.Popen(
            [*args, *extra], cwd=REPO,
            env={**os.environ, "GODOT": str(self.godot), "FRACTAL_PLAY": "1"},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True,
        )

    def ready(self, proc):
        self.assertTrue(select.select([proc.stdout], [], [], 5)[0], "launcher stalled")
        line = proc.stdout.readline()
        self.assertTrue(line, "child failed to start: " + (proc.stderr.read() if not line else ""))
        child = json.loads(line)
        proc.child_pid = child["pid"]
        return child

    def cleanup(self, proc):
        try:
            if hasattr(proc, "child_pid"):
                os.kill(proc.child_pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        if proc.poll() is None:
            proc.terminate()
        proc.communicate(timeout=5)

    def test_ctrl_c_stops_background_child(self):
        for script, args in LAUNCHERS:
            with self.subTest(script=script, args=args):
                proc = self.launch(script, args)
                try:
                    child = self.ready(proc)
                    self.assertEqual(child["parent"], proc.pid, "Godot replaced the launcher")
                    self.assertTrue(child["stdin_null"], "Godot inherits terminal input")
                    proc.send_signal(signal.SIGINT)
                    self.assertEqual(proc.wait(timeout=5), 130)
                    with self.assertRaises(ProcessLookupError):
                        os.kill(child["pid"], 0)
                finally:
                    self.cleanup(proc)

    def test_preserves_game_exit_status(self):
        for script, args in LAUNCHERS:
            with self.subTest(script=script, args=args):
                proc = self.launch(script, [*args, "--quit"])
                try:
                    self.ready(proc)
                    self.assertEqual(proc.wait(timeout=5), 37)
                finally:
                    self.cleanup(proc)


if __name__ == "__main__":
    unittest.main()
