import XCTest
import JavaScriptCore
@testable import Search

final class FloatMediaTests: XCTestCase {
    func testInvalidAndLiveStateDoNotOfferSeekOrNonfiniteProgress() {
        let live = FloatMediaState(["duration": Double.infinity, "current": Double.nan, "playing": false, "muted": true, "seekable": true])
        XCTAssertFalse(live.seekable); XCTAssertEqual(live.progress, 0); XCTAssertEqual(live.timeLabel, "Live"); XCTAssertFalse(live.playing); XCTAssertTrue(live.muted)
        let dvr = FloatMediaState(["duration": Double.infinity, "seekable": false, "canSkip": true])
        XCTAssertFalse(dvr.seekable); XCTAssertTrue(dvr.canSkip)
        let missing = FloatMediaState(nil); XCTAssertFalse(missing.playing); XCTAssertFalse(missing.seekable)
    }
    func testFiniteStateClampsProgressAndFormatsLongMedia() {
        let media = FloatMediaState(["duration": 3661.0, "current": 4000.0, "seekable": true])
        XCTAssertTrue(media.seekable); XCTAssertEqual(media.progress, 1); XCTAssertEqual(media.timeLabel, "1:01:01 / 1:01:01")
        XCTAssertEqual(FloatMediaState.clock(-4), "0:00"); XCTAssertEqual(FloatMediaState.clock(72), "1:12")
    }
    func testMissingLoadingAndErrorsAreDistinctFromLive() {
        XCTAssertEqual(FloatMediaState(nil).timeLabel, "Video unavailable")
        XCTAssertEqual(FloatMediaState(["loading": true]).timeLabel, "Loading…")
        let failed = FloatMediaState(["failed": true, "playing": true, "seekable": true, "canSkip": true, "duration": 20.0])
        XCTAssertEqual(failed.timeLabel, "Playback error"); XCTAssertFalse(failed.playing); XCTAssertFalse(failed.seekable); XCTAssertFalse(failed.canSkip)
        XCTAssertEqual(FloatMediaState(["duration": 0.0, "live": false]).timeLabel, "0:00")
    }
    func testBufferingEndedAndSourceSpeed() {
        XCTAssertEqual(FloatMediaState(["buffering": true, "current": 12.0, "duration": 30.0]).timeLabel, "Buffering… · 0:12 / 0:30")
        XCTAssertEqual(FloatMediaState(["ended": true, "current": 30.0, "duration": 30.0]).timeLabel, "Ended · 0:30 / 0:30")
        XCTAssertEqual(FloatMediaState(["rate": 1.5]).rate, 1.5)
        XCTAssertEqual(FloatMediaState(["rate": Double.nan]).rate, 1)
    }
    func testRateCommandsRejectNonMenuValues() {
        for value in [Double.nan, .infinity, -1, 0, 9, 1.2] { XCTAssertEqual(Isolate.rate(value), "false") }
        XCTAssertTrue(Isolate.rate(1.5).contains("video.playbackRate = 1.5"))
    }
    func testFloatingCommandsNeverFallBackToBackgroundPlayer() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var background = {currentTime:12,duration:30,muted:true,volume:1,paused:true,ended:false,seekable:{length:1,start:function(){return 0},end:function(){return 30}},play:function(){this.paused=false;return Promise.resolve()},pause:function(){this.paused=true}};
        var document = {documentElement:{classList:{contains:function(){return true}}},querySelector:function(selector){return selector==='video'?background:null}};
        """)
        for script in [Isolate.mediaState, Isolate.toggle, Isolate.mute, Isolate.skip(15), Isolate.seek(0.5)] {
            context.evaluateScript(script); XCTAssertNil(context.exception)
            XCTAssertTrue(context.evaluateScript("background.paused && background.muted && background.currentTime===12")!.toBool())
        }
        // Outside PiP the same helpers still support the legacy isolation probes.
        context.evaluateScript("document.documentElement.classList.contains=function(){return false}")
        XCTAssertTrue(context.evaluateScript(Isolate.skip(15))!.toBool())
        XCTAssertEqual(context.evaluateScript("background.currentTime")!.toDouble(), 27)
    }
    func testInvalidCommandsCannotBecomeJavaScriptExpressions() {
        XCTAssertEqual(Isolate.seek(.nan), "false"); XCTAssertEqual(Isolate.skip(.infinity), "false")
        XCTAssertTrue(Isolate.seek(9).contains("video.duration * (1.0)"))
    }
    func testAttentionAndSupportedAspectMetadata() {
        XCTAssertTrue(FloatMediaState(nil).needsAttention)
        XCTAssertTrue(FloatMediaState(["buffering":true]).needsAttention)
        XCTAssertFalse(FloatMediaState(["ended":true,"width":640.0,"height":640.0]).needsAttention)
        XCTAssertEqual(FloatMediaState(["width":360.0,"height":640.0]).aspect, 0.5625)
        for fields in [["width":Double.nan,"height":640.0],["width":2.0,"height":10000.0],["width":640.0,"height":0.0]] { XCTAssertNil(FloatMediaState(fields).aspect) }
    }
    func testMediaFrameFitsPortraitSquareAndLandscapeAndKeepsControlsUsable() throws {
        let area = CGRect(x: 0,y: 0,width:1440,height:900), original = CGRect(x:900,y:600,width:440,height:247)
        for ratio in [0.5625,1,2.35] {
            let fitted = try XCTUnwrap(Float.mediaFrame(original, ratio: ratio, in: area))
            XCTAssertEqual(fitted.width / fitted.height, ratio, accuracy: 0.001)
            XCTAssertTrue(area.contains(fitted)); XCTAssertGreaterThanOrEqual(fitted.width,260); XCTAssertGreaterThanOrEqual(fitted.height,146)
        }
        XCTAssertNil(Float.mediaFrame(original, ratio: .nan, in: area))
        XCTAssertNil(Float.mediaFrame(original, ratio: 0.1, in: area))
        XCTAssertNil(Float.mediaFrame(original, ratio: 0.5625, in: CGRect(x:0,y:0,width:100,height:100)))
    }

}
