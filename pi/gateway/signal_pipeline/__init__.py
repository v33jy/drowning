"""
실제 RTL-SDR/FPGA(fpga/rtl/, SPI 연결)가 붙기 전까지의 규격·알고리즘 검증용
패키지. main.py에서 직접 쓰지 않고 tests/test_signal_pipeline.py로만
exercise된다.

MockSdrSource -> RtlSdrSource, MockFpgaTransport -> SpiFpgaTransport로
실제 하드웨어 드라이버가 생기면 이 mock 구현들은 지우고, fpga_protocol.py의
인코딩/디코딩 규격과 detected 판정 알고리즘(fpga/rtl/spectrum_analyzer.v와
동일하게 맞춰둔 것)만 이어받으면 된다.
"""
