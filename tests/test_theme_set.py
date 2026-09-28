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

SETTINGS = """[appearance]
mode = "light"

[borders]
enabled = true
width = 4

[borders.glow]
enabled = true
opacity = 0.4
radius = 12.0

[borders.gradient]
direction = "leftToRight"
enabled = true

[quakeTerminal]
enabled = true
"""


def settings_step():
    """The Python that theme-set runs on OmniWM's settings.toml."""
    text = (REPO / "bin" / "theme-set").read_text()
    return re.search(r'OMNIWM_SETTINGS=.*?<<\'PY\'\n(.*?)\nPY\n', text, re.S).group(1)


class OmniWMSettings(unittest.TestCase):
    def run_step(self, path):
        result = subprocess.run([PYTHON, "-c", settings_step(), str(path), str(REPO / "themes"), "catppuccin",
                                 "light:catppuccin-latte,dark:catppuccin"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_pair_keeps_the_users_border_taste(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "settings.toml"
            path.write_text(SETTINGS)
            self.run_step(path)
            out = path.read_text()
        self.assertIn('[appearance]\nmode = "automatic"', out)
        self.assertIn("[borders.glow]\nenabled = true\nopacity = 0.4\nradius = 12.0", out)
        self.assertIn('direction = "leftToRight"', out)
        self.assertIn("[borders.darkColor]", out)
        self.assertIn("[quakeTerminal]\nenabled = true", out)

    def test_an_unchanged_file_is_written_again(self):
        # the write is what makes OmniWM reload its quake terminal
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "settings.toml"
            path.write_text(SETTINGS)
            self.run_step(path)
            before = path.stat().st_ino
            self.run_step(path)
            self.assertNotEqual(path.stat().st_ino, before)


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
