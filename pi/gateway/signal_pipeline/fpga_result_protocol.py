import struct

from signal_pipeline.fpga_protocol import FFT_SIZE
from signal_pipeline.models import FpgaResult


RESULT_MAGIC = b"\x55\xAA"
RESULT_VERSION = 1
_RESULT_STRUCT = struct.Struct(">2sBIHdddfB")
RESULT_PACKET_SIZE = _RESULT_STRUCT.size


class FpgaResultProtocolError(ValueError):
    """Raised when an FPGA result packet violates the wire protocol."""


def _validate(sequence: int, peak_bin: int) -> None:
    if not 0 <= sequence <= 0xFFFFFFFF:
        raise FpgaResultProtocolError(
            "sequence must fit in unsigned 32-bit range"
        )
    if not 0 <= peak_bin < FFT_SIZE:
        raise FpgaResultProtocolError(
            f"peak_bin must be between 0 and {FFT_SIZE - 1}"
        )


def encode_fpga_result(result: FpgaResult) -> bytes:
    _validate(result.sequence, result.peak_bin)
    return _RESULT_STRUCT.pack(
        RESULT_MAGIC,
        RESULT_VERSION,
        result.sequence,
        result.peak_bin,
        result.peak_power,
        result.target_power,
        result.noise_floor,
        result.rss_dbm,
        int(result.detected),
    )


def decode_fpga_result(packet: bytes) -> FpgaResult:
    if len(packet) != RESULT_PACKET_SIZE:
        raise FpgaResultProtocolError(
            f"Expected result packet size {RESULT_PACKET_SIZE}, got {len(packet)}"
        )

    (
        magic,
        version,
        sequence,
        peak_bin,
        peak_power,
        target_power,
        noise_floor,
        rss_dbm,
        detected,
    ) = _RESULT_STRUCT.unpack(packet)

    if magic != RESULT_MAGIC:
        raise FpgaResultProtocolError("Invalid FPGA result magic")
    if version != RESULT_VERSION:
        raise FpgaResultProtocolError(
            f"Unsupported FPGA result version: {version}"
        )
    if detected not in (0, 1):
        raise FpgaResultProtocolError("detected field must be 0 or 1")
    _validate(sequence, peak_bin)

    try:
        return FpgaResult(
            sequence=sequence,
            peak_bin=peak_bin,
            peak_power=peak_power,
            target_power=target_power,
            noise_floor=noise_floor,
            rss_dbm=rss_dbm,
            detected=bool(detected),
        )
    except ValueError as error:
        raise FpgaResultProtocolError(
            f"Invalid FPGA result: {error}"
        ) from error
