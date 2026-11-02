import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# The bar and Karabiner start theme-set with launchd's PATH, where python3
# is the system's own. Test the step with that Python when this Mac has it.
PYTHON = "/usr/bin/python3" if os.path.exists("/usr/bin/python3") else sys.executable

CONFIG = """# my gaps
[layout]
gaps = 4.0

[decorations.borders]
width = 6 # thick
color = "#FF000000"

[workspaces]
names = ["dev"]
"""


def defi_step():
    """The Python that theme-set runs on Defi's config.toml."""
    text = (REPO / "bin" / "theme-set").read_text()
    return re.search(r'DEFI_CONFIG=.*?<<\'PY\'\n(.*?)\nPY\n', text, re.S).group(1)


class DefiBorders(unittest.TestCase):
    def run_step(self, path, theme="catppuccin"):
        borders = REPO / "themes" / theme / "borders.sh"
        result = subprocess.run([PYTHON, "-c", defi_step(), str(path), str(borders)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_sets_the_theme_colours_and_keeps_every_other_line(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "config.toml"
            path.write_text(CONFIG)
            self.run_step(path)
            out = path.read_text()
        self.assertIn('color = "#FFCBA6F7"', out)
        self.assertIn('inactive_color = "#FF45475A"', out)
        self.assertNotIn("#FF000000", out)
        for line in ("# my gaps", "gaps = 4.0", "width = 6 # thick", 'names = ["dev"]'):
            self.assertIn(line, out)

    def test_adds_the_table_to_a_config_without_one(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "config.toml"
            path.write_text("[layout]\ngaps = 4.0")
            self.run_step(path)
            out = path.read_text()
        self.assertTrue(out.startswith("[layout]\ngaps = 4.0\n\n[decorations.borders]\n"))

    def test_creates_a_missing_config(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "config.toml"
            self.run_step(path)
            self.assertIn('color = "#FFCBA6F7"', path.read_text())

    def test_a_second_run_does_not_write(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "config.toml"
            path.write_text(CONFIG)
            self.run_step(path)
            before = path.stat().st_ino
            self.run_step(path)
            self.assertEqual(path.stat().st_ino, before)


if __name__ == "__main__":
    unittest.main()


class Burst(unittest.TestCase):
    """Quick switches: runs take turns, only the newest applies, and each
    file lands whole. Runs in a sandbox HOME with a theme that has no
    wallpaper, so it touches nothing on this Mac."""

    def test_a_burst_of_switches_leaves_whole_files_and_no_temp_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "bin").mkdir()
            script = root / "bin" / "theme-set"
            script.write_text((REPO / "bin" / "theme-set").read_text())
            script.chmod(0o755)
            theme = root / "themes" / "sandbox"
            theme.mkdir(parents=True)
            (theme / "colors.toml").write_text('background = "#101010"\nforeground = "#eeeeee"\ncolor1 = "#ff0000"\n')
            home = root / "home"
            home.mkdir()
            log = root / "theme.log"
            env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "OMACCHIATO_THEME_LOG": str(log)}
            runs = [subprocess.Popen([str(script), "sandbox"], env=env, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL) for _ in range(4)]
            self.assertEqual([r.wait(timeout=60) for r in runs], [0, 0, 0, 0])

            lines = log.read_text().splitlines()
            applied = [l for l in lines if "applying sandbox" in l]
            skipped = [l for l in lines if "skipped sandbox" in l]
            self.assertGreaterEqual(len(applied), 1)
            self.assertEqual(len(applied) + len(skipped), 4)
            config = home / ".config" / "omacchiato"
            self.assertEqual((config / "theme.conf").read_text(), "theme = sandbox\n")
            ghostty = (config / "ghostty-theme").read_text()
            self.assertIn("background = #101010", ghostty)
            self.assertIn("palette = 1=#ff0000", ghostty)
            self.assertEqual([p.name for p in config.iterdir() if p.name.startswith(".")], [])
