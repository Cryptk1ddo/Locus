import XCTest
import JavaScriptCore
@testable import Search

final class NightColorsTests: XCTestCase {
    func check(_ expression: String) throws -> JSValue {
        let context = try XCTUnwrap(JSContext()); var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        context.evaluateScript(NightColor.script)
        let value = try XCTUnwrap(context.evaluateScript("(() => { const M=__locusNightMath; return " + expression + "; })()"))
        XCTAssertNil(exception, exception ?? ""); return value
    }
    func testReferenceColorsRoundTripThroughOKLCH() throws {
        XCTAssertTrue(try check("['#000','#fff','#808080','#ff0000','#00ff00','#0000ff','#2563eb'].every(s=>{const c=M.parse(s),r=M.rgb(M.lch(c));return c.rgb.every((x,i)=>Math.abs(x-r.rgb[i])<.000002)})").toBool())
    }
    func testHueIdentityAndRoleSpecificOutputs() throws {
        XCTAssertTrue(try check("['#dc2626','#f59e0b','#16a34a','#2563eb','#9333ea'].every(s=>{const c=M.parse(s),a=M.adapt(c,'text'),b=M.adapt(c,'accent-fill'),h=M.lch(c).h,h2=M.lch(M.parse(M.css(a))).h;return Math.min(Math.abs(h-h2),360-Math.abs(h-h2))<2 && M.css(a)!==M.css(b)})").toBool())
    }
    func testTextContrastAfterQuantizationAgainstSurfacesAndAccents() throws {
        XCTAssertTrue(try check("['#1c1c1c','#282828',M.css(M.adapt(M.parse('#f59e0b'),'accent-fill'))].every(bg=>['#000','#888','#0066ff','#ffff00','#fff'].every(s=>{const b=M.parse(bg),a=M.parse(M.css(M.adapt(M.parse(s),'text',b,{originalContrast:4})));return M.contrast(a,b)>=4.5}))").toBool())
    }
    func testNeutralHierarchyAndSurfaceElevation() throws {
        XCTAssertTrue(try check("M.lch(M.adapt(M.parse('#111'),'text',M.canvas,{heading:true})).l>M.lch(M.adapt(M.parse('#444'),'text',M.canvas,{originalContrast:8})).l && M.lch(M.adapt(M.parse('#444'),'text',M.canvas,{originalContrast:8})).l>M.lch(M.adapt(M.parse('#888'),'text',M.canvas,{originalContrast:3})).l && M.css(M.adapt(M.parse('#fff'),'canvas'))==='rgba(28, 28, 28, 1)' && M.lch(M.adapt(M.parse('#fff'),'surface',M.canvas,{depth:2})).l>M.lch(M.adapt(M.parse('#fff'),'surface',M.canvas,{depth:1})).l").toBool())
    }
    func testWideGamutAlphaAndAreaCompression() throws {
        XCTAssertTrue(try check("M.parse('color(display-p3 1 0 0 / .5)').a===.5 && M.parse('oklch(60% .2 260)').rgb.every(Number.isFinite) && M.gamut({l:.7,c:.8,h:95,a:1}).rgb.every(x=>x>=0&&x<=1) && M.lch(M.adapt(M.parse('#f59e0b'),'surface',M.canvas,{area:1})).c<M.lch(M.adapt(M.parse('#f59e0b'),'surface',M.canvas,{area:.001})).c && M.parse('rgba(255, 0, 0, 0)').a===0 && M.parse('invalid')===null").toBool())
    }
    func testCSSHueUnitsAgree() throws {
        XCTAssertTrue(try check("['90deg','100grad','.25turn','1.5707963267948966rad'].every(h=>{const c=M.parse('oklch(.6 .12 '+h+')'),reference=M.parse('oklch(.6 .12 90)');return c.rgb.every((x,i)=>Math.abs(x-reference.rgb[i])<.000002)})").toBool())
    }
    @MainActor func testOptInPersistenceAndPrivateSiteIsolation() throws {
        let name="night-test-\(UUID())",settings=try XCTUnwrap(UserDefaults(suiteName:name));defer{settings.removePersistentDomain(forName:name)}
        let night=NightColors(settings:settings),url=URL(string:"https://example.com/path")!
        XCTAssertFalse(night.enabled);night.setEnabled(true);night.setMode(.always,for:url,shy:false)
        night.setMode(.off,for:url,shy:true);XCTAssertEqual(night.mode(for:url,shy:true),.off)
        XCTAssertEqual(night.mode(for:url,shy:false),.always)
        let restored=NightColors(settings:settings);XCTAssertTrue(restored.enabled);XCTAssertEqual(restored.mode(for:url,shy:false),.always);XCTAssertEqual(restored.mode(for:url,shy:true),.automatic)
        night.resetSites();XCTAssertTrue(night.sites.isEmpty);XCTAssertNil(settings.object(forKey:"night.sites"))
    }
    @MainActor func testExactHostChoicesExcludeInternalAndExtensionPages() throws {
        XCTAssertEqual(NightColors.host(URL(string:"https://EXAMPLE.com.:443/path")),"example.com")
        for value in ["locus://wall/one","chrome-extension://abc/page.html","file:///tmp/index.html","about:blank"]{XCTAssertNil(NightColors.host(URL(string:value)))}
        let name="night-test-\(UUID())",settings=try XCTUnwrap(UserDefaults(suiteName:name));defer{settings.removePersistentDomain(forName:name)}
        let night=NightColors(settings:settings);night.setMode(.off,for:URL(string:"https://example.com"),shy:false)
        XCTAssertEqual(night.mode(for:URL(string:"https://sub.example.com"),shy:false),.automatic)
    }
    @MainActor func testSerializedPolicyContainsOnlyCurrentFrameChoice() throws {
        let name="night-test-\(UUID())",settings=try XCTUnwrap(UserDefaults(suiteName:name));defer{settings.removePersistentDomain(forName:name)}
        let night=NightColors(settings:settings),url=URL(string:"https://example.com")!
        night.setEnabled(true);night.setMode(.always,for:url,shy:false);night.setMode(.off,for:URL(string:"https://other.example"),shy:false)
        let json=night.configuration(shy:false,token:"test-token",url:url)
        let policy=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(json.utf8)) as? [String:Any])
        XCTAssertEqual(Set(policy.keys),["enabled","mode","dark","token"]);XCTAssertEqual(policy["mode"] as? String,"always")
        XCTAssertEqual(policy["dark"] as? Bool,Favicons.dark)
        XCTAssertFalse(json.contains("example"));XCTAssertNil(policy["sites"])
    }

    @MainActor func testOpaqueOrNonWebFrameOriginHasNoPolicyURL() {
        for scheme in ["", "about", "file", "https:", "invalid scheme"] { XCTAssertNil(NightColors.originURL(scheme:scheme,host:"example.com")) }
        XCTAssertNil(NightColors.originURL(scheme:"https",host:""))
        XCTAssertEqual(NightColors.host(NightColors.originURL(scheme:"https",host:"example.com")),"example.com")
    }

}
