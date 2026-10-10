import Foundation

/// Refuses requests sent by WEBSITES open in a browser on this Mac.
///
/// 2026-10-10: PeerGate admits loopback, and a web page's requests to
/// localhost:8179 arrive as loopback. With `Access-Control-Allow-Origin: *`
/// any website could read /peek (Josh's last dictation) or POST /start (open
/// the mic and send the transcript to a steward). Even without CORS approval a
/// page can still SEND a GET, or a text/plain POST, and the side effect happens.
///
/// The rule (mirrors homestead/lib/origin-guard.js):
///   - Host must be ours (localhost, the tailnet name, an IP literal): stops DNS rebinding.
///   - No Origin and no Sec-Fetch-Site (hey-alfred's Python, curl, Swift): allowed.
///   - Origin present: allowed only if it is the presenter's origin. "null" never.
///   - No Origin but Sec-Fetch-Site says another site (an <img>, a link,
///     window.open): refused, except GET /health.
///
/// Pure and dependency-free so `scripts/test-origin-gate.sh` can compile it alone.
enum BrowserOriginGate {
    /// The presenter page (Electron and the desktop web dashboard) is served by
    /// Homestead on :3005 and fetches /peek, /claim and /status from here.
    static let allowedOrigins: Set<String> = [
        "http://localhost:3005",
        "http://127.0.0.1:3005",
        "http://joshuas-macbook-air.tail84bb3b.ts.net:3005",
        "http://joshuas-macbook-air:3005",
    ]

    struct Verdict: Equatable {
        let ok: Bool
        let reason: String
        /// The origin to echo in Access-Control-Allow-Origin, if any.
        let allowOrigin: String?
    }

    /// Case-insensitive header lookup over a raw HTTP/1.1 request.
    static func header(_ name: String, in request: String) -> String? {
        let head = request.components(separatedBy: "\r\n\r\n").first ?? request
        let wanted = name.lowercased() + ":"
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            if line.lowercased().hasPrefix(wanted) {
                return String(line.dropFirst(wanted.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// DNS rebinding: a page re-points its own domain at 127.0.0.1 and becomes
    /// same-origin with us (no Origin header, readable answers). Its Host header
    /// still names the attacker's domain, so Host must be one of ours or an IP.
    static let allowedHostNames: Set<String> = [
        "localhost", "joshuas-macbook-air.tail84bb3b.ts.net", "joshuas-macbook-air",
    ]

    static func isHostAllowed(_ host: String?) -> Bool {
        guard let host = host?.lowercased().trimmingCharacters(in: .whitespaces) else { return true }
        if host.hasPrefix("[") { return host.contains("]") } // IPv6 literal
        var name = host
        if let colon = name.lastIndex(of: ":") { name = String(name[..<colon]) }
        if name.hasSuffix(".") { name.removeLast() }
        if name.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil { return true }
        return allowedHostNames.contains(name)
    }

    static func decide(_ request: String) -> Verdict {
        if !isHostAllowed(header("Host", in: request)) {
            return Verdict(ok: false, reason: "host-not-allowed:\(header("Host", in: request) ?? "")", allowOrigin: nil)
        }
        let requestLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init)?.uppercased() ?? ""
        let path = parts.count > 1 ? String(parts[1].split(separator: "?").first ?? "") : ""

        if let origin = header("Origin", in: request) {
            let o = origin.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if allowedOrigins.contains(o) { return Verdict(ok: true, reason: "origin-allowed", allowOrigin: origin) }
            return Verdict(ok: false, reason: "origin-not-allowed:\(origin)", allowOrigin: nil)
        }
        let site = header("Sec-Fetch-Site", in: request)?.lowercased() ?? ""
        if site.isEmpty || site == "same-origin" || site == "none" {
            return Verdict(ok: true, reason: site.isEmpty ? "no-browser-headers" : "sec-fetch-site:\(site)", allowOrigin: nil)
        }
        if method == "GET" && path == "/health" {
            return Verdict(ok: true, reason: "cross-site-health", allowOrigin: nil)
        }
        return Verdict(ok: false, reason: "cross-site-\(method)-no-origin:\(path)", allowOrigin: nil)
    }
}
