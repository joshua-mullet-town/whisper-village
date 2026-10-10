import Foundation
import Network

/// Decides, at connection accept, whether a peer may talk to us at all.
///
/// 2026-10-10 security lockdown: these listeners bind every interface, so
/// anyone on Josh's home Wi-Fi could type, paste and click on the Mac.
/// Allowed peers are ONLY:
///   - loopback (127.0.0.0/8, ::1), i.e. this Mac itself
///   - Tailscale peers (100.64.0.0/10, fd7a:115c:a1e0::/48) whose owner,
///     per `tailscale whois`, is one of Josh's own accounts (joshua@mullet.town
///     or his side-business jorymullet@gmail.com). The tailnet is shared with
///     family accounts, so "on the tailnet" alone is not enough.
/// Everything else is refused, and so is anything we can't verify (fail closed).
///
/// Checking the remote address (instead of binding to one interface) keeps
/// working when the Mac's Wi-Fi or tailnet address changes.
///
/// Every refusal, and every first allow of an address, is appended to
/// `~/Library/Logs/<app>-peers.log` so there is a record of who connected.
final class PeerGate {
    static let allowedOwners: Set<String> = ["joshua@mullet.town", "jorymullet@gmail.com"]
    static let shared = PeerGate(appName: "WhisperVillage")

    enum Verdict: Equatable {
        case allow(String)
        case deny(String)
        var allowed: Bool { if case .allow = self { return true }; return false }
    }

    /// Returns the tailnet owner's login name for an IP, or nil if unknown.
    /// Injectable so the gate can be unit-tested without a tailnet.
    var whois: (String) -> String? = PeerGate.tailscaleWhois

    private let logURL: URL
    private let queue = DispatchQueue(label: "peer-gate", qos: .userInitiated)
    private var cache: [String: (verdict: Verdict, expires: Date)] = [:]

    init(appName: String) {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        logURL = logs.appendingPathComponent("\(appName)-peers.log")
    }

    /// Vet a freshly accepted connection. Calls `onAllowed` (on the gate's
    /// queue) if the peer may proceed; otherwise cancels the connection
    /// without ever reading from it.
    func admit(_ conn: NWConnection, label: String, onAllowed: @escaping () -> Void) {
        queue.async {
            let ip = PeerGate.ipString(of: conn.endpoint)
            let verdict = self.cachedVerdict(for: ip, label: label)
            if verdict.allowed {
                onAllowed()
            } else {
                conn.cancel()
            }
        }
    }

    /// Pure classification, cached. Exposed for tests.
    func verdict(for ip: String?) -> Verdict {
        guard let ip = ip else { return .deny("unparseable peer address") }
        if PeerGate.isLoopback(ip) { return .allow("loopback") }
        if PeerGate.isTailnet(ip) {
            guard let owner = whois(ip) else { return .deny("tailnet peer, owner unknown") }
            return PeerGate.allowedOwners.contains(owner.lowercased())
                ? .allow("tailnet peer owned by \(owner)")
                : .deny("tailnet peer owned by \(owner)")
        }
        return .deny("not loopback or tailnet")
    }

    private func cachedVerdict(for ip: String?, label: String) -> Verdict {
        let key = ip ?? "?"
        if let hit = cache[key], hit.expires > Date() {
            if !hit.verdict.allowed { log(label: label, ip: key, verdict: hit.verdict) }
            return hit.verdict
        }
        let v = verdict(for: ip)
        // Loopback never changes; tailnet ownership is re-checked every 5 min.
        // Denials are re-checked sooner so a fixed whois hiccup heals fast.
        cache[key] = (v, Date().addingTimeInterval(v.allowed ? 300 : 30))
        log(label: label, ip: key, verdict: v)
        return v
    }

    private func log(label: String, ip: String, verdict: Verdict) {
        let stamp = ISO8601DateFormatter.localStamp.string(from: Date())
        let line: String
        switch verdict {
        case .allow(let why): line = "\(stamp) ALLOW \(label) \(ip) (\(why))\n"
        case .deny(let why): line = "\(stamp) REFUSE \(label) \(ip) (\(why))\n"
        }
        NSLog("PeerGate: \(line.trimmingCharacters(in: .newlines))")
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    // MARK: - Address helpers

    static func ipString(of endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        switch host {
        case .ipv4(let a):
            return ipv4String(a.rawValue)
        case .ipv6(let a):
            let b = [UInt8](a.rawValue)
            // Dual-stack listener: IPv4 peers arrive as ::ffff:a.b.c.d.
            if b.count == 16, b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff {
                return ipv4String(Data(b[12..<16]))
            }
            var sa = in6_addr()
            withUnsafeMutableBytes(of: &sa) { $0.copyBytes(from: b) }
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &sa, &buf, socklen_t(buf.count)) != nil else { return nil }
            return String(cString: buf)
        case .name(let n, _):
            return n
        @unknown default:
            return nil
        }
    }

    private static func ipv4String(_ d: Data) -> String? {
        let b = [UInt8](d)
        guard b.count == 4 else { return nil }
        return "\(b[0]).\(b[1]).\(b[2]).\(b[3])"
    }

    private static func ipv4Octets(_ ip: String) -> [UInt8]? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let o = parts.compactMap { UInt8($0) }
        return o.count == 4 ? o : nil
    }

    private static func ipv6Bytes(_ ip: String) -> [UInt8]? {
        var a = in6_addr()
        let bare = ip.split(separator: "%").first.map(String.init) ?? ip
        guard inet_pton(AF_INET6, bare, &a) == 1 else { return nil }
        return withUnsafeBytes(of: &a) { Array($0) }
    }

    static func isLoopback(_ ip: String) -> Bool {
        if let o = ipv4Octets(ip) { return o[0] == 127 }
        if let b = ipv6Bytes(ip) { return b[0..<15].allSatisfy { $0 == 0 } && b[15] == 1 }
        return false
    }

    static func isTailnet(_ ip: String) -> Bool {
        if let o = ipv4Octets(ip) { return o[0] == 100 && (o[1] & 0xC0) == 64 } // 100.64.0.0/10
        if let b = ipv6Bytes(ip) { return Array(b[0..<6]) == [0xfd, 0x7a, 0x11, 0x5c, 0xa1, 0xe0] } // fd7a:115c:a1e0::/48
        return false
    }

    // MARK: - tailscale whois

    static let tailscaleCandidates = [
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    static func tailscaleWhois(_ ip: String) -> String? {
        for path in tailscaleCandidates where FileManager.default.isExecutableFile(atPath: path) {
            if let owner = runWhois(path: path, ip: ip) { return owner }
        }
        return nil
    }

    private static func runWhois(path: String, ip: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["whois", "--json", ip]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let done = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + 3) == .timedOut {
            p.terminate()
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = obj["UserProfile"] as? [String: Any],
              let login = profile["LoginName"] as? String,
              !login.isEmpty
        else { return nil }
        return login
    }
}

private extension ISO8601DateFormatter {
    static let localStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
