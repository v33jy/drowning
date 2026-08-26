import asyncio
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from ws_manager import ConnectionManager


class FakeWebSocket:
    def __init__(self, behavior="ok"):
        self.behavior = behavior
        self.messages = []
        self.closed = False

    async def send_text(self, payload):
        if self.behavior == "slow":
            await asyncio.Event().wait()
        if self.behavior == "error":
            raise ConnectionError("disconnected")
        self.messages.append(payload)

    async def close(self, code=1000):
        self.closed = True


class WebSocketManagerTests(unittest.IsolatedAsyncioTestCase):
    async def test_slow_and_dead_clients_do_not_block_healthy_client(self):
        manager = ConnectionManager()
        healthy = FakeWebSocket()
        slow = FakeWebSocket("slow")
        dead = FakeWebSocket("error")
        manager._clients.extend([slow, healthy, dead])

        with patch("ws_manager.config.WS_SEND_TIMEOUT_SECONDS", 0.01):
            await manager.broadcast({"type": "update"})

        self.assertEqual(healthy.messages, ['{"type": "update"}'])
        self.assertEqual(manager._clients, [healthy])
        self.assertTrue(slow.closed)
        self.assertTrue(dead.closed)
        self.assertFalse(healthy.closed)

    async def test_broadcast_sends_to_all_healthy_clients(self):
        manager = ConnectionManager()
        clients = [FakeWebSocket(), FakeWebSocket()]
        manager._clients.extend(clients)

        await manager.broadcast({"label": "구조"})

        self.assertTrue(all('"구조"' in client.messages[0] for client in clients))


if __name__ == "__main__":
    unittest.main()
