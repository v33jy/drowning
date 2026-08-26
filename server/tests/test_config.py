import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import config


class EnvironmentConfigTests(unittest.TestCase):
    def test_integer_error_names_the_environment_variable(self):
        with patch.dict(os.environ, {"TEST_COUNT": "many"}):
            with self.assertRaisesRegex(RuntimeError, "TEST_COUNT must be an integer"):
                config._env_int("TEST_COUNT", 1)

    def test_integer_minimum_is_validated(self):
        with patch.dict(os.environ, {"TEST_COUNT": "0"}):
            with self.assertRaisesRegex(RuntimeError, "at least 1"):
                config._env_int("TEST_COUNT", 1, minimum=1)

    def test_cors_origins_are_split_and_trimmed(self):
        with patch.dict(
            os.environ,
            {"CORS_ORIGINS": "https://control.example, http://localhost:8080"},
        ):
            self.assertEqual(
                config._env_origins(),
                ["https://control.example", "http://localhost:8080"],
            )

    def test_invalid_cors_origin_is_rejected(self):
        with patch.dict(os.environ, {"CORS_ORIGINS": "control.example"}):
            with self.assertRaisesRegex(RuntimeError, "invalid HTTP"):
                config._env_origins()

    def test_landmarks_must_be_a_json_object(self):
        with self.assertRaisesRegex(RuntimeError, "JSON object"):
            config._load_grid_landmarks("[]", False)

    def test_priority_file_permission_error_has_context(self):
        path = Path("/restricted/priorities.json")
        with patch.object(Path, "read_text", side_effect=PermissionError):
            with self.assertRaisesRegex(RuntimeError, "permission denied"):
                config._load_grid_priorities(path)

    def test_priority_file_io_error_has_context(self):
        path = Path("/broken/priorities.json")
        with patch.object(Path, "read_text", side_effect=OSError("I/O error")):
            with self.assertRaisesRegex(RuntimeError, "Could not read.*I/O error"):
                config._load_grid_priorities(path)


if __name__ == "__main__":
    unittest.main()
