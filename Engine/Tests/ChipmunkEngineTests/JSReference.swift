import Foundation
import JavaScriptCore

/// The original JavaScript engine, loaded straight from web/chipmunk-challenge.html, used as the reference the Swift
/// port is checked against.
final class JSReference {
    static let shared = JSReference()

    let ctx: JSContext
    private(set) var lastError: String?

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private init() {
        let html = try! String(contentsOf: Self.repoRoot.appendingPathComponent("web/chipmunk-challenge.html"),
                               encoding: .utf8)
        let open = html.range(of: "<script id=\"engine\">")!
        let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex)!
        let source = String(html[open.upperBound..<close.lowerBound])
        ctx = JSContext()!
        ctx.exceptionHandler = { [weak self] _, ex in self?.lastError = ex?.toString() }
        ctx.evaluateScript("var performance = { now: () => Date.now() };")
        ctx.evaluateScript(source)
        precondition(lastError == nil, "Engine script failed: \(lastError!)")
        // Helpers for the tests: the base a Level Play board is built from (as the page's baseOf does).
        ctx.evaluateScript("""
        function testBase(i){const L=LEVELS[i],n=i<RAMP_N?i+1:0;const b={name:L.name,rows:L.rows};
          if(n){const rk=rocksFor(L.rows,n);if(rk)b.rocks=rk;if(lockFor(n))b.lock=true;if(n>=LOCK_FROM)b.lockOK=true}return b}
        """)
    }

    /// Evaluate a JS expression and return it as JSON text.
    func json(_ expr: String) -> String {
        lastError = nil
        let v = ctx.evaluateScript("JSON.stringify((()=>{return \(expr)})())")
        precondition(lastError == nil, "JS error in \(expr): \(lastError!)")
        return v!.toString()
    }

    func decode<T: Decodable>(_ type: T.Type, _ expr: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(json(expr).utf8))
    }

    func run(_ code: String) {
        lastError = nil
        ctx.evaluateScript(code)
        precondition(lastError == nil, "JS error: \(lastError!)")
    }
}
