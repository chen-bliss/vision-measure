import XCTest
import UIKit

final class FlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-test"]
        app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<16 {
            let keyboard=app.keyboards.firstMatch
            let toolbar=app.toolbars.firstMatch
            let hasKeyboard=keyboard.exists
            let keyboardTop=hasKeyboard ? (toolbar.exists ? min(keyboard.frame.minY,toolbar.frame.minY) : keyboard.frame.minY-56) : app.frame.maxY
            let bottom=hasKeyboard ? keyboardTop-12 : app.frame.maxY-20
            let top=app.frame.minY+60
            if element.isHittable && element.frame.maxY <= bottom && element.frame.minY >= top { return }
            let down=element.exists && element.frame.minY < top
            let needed=element.exists ? (down ? top-element.frame.minY+16 : element.frame.maxY-bottom+16) : 120
            let amount=min(max(needed,35),max(60,(bottom-top)*0.65))
            let start=down ? top+12 : bottom-12
            let end=start+(down ? amount : -amount)
            let origin=app.coordinate(withNormalizedOffset:.zero)
            let from=origin.withOffset(CGVector(dx:app.frame.width/2,dy:start-app.frame.minY))
            let to=origin.withOffset(CGVector(dx:app.frame.width/2,dy:end-app.frame.minY))
            from.press(forDuration:0.02,thenDragTo:to)
        }
    }
    private func fill(_ field: XCUIElement, _ value: String) {
        reveal(field); field.tap()
        if let old = field.value as? String, !old.isEmpty, old != field.placeholderValue {
            field.press(forDuration: 1.1)
            let select = app.menuItems["Select All"]
            if select.waitForExistence(timeout: 1) { select.tap() }
            else {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
        }
        field.typeText(value)
    }
    private func confirmManual() {
        let button=app.buttons["确认已实测，并保持不动"]
        reveal(button); button.tap()
    }
    private func assertKeyboardDismissed(file:StaticString = #filePath,line:UInt = #line) {
        let hidden=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for:[hidden],timeout:4),.completed,file:file,line:line)
    }
    private func prepareManualTest() {
        fill(app.textFields["匿名编号，例如 P001（不要填写姓名）"],"SYNTHETIC_MANUAL")
        for index in 0..<2 { let toggle=app.switches.element(boundBy:index); reveal(toggle); toggle.tap() }
        fill(app.textFields["蓝线实测长度（厘米）"],"6")
        reveal(app.buttons["确认尺寸"]); app.buttons["确认尺寸"].tap()
        reveal(app.buttons["设置测距方式"]); app.buttons["设置测距方式"].tap()
        reveal(app.buttons["开始练习与测量"]); app.buttons["开始练习与测量"].tap()
    }
    private func targetCentimeters() throws -> String {
        let target=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","请到距屏幕")).firstMatch.label
        let regex=try NSRegularExpression(pattern:"距屏幕 ([0-9.]+) 厘米")
        let match=try XCTUnwrap(regex.firstMatch(in:target,range:NSRange(target.startIndex...,in:target)))
        return String(target[try XCTUnwrap(Range(match.range(at:1),in:target))])
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func assertVisibleStripes(in element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        reveal(element)
        let cg = try XCTUnwrap(element.screenshot().image.cgImage, file:file,line:line)
        var pixels = [UInt8](repeating:0,count:cg.width * cg.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data:buffer.baseAddress,width:cg.width,height:cg.height,
                bitsPerComponent:8,bytesPerRow:cg.width * 4,space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height)); return true
        }
        XCTAssertTrue(rendered,file:file,line:line)
        var dark = 0, light = 0
        for offset in stride(from:0,to:pixels.count,by:4) where pixels[offset+3] > 240 {
            if pixels[offset] < 80 && pixels[offset+1] < 80 && pixels[offset+2] < 80 { dark += 1 }
            if pixels[offset] > 210 && pixels[offset+1] > 210 && pixels[offset+2] > 210 { light += 1 }
        }
        XCTAssertGreaterThan(dark,50,"The rendered stimulus must contain dark stripe pixels, not just a gray placeholder",file:file,line:line)
        XCTAssertGreaterThan(light,50,"The rendered stimulus must contain light stripe pixels",file:file,line:line)
    }
    private func darkPixelCount(_ element:XCUIElement) throws -> Int {
        let cg=try XCTUnwrap(element.screenshot().image.cgImage)
        var pixels=[UInt8](repeating:0,count:cg.width*cg.height*4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:cg.width,height:cg.height,bitsPerComponent:8,
                bytesPerRow:cg.width*4,space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
        }
        return stride(from:0,to:pixels.count,by:4).filter{pixels[$0]<150 && pixels[$0+1]<150 && pixels[$0+2]<150 && pixels[$0+3]>240}.count
    }
    func testPreviewRendersStripesWithoutDistanceOrConsent() throws {
        app.buttons["距离"].tap()
        let preview = app.buttons["查看条纹显示示例"]
        reveal(preview); preview.tap()
        let pair=app.descendants(matching:.any).matching(identifier:"preview-stimulus-pair").firstMatch
        XCTAssertTrue(pair.waitForExistence(timeout:5))
        try assertVisibleStripes(in:pair)
        attach("iPhone-unmeasured-display-preview")
        app.buttons["返回测距与测试"].tap()
        XCTAssertFalse(app.buttons["停止并保存已有记录"].exists)
    }
    func testFunPrecompensationGeneratesAndSwitchesOriginalWithoutStudyConsent() throws {
        fill(app.textFields["蓝线实测长度（厘米）"],"6")
        reveal(app.buttons["确认尺寸"]); app.buttons["确认尺寸"].tap(); assertKeyboardDismissed()
        reveal(app.buttons["趣味"]); app.buttons["趣味"].tap()
        let generate=app.buttons["生成预处理图"]
        reveal(generate); generate.tap()
        let image=app.descendants(matching:.any).matching(identifier:"fun-display-image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout:12))
        reveal(image); attach("iPhone-fun-precompensation")
        let processed=image.screenshot().pngRepresentation
        reveal(app.buttons["原图"]); app.buttons["原图"].tap()
        reveal(image)
        XCTAssertNotEqual(processed,image.screenshot().pngRepresentation,"The prefiltered image should differ from its source")
        attach("iPhone-fun-original")
        let largeInk=try darkPixelCount(image)
        let size=app.sliders["fun-content-size"]; reveal(size); size.adjust(toNormalizedSliderPosition:0)
        reveal(generate); generate.tap()
        XCTAssertTrue(image.waitForExistence(timeout:12))
        reveal(app.buttons["原图"]); app.buttons["原图"].tap(); reveal(image)
        let smallInk=try darkPixelCount(image)
        XCTAssertGreaterThan(smallInk,100)
        XCTAssertLessThan(Double(smallInk),Double(largeInk)*0.75,"Changing size must resize the actual source glyph, not just its label")
        attach("iPhone-fun-smaller-text")
        let save=app.buttons["保存到文件"]; reveal(save); save.tap()
        let cancel=app.buttons.matching(NSPredicate(format:"label IN %@",["取消","Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:8))
        attach("iPhone-fun-save-png-dialog")
        cancel.tap()
        XCTAssertFalse(app.buttons["停止并保存已有记录"].exists)
    }
    func testManualDistanceFlowAndIncompleteResult() throws {
        attach("iPhone-preparation")
        fill(app.textFields["匿名编号，例如 P001（不要填写姓名）"], "SYNTHETIC_UI")
        for index in 0..<2 {
            let toggle = app.switches.element(boundBy: index)
            reveal(toggle); toggle.tap()
        }
        fill(app.textFields["蓝线实测长度（厘米）"], "6")
        reveal(app.buttons["确认尺寸"]); app.buttons["确认尺寸"].tap()
        reveal(app.buttons["设置测距方式"]); app.buttons["设置测距方式"].tap()
        fill(app.textFields["距离（厘米）"], "300")
        confirmManual()
        reveal(app.buttons["开始练习与测量"]); app.buttons["开始练习与测量"].tap()
        let left = app.buttons["左侧有条纹"]
        reveal(left)
        XCTAssertFalse(left.isEnabled, "Wrong distance must block responses")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","尚未到达目标")).firstMatch.exists)
        attach("iPhone-distance-gate")
        let target = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "请到距屏幕")).firstMatch.label
        let regex = try NSRegularExpression(pattern: "距屏幕 ([0-9.]+) 厘米")
        let match = try XCTUnwrap(regex.firstMatch(in: target, range: NSRange(target.startIndex...,in:target)))
        let range = try XCTUnwrap(Range(match.range(at:1),in:target))
        fill(app.textFields["距离（厘米）"],String(target[range]))
        confirmManual()
        assertKeyboardDismissed()
        reveal(left)
        let enabled = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:left)
        XCTAssertEqual(XCTWaiter.wait(for:[enabled],timeout:8),.completed)
        let pair=app.descendants(matching:.any).matching(identifier:"stimulus-pair").firstMatch
        try assertVisibleStripes(in:pair)
        reveal(left)
        XCTAssertTrue(left.isEnabled)
        attach("iPhone-live-stimulus")
        // Exercise the former 30-second limit through refresh AND actual response handling.
        let unexpectedlyDisabled=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == false"),object:left)
        unexpectedlyDisabled.isInverted=true
        XCTAssertEqual(XCTWaiter.wait(for:[unexpectedlyDisabled],timeout:32),.completed)
        XCTAssertTrue(left.isEnabled,"A fixed-position manual confirmation must not expire after 30 seconds")
        attach("iPhone-manual-confirmation-after-30-seconds")
        left.tap()
        let stop = app.buttons["停止并保存已有记录"]
        reveal(stop); stop.tap()
        XCTAssertTrue(app.staticTexts["本次未输出度数"].firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["导出完整记录"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","1次作答")).firstMatch.exists)
        attach("iPhone-incomplete-record")
        let export=app.buttons["导出完整记录"].firstMatch; reveal(export); export.tap()
        let cancel=app.buttons.matching(NSPredicate(format:"label IN %@",["取消","Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:8))
        attach("iPhone-study-json-export-dialog")
        cancel.tap()
    }
    func testKeyboardDoneDismissesWithoutConfirmingDistance() {
        app.buttons["距离"].tap()
        fill(app.textFields["距离（厘米）"],"100")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let done=app.buttons["dismiss-input-keyboard"]
        XCTAssertTrue(done.waitForExistence(timeout:4))
        done.tap(); assertKeyboardDismissed()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","当前 100.0 厘米")).firstMatch.exists)
        attach("iPhone-keyboard-done-dismissed")
    }
    func testUnrecognizableCoarseTrainingStopsWithoutEstimate() throws {
        prepareManualTest()
        fill(app.textFields["距离（厘米）"],try targetCentimeters())
        confirmManual(); assertKeyboardDismissed()
        let cannotSee=app.buttons["我仍无法辨认练习图案"]
        reveal(cannotSee)
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:cannotSee)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:8),.completed)
        attach("iPhone-coarse-training")
        cannotSee.tap()
        XCTAssertTrue(app.staticTexts["本次未输出度数"].firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","用户仍无法辨认")).firstMatch.exists)
        attach("iPhone-unrecognizable-training-no-estimate")
    }
    func testUnconfirmedAndInvalidManualDistanceExplainBlankStimulus() {
        fill(app.textFields["匿名编号，例如 P001（不要填写姓名）"],"SYNTHETIC_GATE")
        for index in 0..<2 { let toggle=app.switches.element(boundBy:index); reveal(toggle); toggle.tap() }
        fill(app.textFields["蓝线实测长度（厘米）"],"6")
        reveal(app.buttons["确认尺寸"]); app.buttons["确认尺寸"].tap()
        reveal(app.buttons["设置测距方式"]); app.buttons["设置测距方式"].tap()
        reveal(app.buttons["开始练习与测量"]); app.buttons["开始练习与测量"].tap()
        let missing=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","人工距离尚未确认")).firstMatch
        XCTAssertTrue(missing.waitForExistence(timeout:5))
        fill(app.textFields["距离（厘米）"],"abc")
        confirmManual()
        let invalid=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","请输入实际测量的距离和误差")).firstMatch
        XCTAssertTrue(invalid.waitForExistence(timeout:5))
        let left=app.buttons["左侧有条纹"]; reveal(left)
        XCTAssertFalse(left.isEnabled)
        attach("iPhone-manual-distance-explanation")
    }
    func testInvalidScreenCalibrationDoesNotStartMeasurement() {
        fill(app.textFields["蓝线实测长度（厘米）"],"abc")
        reveal(app.buttons["确认尺寸"]); app.buttons["确认尺寸"].tap()
        let warning = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","请用尺子测量蓝色线段的实际长度并输入厘米数" )).firstMatch
        reveal(warning)
        attach("iPhone-invalid-screen-after-confirm")
        if !warning.exists { print(app.debugDescription) }
        XCTAssertTrue(warning.exists)
    }
    func testActualDisplayChangeStopsMeasurement() throws {
        fill(app.textFields["匿名编号，例如 P001（不要填写姓名）"],"SYNTHETIC_RESIZE")
        for index in 0..<2 { let toggle=app.switches.element(boundBy:index); reveal(toggle); toggle.tap() }
        fill(app.textFields["蓝线实测长度（厘米）"],"6")
        reveal(app.buttons["确认尺寸"]); app.buttons["确认尺寸"].tap()
        reveal(app.buttons["设置测距方式"]); app.buttons["设置测距方式"].tap()
        reveal(app.buttons["开始练习与测量"]); app.buttons["开始练习与测量"].tap()
        XCTAssertTrue(app.buttons["停止并保存已有记录"].waitForExistence(timeout:8))
        let context=app.staticTexts["test-display-context"]
        let before=context.label
        attach("iPhone-before-posture-change")
        XCUIDevice.shared.orientation = .landscapeLeft
        let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label != %@",before),object:context)
        let didChange = XCTWaiter.wait(for:[changed],timeout:8) == .completed
        attach("iPhone-after-posture-change")
        guard didChange else { throw XCTSkip("模拟器旋转未改变实际显示或姿态，不能作为显示切换验证；需要Device Hub或真机检查。") }
        let stopped=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","本轮已停止")).firstMatch
        XCTAssertTrue(stopped.waitForExistence(timeout:8))
        attach("iPhone-resize-stopped")
        XCTAssertFalse(app.buttons["停止并保存已有记录"].exists)
    }
}
