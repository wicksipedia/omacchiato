import unittest

from loader import load

airpods = load("omacchiato-airpods")
TYPES = {0x2014: ("com.apple.airpods-pro-gen2", "AirPods Pro (2nd generation)"),
         0x201F: ("com.apple.airpods-max-2024", None)}


class Model(unittest.TestCase):
    def test_carries_the_type_identifier_for_the_panel_image(self):
        info = {"device_vendorID": "0x004C", "device_productID": "0x2014"}
        self.assertEqual(airpods.airpods_model(TYPES, info),
                         ("AirPods Pro (2nd generation)", airpods.EARBUDS, "com.apple.airpods-pro-gen2"))

    def test_falls_back_to_the_family_name(self):
        info = {"device_vendorID": "0x004C", "device_productID": "0x201F"}
        self.assertEqual(airpods.airpods_model(TYPES, info)[0], "AirPods Max")


class PanelDevice(unittest.TestCase):
    def test_lists_each_mode_with_its_command(self):
        device = airpods.panel_device("/bin/airpods-control", "Matt’s AirPods Pro", "AirPods Pro",
                                      "com.apple.airpods-pro-gen2", {"Left": 83, "Case": 52}, False,
                                      ("adaptive", ["off", "adaptive"]))
        self.assertEqual(device["mode"], "adaptive")
        self.assertEqual([m["title"] for m in device["modes"]], ["Off", "Adaptive"])
        self.assertEqual(device["modes"][0]["run"],
                         "/bin/airpods-control --device 'Matt’s AirPods Pro' listening-mode set off")

    def test_no_control_tool_means_no_modes(self):
        device = airpods.panel_device(None, "Max", "AirPods Max", "com.apple.airpods-max-2024",
                                      {"Battery": 40}, True, None)
        self.assertNotIn("modes", device)
        self.assertTrue(device["cable"])


if __name__ == "__main__":
    unittest.main()
