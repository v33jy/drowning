import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import ConfigError, Settings


class SettingsTests(unittest.TestCase):
    def test_rejects_invalid_timeout_with_variable_name(self) -> None:
        with patch.dict(os.environ, {"REQUEST_TIMEOUT": "soon"}, clear=True):
            with self.assertRaisesRegex(ConfigError, "REQUEST_TIMEOUT"):
                Settings()

    def test_rejects_unknown_input_mode(self) -> None:
        with patch.dict(os.environ, {"INPUT_MODE": "other"}, clear=True):
            with self.assertRaisesRegex(ConfigError, "INPUT_MODE"):
                Settings()

    def test_rejects_invalid_server_url(self) -> None:
        with patch.dict(os.environ, {"SERVER_URL": "localhost:8001"}, clear=True):
            with self.assertRaisesRegex(ConfigError, "SERVER_URL"):
                Settings()

    def test_rejects_excessive_retry_count(self) -> None:
        with patch.dict(os.environ, {"MAX_RETRIES": "100"}, clear=True):
            with self.assertRaisesRegex(ConfigError, "MAX_RETRIES"):
                Settings()


if __name__ == "__main__":
    unittest.main()
