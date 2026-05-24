import Darwin
import Foundation
import OSLog

/// Uses TCC SPI to preflight/request `kTCCServiceAudioCapture`. Required
/// because Process Tap permission cannot be requested through any public
/// API — `AudioHardwareCreateProcessTap` returns success and silently
/// delivers zero frames when TCC has not granted.
enum TCCAudioCapture {
    private static let log = Logger(subsystem: "io.pulsar.audio", category: "TCC")
    private static let service = "kTCCServiceAudioCapture" as CFString

    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let handle: UnsafeMutableRawPointer? = {
        let h = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
        if h == nil {
            let msg = dlerror().map { String(cString: $0) } ?? "unknown"
            log.error("dlopen TCC.framework failed: \(msg, privacy: .public)")
        }
        return h
    }()

    private static let preflight: PreflightFn? = {
        guard let h = handle, let sym = dlsym(h, "TCCAccessPreflight") else {
            log.error("dlsym TCCAccessPreflight failed")
            return nil
        }
        return unsafeBitCast(sym, to: PreflightFn.self)
    }()

    private static let request: RequestFn? = {
        guard let h = handle, let sym = dlsym(h, "TCCAccessRequest") else {
            log.error("dlsym TCCAccessRequest failed")
            return nil
        }
        return unsafeBitCast(sym, to: RequestFn.self)
    }()

    /// True iff both TCC SPI symbols loaded. False means we cannot preflight
    /// or request — the daemon should bail early because the tap would
    /// silently deliver zero frames.
    static var available: Bool { preflight != nil && request != nil }

    /// Return values: 0 = authorized, 1 = denied, anything else = unknown/not-yet-decided.
    static func status() -> Int { preflight?(service, nil) ?? -1 }

    /// Blocks until the user responds (or never returns if no UI session is up).
    static func requestBlocking(timeout: TimeInterval = 30) -> Bool {
        guard let request else { return false }
        let sem = DispatchSemaphore(value: 0)
        var result = false
        request(service, nil) { granted in
            result = granted
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
        return result
    }
}
