import unittest

from signal_pipeline.fpga_protocol import (
    PACKET_SIZE,
    decode_iq_packet,
    encode_iq_frame,
)
from signal_pipeline.fpga_result_protocol import (
    FpgaResultProtocolError,
    decode_fpga_result,
    encode_fpga_result,
)
from signal_pipeline.mock_fpga import MockFpgaTransport
from signal_pipeline.mock_sdr import MockSdrSource
from signal_pipeline.models import FpgaResult
from signal_pipeline.pipeline import SignalPipeline
from signal_pipeline.rtl_sdr import RtlSdrSource
from signal_pipeline.spi_fpga import SpiFpgaTransport


class MockSdrSourceTests(unittest.TestCase):
    def test_generates_1024_iq_samples(self) -> None:
        source = MockSdrSource()

        frame = source.next_frame()

        self.assertEqual(frame.sequence, 0)
        self.assertEqual(len(frame.samples), 1024)


class FpgaProtocolTests(unittest.TestCase):
    def test_encode_and_decode_preserve_frame(self) -> None:
        source = MockSdrSource()
        original = source.next_frame()

        packet = encode_iq_frame(original)
        restored = decode_iq_packet(packet)

        self.assertEqual(len(packet), PACKET_SIZE)
        self.assertEqual(restored.sequence, original.sequence)
        self.assertEqual(restored.samples, original.samples)


class MockFpgaTransportTests(unittest.TestCase):
    def test_detects_tone_at_target_bin(self) -> None:
        # fpga/rtl/spectrum_analyzer.v의 TARGET_BIN=128과 맞춰야 detected=True가 됨.
        source = MockSdrSource(
            tone_bin=128,
            noise_amplitude=0,
        )
        fpga = MockFpgaTransport()

        frame = source.next_frame()
        packet = encode_iq_frame(frame)
        result = fpga.process(packet)

        self.assertEqual(result.sequence, frame.sequence)
        self.assertEqual(result.peak_bin, 128)
        self.assertTrue(result.detected)

    def test_does_not_detect_tone_off_target_bin(self) -> None:
        # target_bin(128)/interference_bin(310) 대역 밖의 신호는
        # 아무리 세도 detected=False여야 함 — RTL과 같은 판정 기준인지 확인.
        source = MockSdrSource(
            tone_bin=3,
            noise_amplitude=0,
        )
        fpga = MockFpgaTransport()

        frame = source.next_frame()
        packet = encode_iq_frame(frame)
        result = fpga.process(packet)

        self.assertEqual(result.peak_bin, 3)
        self.assertFalse(result.detected)


class SignalPipelineTests(unittest.TestCase):
    def test_processes_frames_in_sequence(self) -> None:
        pipeline = SignalPipeline(
            sdr_source=MockSdrSource(
                tone_bin=128,
                noise_amplitude=0,
            ),
            fpga_transport=MockFpgaTransport(),
        )

        first_result = pipeline.process_next_frame()
        second_result = pipeline.process_next_frame()

        self.assertEqual(first_result.sequence, 0)
        self.assertEqual(second_result.sequence, 1)
        self.assertEqual(first_result.peak_bin, 128)
        self.assertEqual(second_result.peak_bin, 128)


class RtlSdrSourceTests(unittest.TestCase):
    def test_converts_samples_to_integer_iq_values(self) -> None:
        class FakeSdr:
            def read_samples(self, count: int):
                return [0.5 + 0.25j] * count

        source = RtlSdrSource()
        source._sdr = FakeSdr()

        frame = source.next_frame()

        self.assertEqual(len(frame.samples), 1024)
        self.assertEqual(frame.samples[0], (16384, 8192))
        self.assertIsInstance(frame.samples[0][0], int)
        self.assertIsInstance(frame.samples[0][1], int)

    def test_close_releases_device(self) -> None:
        class FakeSdr:
            closed = False

            def close(self) -> None:
                self.closed = True

        source = RtlSdrSource()
        fake_sdr = FakeSdr()
        source._sdr = fake_sdr

        source.close()

        self.assertIsNone(source._sdr)
        self.assertTrue(fake_sdr.closed)


class SpiFpgaTransportTests(unittest.TestCase):
    def test_rejects_wrong_input_packet_size(self) -> None:
        transport = SpiFpgaTransport()
        transport._spi = object()

        with self.assertRaisesRegex(ValueError, "input packet size"):
            transport.process(b"short")

    def test_processes_fpga_result_packet(self) -> None:
        expected = FpgaResult(
            sequence=0,
            peak_bin=128,
            peak_power=100.0,
            target_power=90.0,
            noise_floor=10.0,
            rss_dbm=-18.5,
            detected=True,
        )
        result_packet = encode_fpga_result(expected)

        class FakeSpi:
            def __init__(self) -> None:
                self.transfer_count = 0

            def xfer2(self, data):
                self.transfer_count += 1
                if self.transfer_count == 1:
                    return [0] * len(data)
                return list(result_packet)

        transport = SpiFpgaTransport()
        transport._spi = FakeSpi()

        result = transport.process(bytes(PACKET_SIZE))

        self.assertEqual(result.sequence, expected.sequence)
        self.assertEqual(result.peak_bin, expected.peak_bin)
        self.assertTrue(result.detected)

    def test_rejects_out_of_range_result_bin(self) -> None:
        valid = encode_fpga_result(
            FpgaResult(0, 128, 1.0, 1.0, 1.0, -10.0, False)
        )
        malformed = valid[:7] + (1024).to_bytes(2, "big") + valid[9:]

        with self.assertRaisesRegex(FpgaResultProtocolError, "peak_bin"):
            decode_fpga_result(malformed)

    def test_close_releases_device(self) -> None:
        class FakeSpi:
            closed = False

            def close(self) -> None:
                self.closed = True

        transport = SpiFpgaTransport()
        fake_spi = FakeSpi()
        transport._spi = fake_spi

        transport.close()

        self.assertIsNone(transport._spi)
        self.assertTrue(fake_spi.closed)


if __name__ == "__main__":
    unittest.main()
