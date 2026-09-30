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


class PanelHolder(unittest.TestCase):
    def test_carries_the_pid_and_a_read_duration(self):
        self.assertEqual(ka.panel_holder("Steam", 812, "01:26:17"),
                         {"name": "Steam", "pid": 812, "duration": "1h 26m"})


class State(unittest.TestCase):
    def test_the_file_reads_as_off_on_or_on_until_a_time(self):
        self.assertEqual(ka.read_state("", 100), (False, None))
        self.assertEqual(ka.read_state("off\n", 100), (False, None))
        self.assertEqual(ka.read_state("on\n", 100), (True, None))
        self.assertEqual(ka.read_state("400\n", 100), (True, 400))
        self.assertEqual(ka.read_state("junk", 100), (False, None))

    def test_an_end_time_in_the_past_reads_as_off(self):
        self.assertEqual(ka.read_state("99", 100), (False, None))

    def test_each_command_writes_its_state_and_remembers_a_chosen_time(self):
        self.assertEqual(ka.next_state(["on"], False, 100), ("on", "on"))
        self.assertEqual(ka.next_state(["off"], True, 100), ("off", None))
        self.assertEqual(ka.next_state(["for", "30"], False, 100), ("1900", "for 30"))
        self.assertEqual(ka.next_state(["for", "75"], False, 100), ("4600", "for 75"), "a custom time")

    def test_toggle_turns_on_with_the_last_chosen_time(self):
        self.assertEqual(ka.next_state(["toggle"], False, 100), ("on", None))
        self.assertEqual(ka.next_state(["toggle"], False, 100, "for 30"), ("1900", None))
        self.assertEqual(ka.next_state(["toggle"], True, 100, "for 30"), ("off", None))

    def test_a_bad_remembered_time_falls_back_to_until_turned_off(self):
        self.assertEqual(ka.next_state(["toggle"], False, 100, "for x"), ("on", None))
        self.assertEqual(ka.next_state(["toggle"], False, 100, "toggle"), ("on", None))

    def test_a_bad_command_is_refused(self):
        for args in (["for"], ["for", "0"], ["for", "x"], ["sometimes"]):
            with self.assertRaises(ValueError):
                ka.next_state(args, False, 100)


class Pill(unittest.TestCase):
    def test_off_shows_a_dimmed_cup_that_a_right_click_turns_on(self):
        p = ka.render(False, None, [], 100, "/bin/ka")
        self.assertEqual((p["icon"], p["color"], p["label"]), (ka.AWAKE_ICON, "muted", ""))
        self.assertEqual(p["right_click"], "/bin/ka toggle")
        self.assertEqual((p["panel"]["on"], p["panel"]["until"], p["panel"]["last"]), (False, None, "on"))

    def test_on_shows_the_accent_cup(self):
        p = ka.render(True, None, [], 100, "/bin/ka")
        self.assertEqual((p["color"], p["label"]), ("accent", ""))
        self.assertTrue(p["panel"]["on"])

    def test_the_panel_carries_the_last_chosen_time(self):
        self.assertEqual(ka.render(False, None, [], 100, "/bin/ka", "for 30")["panel"]["last"], "for 30")

    def test_a_timed_run_shows_the_time_left(self):
        self.assertEqual(ka.render(True, 100 + 45 * 60, [], 100, "/bin/ka")["label"], "45m")
        self.assertEqual(ka.render(True, 100 + 65 * 60, [], 100, "/bin/ka")["label"], "1h 5m")

    def test_another_holder_lights_the_cup_while_ours_is_off(self):
        p = ka.render(False, None, [("Steam", 812, "01:26:17")], 100, "/bin/ka")
        self.assertEqual(p["color"], "accent")
        self.assertEqual(p["panel"]["holders"][0]["name"], "Steam")


class OwnHold(unittest.TestCase):
    def test_the_bar_is_not_listed_as_another_holder(self):
        self.assertTrue(ka.is_own("omacchiato-bar"))
        self.assertFalse(ka.is_own("Steam"))


if __name__ == "__main__":
    unittest.main()
