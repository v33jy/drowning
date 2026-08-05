from dataclasses import dataclass


@dataclass(frozen=True)
class IQFrame:
    """
    RTL-SDR 또는 Mock SDR에서 생성한 I/Q 샘플 한 묶음.

    각 샘플은 (I, Q) 정수 쌍으로 저장한다.
    실제 RTL-SDR 연결 시에도 이 형식으로 변환하여
    이후 FPGA 전송 코드가 입력 장치 종류를 몰라도 되게 한다.
    """

    sequence: int
    sample_rate_hz: int
    center_frequency_hz: int
    samples: list[tuple[int, int]]

    def __post_init__(self) -> None:
        if self.sequence < 0:
            raise ValueError("sequence must be zero or greater")

        if self.sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz must be greater than zero")

        if self.center_frequency_hz <= 0:
            raise ValueError("center_frequency_hz must be greater than zero")

        if not self.samples:
            raise ValueError("samples must not be empty")

        for i_value, q_value in self.samples:
            if not -32768 <= i_value <= 32767:
                raise ValueError("I sample must fit in signed 16-bit range")

            if not -32768 <= q_value <= 32767:
                raise ValueError("Q sample must fit in signed 16-bit range")


@dataclass(frozen=True)
class FpgaResult:
    """
    FPGA가 I/Q 샘플을 처리한 뒤 Raspberry Pi에 반환할 결과.

    현재는 Mock FPGA가 생성하고,
    나중에는 실제 FPGA UART 또는 SPI 응답을 같은 형식으로 변환한다.
    """

    sequence: int
    peak_bin: int
    peak_power: float
    target_power: float
    noise_floor: float
    rss_dbm: float
    detected: bool

    def __post_init__(self) -> None:
        if self.sequence < 0:
            raise ValueError("sequence must be zero or greater")

        if self.peak_bin < 0:
            raise ValueError("peak_bin must be zero or greater")
