import unittest

from signal_pipeline.fpga_protocol import (
    PACKET_SIZE,
    decode_iq_packet,
    encode_iq_frame,
)
from signal_pipeline.mock_fpga import MockFpgaTransport
from signal_pipeline.mock_sdr import MockSdrSource
from signal_pipeline.pipeline import SignalPipeline


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
    def test_detects_expected_fft_peak_bin(self) -> None:
        source = MockSdrSource(
            tone_bin=3,
            noise_amplitude=0,
        )
        fpga = MockFpgaTransport(
            detection_threshold_dbm=-20.0,
        )

        frame = source.next_frame()
        packet = encode_iq_frame(frame)
        result = fpga.process(packet)

        self.assertEqual(result.sequence, frame.sequence)
        self.assertEqual(result.peak_bin, 3)
        self.assertTrue(result.detected)


class SignalPipelineTests(unittest.TestCase):
    def test_processes_frames_in_sequence(self) -> None:
        pipeline = SignalPipeline(
            sdr_source=MockSdrSource(
                tone_bin=3,
                noise_amplitude=0,
            ),
            fpga_transport=MockFpgaTransport(
                detection_threshold_dbm=-20.0,
            ),
        )

        first_result = pipeline.process_next_frame()
        second_result = pipeline.process_next_frame()

        self.assertEqual(first_result.sequence, 0)
        self.assertEqual(second_result.sequence, 1)
        self.assertEqual(first_result.peak_bin, 3)
        self.assertEqual(second_result.peak_bin, 3)


if __name__ == "__main__":
    unittest.main()