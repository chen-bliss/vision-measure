import XCTest
@testable import RefractionCore

final class DisplayCalibrationTests: XCTestCase {
    private func context(width:Double=400,pose:Int=1,interface:Int=1,id:String="stable-scene",scale:Double=3) -> DisplayContext {
        DisplayContext(displayID:id,widthPoints:width,heightPoints:700,scale:scale,
            nativeWidthPixels:1200,nativeHeightPixels:2100,physicalOrientation:pose,interfaceOrientation:interface)
    }
    func testInnerScreenGravityTransitionsDoNotRecalibrate() {
        var tracker=DisplayCalibrationTracker()
        XCTAssertEqual(tracker.update(context()),.initial)
        let key=tracker.accepted?.signature
        for pose in [0,5,6,3,4,1,2,5,1] {
            XCTAssertEqual(tracker.update(context(pose:pose)),.unchanged)
            XCTAssertEqual(tracker.accepted?.signature,key)
        }
    }
    func testTransientDetachmentAndInvalidSnapshotKeepAcceptedCalibration() {
        var tracker=DisplayCalibrationTracker(); _=tracker.update(context())
        XCTAssertEqual(tracker.update(nil),.unchanged)
        XCTAssertEqual(tracker.update(context(width:0)),.unchanged)
        XCTAssertEqual(tracker.accepted?.widthPoints,400)
        XCTAssertEqual(tracker.update(context(pose:5)),.unchanged)
    }
    func testOnePixelJitterIsAnchoredRatherThanAccumulated() {
        var tracker=DisplayCalibrationTracker(); _=tracker.update(context())
        XCTAssertEqual(tracker.update(context(width:400.2)),.unchanged)
        XCTAssertEqual(tracker.accepted?.widthPoints,400)
        XCTAssertEqual(tracker.update(context(width:400.4)),.geometry)
    }
    func testRealPanelScaleAndDisplayChangesStillInvalidate() {
        var tracker=DisplayCalibrationTracker(); _=tracker.update(context())
        let inner=DisplayContext(displayID:"stable-scene",widthPoints:700,heightPoints:650,scale:3,
            nativeWidthPixels:2100,nativeHeightPixels:1950,physicalOrientation:1,interfaceOrientation:1)
        XCTAssertEqual(tracker.update(inner),.geometry)
        XCTAssertEqual(tracker.update(context()),.geometry)
        XCTAssertEqual(tracker.update(context(scale:2)),.geometry)
        XCTAssertEqual(tracker.update(context(id:"different-display",scale:2)),.geometry)
    }
    func testOnlyKnownInterfaceQuarterTurnChangesOpticalAxis() {
        var tracker=DisplayCalibrationTracker(); _=tracker.update(context())
        XCTAssertEqual(tracker.update(context(pose:5,interface:0)),.unchanged)
        XCTAssertEqual(tracker.accepted?.interfaceAxis,0)
        XCTAssertEqual(tracker.update(context(interface:2)),.unchanged)
        XCTAssertEqual(tracker.update(context(interface:3)),.interfaceAxis)
        XCTAssertEqual(tracker.update(context(interface:4)),.unchanged)
    }
    func testLegacyDisplayRecordsDecodeWithoutNewMetadata() throws {
        let json=#"{"displayID":"old","widthPoints":400,"heightPoints":700,"scale":3,"nativeWidthPixels":1200,"nativeHeightPixels":2100,"physicalOrientation":5}"#
        let decoded=try JSONDecoder().decode(DisplayContext.self,from:Data(json.utf8))
        XCTAssertNil(decoded.interfaceOrientation); XCTAssertNil(decoded.calibrationPolicy)
        XCTAssertTrue(decoded.isUsable)
    }
}
