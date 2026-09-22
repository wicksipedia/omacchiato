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
