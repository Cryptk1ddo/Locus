import XCTest
import JavaScriptCore
@testable import Search

final class NightCSSTests: XCTestCase {
    func evaluate(_ code: String) throws -> JSValue {
        let context = try XCTUnwrap(JSContext()); var exception: String?
        context.exceptionHandler = { _, e in exception = e?.toString() }
        context.evaluateScript("globalThis.CSS={supports:()=>false};" + NightColor.script + NightCSS.script)
        let value = try XCTUnwrap(context.evaluateScript("(()=>{const C=__locusNightCSS;return " + code + ";})()"))
        XCTAssertNil(exception); return value
    }
    func testBalancedGradientRetainsURLAndGeometryTokens() throws {
        XCTAssertTrue(try evaluate(##"(()=>{const s='linear-gradient(90deg, rgb(255 0 0 / .5) 10%, rgba(0,0,255,1) calc(100% - 3px)), url("https://example.test/#fff")',r=C.rewrite(s,()=> 'rgba(1, 2, 3, 1)');return r.includes('90deg')&&r.includes('calc(100% - 3px)')&&r.includes('url("https://example.test/#fff")')&&r.match(/rgba\(1, 2, 3, 1\)/g).length===2})()"##).toBool())
    }
    func testUnsupportedPayloadsAndQuotesAreNeverPartiallyRewritten() throws {
        XCTAssertTrue(try evaluate(##"C.rewrite('url("#fff") var(--red) calc(10px + 2px)',()=> 'changed')===null && C.rewrite('linear-gradient(rgb(1 2 3)',()=> 'changed')===null && C.rewrite('x'.repeat(16001),()=> 'changed')===null"##).toBool())
    }
    func testPaintTransitionsPreservedWhileTransformIsIndependent() throws {
        XCTAssertTrue(try evaluate("C.transitions({transitionProperty:'background-color, transform',transitionDuration:'.2s, .3s'}).has('background-color') && !C.transitions({transitionProperty:'transform',transitionDuration:'.2s'}).has('color') && C.transitions({transitionProperty:'all',transitionDuration:'.2s'}).has('stroke') && C.transitions({transitionProperty:'color',transitionDuration:'0s'}).size===0").toBool())
    }
}
