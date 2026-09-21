import unittest

from loader import load

ka = load("omacchiato-keep-awake")


class Duration(unittest.TestCase):
    def test_age_reads_as_time_held(self):
        self.assertEqual(ka.duration("01:26:17"), "1h 26m")
        self.assertEqual(ka.duration("1:02:03:04"), "26h 3m")
        self.assertEqual(ka.duration("00:00:40"), "<1m")

    def test_age_that_is_not_a_time_passes_through(self):
        self.assertEqual(ka.duration("n/a"), "n/a")


class Assertion(unittest.TestCase):
    def test_assertion_with_an_id_parses(self):
        line = '   pid 812(Vorssaint): [0x0001a2b300019f2c] 08:29:13 PreventUserIdleSystemSleep named: "x"'
        m = ka.ASSERTION.match(line)
        self.assertIsNotNone(m)
        self.assertEqual(m.groups(), ("812", "Vorssaint", "08:29:13"))


if __name__ == "__main__":
    unittest.main()
