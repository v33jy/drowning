import struct

from signal_pipeline.models import IQFrame


MAGIC = b"\xAA\x55"
VERSION = 1
FFT_SIZE = 1024

_HEADER_FORMAT = ">2sBHI"
_SAMPLE_FORMAT = ">hh"

HEADER_SIZE = struct.calcsize(_HEADER_FORMAT)
SAMPLE_SIZE = struct.calcsize(_SAMPLE_FORMAT)
PACKET_SIZE = HEADER_SIZE + FFT_SIZE * SAMPLE_SIZE


class FpgaProtocolError(ValueError):
    """FPGA 송수신 패킷 형식이 올바르지 않을 때 발생한다."""


def encode_iq_frame(frame: IQFrame) -> bytes:
    """
    IQFrame을 FPGA SPI 전송용 바이트 패킷으로 변환한다.

    패킷 구성:
    MAGIC(2바이트) + VERSION(1바이트) + SAMPLE_COUNT(2바이트, 최대 1024라 1바이트로는 못 담음)
    + SEQUENCE(4바이트) + I/Q 샘플 1024쌍(각 4바이트)
    """

    if len(frame.samples) != FFT_SIZE:
        raise FpgaProtocolError(
            f"Expected {FFT_SIZE} I/Q samples, got {len(frame.samples)}"
        )

    if frame.sequence > 0xFFFFFFFF:
        raise FpgaProtocolError("sequence must fit in unsigned 32-bit range")

    packet = bytearray()

    packet.extend(
        struct.pack(
            _HEADER_FORMAT,
            MAGIC,
            VERSION,
            len(frame.samples),
            frame.sequence,
        )
    )

    for i_value, q_value in frame.samples:
        packet.extend(
            struct.pack(
                _SAMPLE_FORMAT,
                i_value,
                q_value,
            )
        )

    return bytes(packet)


def decode_iq_packet(
    packet: bytes,
    sample_rate_hz: int = 2_400_000,
    center_frequency_hz: int = 915_000_000,
) -> IQFrame:
    """
    전송된 바이트 패킷을 다시 IQFrame으로 복원한다.

    현재는 Mock FPGA가 Raspberry Pi에서 만든 패킷을 검사하기 위해 사용한다.
    나중에는 FPGA 테스트벤치나 디버깅 코드에서도 같은 규격을 참고할 수 있다.

    패킷 자체엔 sample_rate_hz/center_frequency_hz가 안 실려있어서(IQ 샘플과
    시퀀스만 전송됨), 호출하는 쪽이 실제 SDR 설정값을 넘겨줘야 한다 — 안 넘기면
    기본값으로 채워지는데, 이게 실제 SDR 설정과 다르면 IQFrame의 메타데이터만
    조용히 틀린 값이 된다.
    """

    if len(packet) != PACKET_SIZE:
        raise FpgaProtocolError(
            f"Expected packet size {PACKET_SIZE}, got {len(packet)}"
        )

    magic, version, sample_count, sequence = struct.unpack(
        _HEADER_FORMAT,
        packet[:HEADER_SIZE],
    )

    if magic != MAGIC:
        raise FpgaProtocolError("Invalid packet magic")

    if version != VERSION:
        raise FpgaProtocolError(f"Unsupported protocol version: {version}")

    if sample_count != FFT_SIZE:
        raise FpgaProtocolError(
            f"Expected sample count {FFT_SIZE}, got {sample_count}"
        )

    samples: list[tuple[int, int]] = []
    offset = HEADER_SIZE

    for _ in range(sample_count):
        sample_end = offset + SAMPLE_SIZE
        i_value, q_value = struct.unpack(
            _SAMPLE_FORMAT,
            packet[offset:sample_end],
        )
        samples.append((i_value, q_value))
        offset = sample_end

    return IQFrame(
        sequence=sequence,
        sample_rate_hz=sample_rate_hz,
        center_frequency_hz=center_frequency_hz,
        samples=samples,
    )
