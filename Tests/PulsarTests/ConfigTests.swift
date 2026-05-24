import XCTest
@testable import Pulsar

final class ConfigTests: XCTestCase {
    func testSanitizedConfigClampsUnsafeScalarValues() {
        let raw = Config(
            fps: 0,
            fft_size: 1000,
            band_count: 0,
            smoothing: 2,
            min_freq_hz: -10,
            max_freq_hz: 0,
            devices: [],
            enabled: true,
            effect: "spectrum",
            palette: "sunset",
            brightness: 2,
            speed: 4,
            intensity: -1,
            brightness_reactive: nil,
            brightness_aspect: nil,
            speed_reactive: nil,
            speed_aspect: nil,
            intensity_reactive: nil,
            intensity_aspect: nil
        )

        let cfg = raw.sanitized()

        XCTAssertEqual(cfg.fps, 1)
        XCTAssertEqual(cfg.fft_size, Config.default.fft_size)
        XCTAssertEqual(cfg.band_count, 1)
        XCTAssertEqual(cfg.smoothing, 0.99)
        XCTAssertEqual(cfg.min_freq_hz, Config.default.min_freq_hz)
        XCTAssertEqual(cfg.max_freq_hz, Config.default.max_freq_hz)
        XCTAssertEqual(cfg.brightness, 1)
        XCTAssertEqual(cfg.speed, 2)
        XCTAssertEqual(cfg.intensity, 0)
    }

    func testSanitizedConfigDropsInvalidDevicesAndClampsSegments() {
        let raw = Config(
            fps: 60,
            fft_size: 1024,
            band_count: 32,
            smoothing: 0.6,
            min_freq_hz: 40,
            max_freq_hz: 16000,
            devices: [
                DeviceConfig(
                    name: "  Desk  ",
                    ip: "  192.0.2.42  ",
                    pixel_count: 10,
                    rgbw: false,
                    brightness: -1,
                    enabled: true,
                    segments: [
                        SegmentConfig(start: -5, length: 20, reverse: true, mirror: false),
                        SegmentConfig(start: 20, length: 1, reverse: false, mirror: false),
                    ],
                    min_load: nil,
                    mirror: nil,
                    reverse: nil,
                    effect: nil
                ),
                DeviceConfig(
                    name: "",
                    ip: "192.0.2.43",
                    pixel_count: 10,
                    rgbw: false,
                    brightness: nil,
                    enabled: nil,
                    segments: nil,
                    min_load: nil,
                    mirror: nil,
                    reverse: nil,
                    effect: nil
                ),
            ],
            enabled: true,
            effect: "spectrum",
            palette: "sunset",
            brightness: 1,
            speed: 1,
            intensity: 1,
            brightness_reactive: nil,
            brightness_aspect: nil,
            speed_reactive: nil,
            speed_aspect: nil,
            intensity_reactive: nil,
            intensity_aspect: nil
        )

        let cfg = raw.sanitized()

        XCTAssertEqual(cfg.devices.count, 1)
        XCTAssertEqual(cfg.devices[0].name, "Desk")
        XCTAssertEqual(cfg.devices[0].ip, "192.0.2.42")
        XCTAssertEqual(cfg.devices[0].brightness, 0)
        XCTAssertEqual(cfg.devices[0].segments?.count, 2)
        XCTAssertEqual(cfg.devices[0].segments?[0].start, 0)
        XCTAssertEqual(cfg.devices[0].segments?[0].length, 10)
        // start=20 is clamped to pixelCount-1=9; available=1 so length=1.
        XCTAssertEqual(cfg.devices[0].segments?[1].start, 9)
        XCTAssertEqual(cfg.devices[0].segments?[1].length, 1)
    }
}
