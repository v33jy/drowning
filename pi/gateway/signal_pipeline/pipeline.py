from signal_pipeline.fpga_protocol import encode_iq_frame
from signal_pipeline.mock_fpga import MockFpgaTransport
from signal_pipeline.mock_sdr import MockSdrSource
from signal_pipeline.models import FpgaResult


class SignalPipeline:
    """
    SDR 입력부터 FPGA 처리 결과까지의 전체 흐름을 관리한다.

    현재:
        MockSdrSource -> bytes 패킷 -> MockFpgaTransport

    나중:
        RtlSdrSource -> bytes 패킷 -> SpiFpgaTransport
    """

    def __init__(
        self,
        sdr_source: MockSdrSource,
        fpga_transport: MockFpgaTransport,
    ) -> None:
        self.sdr_source = sdr_source
        self.fpga_transport = fpga_transport

    def process_next_frame(self) -> FpgaResult:
        """
        다음 SDR 프레임 하나를 읽고 FPGA 처리 결과를 반환한다.
        """

        iq_frame = self.sdr_source.next_frame()

        fpga_packet = encode_iq_frame(iq_frame)

        result = self.fpga_transport.process(fpga_packet)

        if result.sequence != iq_frame.sequence:
            raise RuntimeError(
                "FPGA result sequence does not match the transmitted frame"
            )

        return result