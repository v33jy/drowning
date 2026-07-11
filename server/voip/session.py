"""VoIP session state — one session per survivor detection event."""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from typing import Optional, Tuple


@dataclass
class VoIPSession:
    session_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    drone_id: int = 0
    cell_id: str = ""
    created_at: float = field(default_factory=time.time)
    # Filled in when each party sends their first audio packet.
    survivor_addr: Optional[Tuple[str, int]] = None
    control_addr: Optional[Tuple[str, int]] = None
    active: bool = True

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "drone_id": self.drone_id,
            "cell_id": self.cell_id,
            "created_at": self.created_at,
            "active": self.active,
        }
