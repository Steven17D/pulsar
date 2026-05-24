import Foundation
import OSLog

struct DiscoveredWLED: Identifiable, Equatable {
    let serviceName: String
    var host: String
    var ip: String
    var port: Int
    var pixelCount: Int?
    var rgbw: Bool?
    var segmentCount: Int?
    var firmware: String?

    var id: String { ip.isEmpty ? serviceName : ip }
}

@MainActor
final class WLEDDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published private(set) var discovered: [DiscoveredWLED] = []

    private let log = Logger(subsystem: "io.pulsar.audio", category: "Discovery")
    private let browser = NetServiceBrowser()
    private var pending: [NetService] = []
    private var resolving: Set<ObjectIdentifier> = []

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        browser.stop()
        discovered.removeAll()
        pending.removeAll()
        resolving.removeAll()
        browser.searchForServices(ofType: "_wled._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        for svc in pending { svc.stop() }
        pending.removeAll()
        resolving.removeAll()
    }

    // MARK: - NetServiceBrowserDelegate

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            self.beginResolve(service)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let name = service.name
        Task { @MainActor in
            self.discovered.removeAll { $0.serviceName == name }
        }
    }

    private func beginResolve(_ service: NetService) {
        service.delegate = self
        pending.append(service)
        resolving.insert(ObjectIdentifier(service))
        service.resolve(withTimeout: 5)
    }

    // MARK: - NetServiceDelegate

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let host = sender.hostName ?? ""
        let port = sender.port
        let ip = Self.firstIPv4(from: sender.addresses ?? []) ?? ""
        Task { @MainActor in
            self.resolving.remove(ObjectIdentifier(sender))
            self.pending.removeAll { $0 === sender }
            guard !ip.isEmpty else { return }
            if let existing = self.discovered.firstIndex(where: { $0.ip == ip || $0.serviceName == name }) {
                self.discovered[existing].host = host
                self.discovered[existing].port = port
            } else {
                self.discovered.append(DiscoveredWLED(
                    serviceName: name, host: host, ip: ip, port: port,
                    pixelCount: nil, rgbw: nil, segmentCount: nil, firmware: nil
                ))
            }
            Task { await self.fetchMetadata(ip: ip) }
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor in
            self.resolving.remove(ObjectIdentifier(sender))
            self.pending.removeAll { $0 === sender }
        }
    }

    // MARK: - Metadata

    private func fetchMetadata(ip: String) async {
        guard let infoURL = URL(string: "http://\(ip)/json/info"),
              let cfgURL = URL(string: "http://\(ip)/json/cfg") else { return }
        var pixelCount: Int?
        var rgbw: Bool?
        var segCount: Int?
        var firmware: String?
        var req = URLRequest(url: infoURL); req.timeoutInterval = 3
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let leds = json["leds"] as? [String: Any] {
                pixelCount = leds["count"] as? Int
                rgbw = leds["rgbw"] as? Bool
            }
            firmware = json["ver"] as? String
        }
        req = URLRequest(url: cfgURL); req.timeoutInterval = 3
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hw = json["hw"] as? [String: Any],
           let led = hw["led"] as? [String: Any],
           let ins = led["ins"] as? [[String: Any]] {
            segCount = ins.count
        }
        if let idx = discovered.firstIndex(where: { $0.ip == ip }) {
            if let p = pixelCount { discovered[idx].pixelCount = p }
            if let w = rgbw { discovered[idx].rgbw = w }
            if let s = segCount { discovered[idx].segmentCount = s }
            if let f = firmware { discovered[idx].firmware = f }
        }
    }

    nonisolated private static func firstIPv4(from addresses: [Data]) -> String? {
        for data in addresses {
            let ip: String? = data.withUnsafeBytes { raw -> String? in
                guard let base = raw.baseAddress else { return nil }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                guard sa.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
                let sin = base.assumingMemoryBound(to: sockaddr_in.self)
                var addr = sin.pointee.sin_addr
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buf)
            }
            if let ip { return ip }
        }
        return nil
    }
}
