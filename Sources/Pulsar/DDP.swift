import Foundation
import Network
import OSLog

/// DDP (Distributed Display Protocol) sender. WLED listens on UDP/4048.
/// Header layout (10 bytes):
///   [0] flags1: bit7..6 = version (01 = v1, so base = 0x40); bit0 = push
///       (commit the framebuffer). Set push ONLY on the final fragment of
///       a frame, so multi-packet frames render as a single update.
///   [1] sequence number (4 bits in low nibble), upper nibble unused
///   [2] data type: 0x0B = RGB888, 0x1B = RGBW8888
///   [3] id (1=display)
///   [4..7] offset (big-endian, byte offset within the LED stream)
///   [8..9] length (big-endian, number of payload bytes in this packet)
final class DDPSender {
    private let log = Logger(subsystem: "io.pulsar.audio", category: "DDP")
    private let host: String
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var seq: UInt8 = 0
    private let dataType: UInt8
    private var sendErrorLogAt: Date = .distantPast

    /// Per WLED max UDP payload safety; one frame of 240 RGBW LEDs = 960B fits well below MTU.
    private let maxPayload = 1440

    init(host: String, port: UInt16 = 4048, rgbw: Bool, queueLabel: String) {
        self.host = host
        self.dataType = rgbw ? 0x1B : 0x0B
        self.queue = DispatchQueue(label: queueLabel, qos: .userInteractive)
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        self.connection = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection.start(queue: queue)
    }

    func send(pixels: [UInt8]) {
        var offset = 0
        let total = pixels.count
        while offset < total {
            let chunk = min(maxPayload, total - offset)
            let isFinal = offset + chunk >= total
            var header = [UInt8](repeating: 0, count: 10)
            header[0] = isFinal ? 0x41 : 0x40
            seq = (seq &+ 1) & 0x0F
            header[1] = seq
            header[2] = dataType
            header[3] = 1
            header[4] = UInt8((offset >> 24) & 0xFF)
            header[5] = UInt8((offset >> 16) & 0xFF)
            header[6] = UInt8((offset >> 8) & 0xFF)
            header[7] = UInt8(offset & 0xFF)
            header[8] = UInt8((chunk >> 8) & 0xFF)
            header[9] = UInt8(chunk & 0xFF)
            var packet = Data(capacity: 10 + chunk)
            packet.append(contentsOf: header)
            packet.append(contentsOf: pixels[offset..<(offset + chunk)])
            // .contentProcessed surfaces ICMP-port-unreachable etc. via the
            // completion; .idempotent swallows them. Rate-limit the log
            // because a powered-off controller floods every frame.
            connection.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self, let error else { return }
                let now = Date()
                if now.timeIntervalSince(self.sendErrorLogAt) > 5.0 {
                    self.sendErrorLogAt = now
                    self.log.error("send to \(self.host, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            })
            offset += chunk
        }
    }

    func stop() { connection.cancel() }
    deinit { stop() }
}
