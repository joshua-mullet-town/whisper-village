// Regression check for BrowserOriginGate — run via scripts/test-origin-gate.sh.
// A website on this Mac must not be able to drive :8179; the presenter,
// hey-alfred (Python, no Origin) and curl must keep working.
import Foundation

var failures = 0, passes = 0
func expect(_ ok: Bool, _ label: String, _ req: String) {
    let v = BrowserOriginGate.decide(req)
    if v.ok == ok { passes += 1 } else { failures += 1; print("not ok - \(label): got \(v)") }
}
func req(_ line: String, _ headers: [String] = [], body: String = "") -> String {
    ([line] + headers).joined(separator: "\r\n") + "\r\n\r\n" + body
}

let evil = "Origin: https://evil.example"
// Websites: refused
expect(false, "evil preflight", req("OPTIONS /start HTTP/1.1", [evil, "Access-Control-Request-Method: POST"]))
expect(false, "evil POST /start text/plain", req("POST /start HTTP/1.1", [evil, "Content-Type: text/plain"], body: "{\"deliverTo\":\"x\"}"))
expect(false, "evil POST /peek", req("POST /peek HTTP/1.1", [evil]))
expect(false, "evil GET /peek", req("GET /peek HTTP/1.1", ["origin: https://EVIL.example"]))
expect(false, "Origin null", req("POST /peek HTTP/1.1", ["Origin: null"]))
expect(false, "look-alike port", req("POST /peek HTTP/1.1", ["Origin: http://localhost:30050"]))
expect(false, "<img src=/start> (no Origin, cross-site)", req("GET /start HTTP/1.1", ["Sec-Fetch-Site: cross-site", "Sec-Fetch-Mode: no-cors"]))
expect(false, "window.open(/peek)", req("GET /peek HTTP/1.1", ["Sec-Fetch-Site: cross-site", "Sec-Fetch-Mode: navigate"]))
expect(false, "same-site other port <img>", req("GET /start HTTP/1.1", ["Sec-Fetch-Site: same-site"]))
// Real clients: allowed
expect(true, "presenter POST /peek", req("POST /peek HTTP/1.1", ["Origin: http://localhost:3005"]))
expect(true, "presenter preflight /claim", req("OPTIONS /claim HTTP/1.1", ["Origin: http://localhost:3005", "Access-Control-Request-Method: POST"]))
expect(true, "presenter POST /claim json", req("POST /claim HTTP/1.1", ["Origin: http://localhost:3005", "Content-Type: application/json"], body: "{\"cardId\":\"x\"}"))
expect(true, "hey-alfred POST /start (python urllib)", req("POST /start HTTP/1.1", ["Host: localhost:8179", "User-Agent: Python-urllib/3.9", "Content-Type: application/json"], body: "{}"))
expect(true, "curl GET /status", req("GET /status HTTP/1.1", ["Host: localhost:8179", "User-Agent: curl/8.7.1"]))
expect(true, "health from anywhere", req("GET /health HTTP/1.1", ["Sec-Fetch-Site: cross-site"]))
// Echo, never wildcard
let v = BrowserOriginGate.decide(req("POST /peek HTTP/1.1", ["Origin: http://localhost:3005"]))
if v.allowOrigin == "http://localhost:3005" { passes += 1 } else { failures += 1; print("not ok - echoes exact origin: \(v)") }

print("# pass \(passes)")
print("# fail \(failures)")
exit(failures == 0 ? 0 : 1)
