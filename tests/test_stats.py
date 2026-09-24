import unittest

from loader import load

stats = load("omacchiato-stats")

VM_STAT = """Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                   321413.
Pages wired down:                             365538.
Pages purgeable:                              115624.
"Translation faults":                     3091825175.
Anonymous pages:                             2071534.
Pages occupied by compressor:                 118013.
"""


class Memory(unittest.TestCase):
    def test_vm_stat_parses_page_size_and_quoted_names(self):
        size, pages = stats.parse_vm_stat(VM_STAT)
        self.assertEqual(size, 16384)
        self.assertEqual(pages["Translation faults"], 3091825175)

    def test_used_memory_leaves_out_purgeable_pages(self):
        app, wired, compressed = stats.memory_parts(VM_STAT)
        self.assertEqual(app, (2071534 - 115624) * 16384)
        self.assertEqual(wired, 365538 * 16384)
        self.assertEqual(compressed, 118013 * 16384)


class Cpu(unittest.TestCase):
    def test_share_of_one_core_divides_by_cores(self):
        self.assertEqual(stats.cpu_percent(" 150.0 a\n 50.0 b\n", 4), 50.0)
        self.assertEqual(stats.cpu_percent(" 900.0 a\n", 4), 100.0)

    def test_top_rows_keep_names_with_spaces(self):
        rows = stats.top_rows(" 30.2 Microsoft Outlook\n 7.6 claude\n", lambda v: "%.0f%%" % v)
        self.assertEqual([(r["text"], r["detail"]) for r in rows],
                         [("Microsoft Outlook", "30%"), ("claude", "8%")])


class Level(unittest.TestCase):
    def test_colour_turns_at_75_and_90(self):
        self.assertEqual([stats.level(p) for p in (74, 75, 89, 90)], [None, "yellow", "yellow", "red"])


if __name__ == "__main__":
    unittest.main()
