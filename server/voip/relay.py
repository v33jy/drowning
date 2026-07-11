"""
UDP VoIP relay
==============
Runs inside the same asyncio event loop as FastAPI (started in main.py lifespan).

Packet format (binary, big-endian)
-----------------------------------
  Bytes  0-15 : session_id as UUID bytes (16 bytes)
  Byte  16    : Role  —  0 = survivor,  1 = control app
  Bytes 17-20 : sequence number (uint32)
  Bytes 21+   : Opus audio payload

The server does no audio processing — it reads the header, looks up the session,
updates the sender's address, and forwards the raw packet to the other party.
If the other party's address is not yet known the packet is silently dropped;
the next packet will succeed once both sides have registered.

Why binary header instead of JSON framing:
  Audio packets arrive at 50 pps (20 ms/frame).  A fixed 21-byte binary header
  adds negligible overhead and keeps the relay well under 1 ms per packet.
"""

from __future__ import annotations

import asyncio
import enum
import logging
import struct
import uuid
from typing import Optional

from .session import VoIPSession

logger = logging.getLogger(__name__)

_HEADER = struct.Struct("!16sBL")  # uuid(16) + role(1) + seq(4)
HEADER_SIZE = _HEADER.size  # 21 bytes

UDP_PORT = 5005


class Role(enum.IntEnum):
    SURVIVOR = 0
    CONTROL = 1


class VoIPRelay(asyncio.DatagramProtocol):
    """asyncio UDP protocol that cross-routes audio packets between two parties."""

    def __init__(self, sessions: dict[str, VoIPSession]) -> None:
        self._sessions = sessions
        self._transport: Optional[asyncio.DatagramTransport] = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self._transport = transport  # type: ignore[assignment]  # always DatagramTransport here
        logger.info("VoIP UDP relay listening on port %d", UDP_PORT)

    def datagram_received(self, data: bytes, addr: tuple) -> None:
        if len(data) < HEADER_SIZE:
            return

        uuid_bytes, role_byte, _seq = _HEADER.unpack_from(data)

        try:
            session_id = str(uuid.UUID(bytes=uuid_bytes))
            role = Role(role_byte)
        except (ValueError, KeyError):
            return

        session = self._sessions.get(session_id)
        if session is None or not session.active:
            return

        if role is Role.SURVIVOR:
            session.survivor_addr = addr
            target = session.control_addr
        else:
            session.control_addr = addr
            target = session.survivor_addr

        if target is not None and self._transport is not None:
            self._transport.sendto(data, target)

    def error_received(self, exc: Exception) -> None:
        logger.warning("VoIP relay error: %s", exc)

    def connection_lost(self, exc: Optional[Exception]) -> None:
        logger.info("VoIP relay transport closed.")


async def start_relay(sessions: dict[str, VoIPSession]) -> asyncio.DatagramTransport:
    """Start the UDP relay and return the transport for clean shutdown."""
    loop = asyncio.get_running_loop()
    transport, _ = await loop.create_datagram_endpoint(
        lambda: VoIPRelay(sessions),
        local_addr=("0.0.0.0", UDP_PORT),
    )
    return transport  # type: ignore[return-value]
