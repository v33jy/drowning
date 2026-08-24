import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from camera_controller import CameraController


class FakePublisher:
    def __init__(self) -> None:
        self.running = False
        self.start_count = 0
        self.stop_count = 0

    def start(self) -> None:
        self.running = True
        self.start_count += 1

    def stop(self) -> None:
        self.running = False
        self.stop_count += 1


class CameraControllerTests(unittest.TestCase):
    def test_fpga_arm_starts_publisher_once(self) -> None:
        publisher = FakePublisher()
        controller = CameraController(publisher, enabled=True, hold_seconds=20)

        controller.update(camera_arm=True, detected=False, now=10)
        controller.update(camera_arm=True, detected=True, now=11)

        self.assertTrue(publisher.running)
        self.assertEqual(publisher.start_count, 1)

    def test_inactive_signal_stops_only_after_hold(self) -> None:
        publisher = FakePublisher()
        controller = CameraController(publisher, enabled=True, hold_seconds=20)

        controller.update(camera_arm=True, detected=False, now=10)
        controller.update(camera_arm=False, detected=False, now=29)
        self.assertTrue(publisher.running)

        controller.update(camera_arm=False, detected=False, now=30)
        self.assertFalse(publisher.running)

    def test_disabled_controller_never_starts_publisher(self) -> None:
        publisher = FakePublisher()
        controller = CameraController(publisher, enabled=False, hold_seconds=0)

        controller.update(camera_arm=True, detected=True, now=0)

        self.assertFalse(publisher.running)


if __name__ == "__main__":
    unittest.main()
