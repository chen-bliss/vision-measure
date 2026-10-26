import XCTest
@testable import RefractionCore

final class PrecompensationTests: XCTestCase {
    private func settings(sphere:Double = -3,cylinder:Double = 0,axis:Double = 0,strength:Double = 0.8) -> VisualPrecompensation.Settings {
        .init(sphere:sphere,cylinder:cylinder,axis:axis,distanceMeters:1,pupilMillimeters:3,imageWidthMillimeters:80,strength:strength)
    }
    private var pattern:[Double] {
        (0..<32*32).map { k in 0.5+0.1*cos(2 * Double.pi * Double(k%32)/16) }
    }
    func testZeroStrengthAndInFocusPreserveInput() throws {
        let target=pattern
        for s in [settings(sphere:-1),settings(strength:0)] {
            let r=try VisualPrecompensation.render(target:target,size:32,settings:s)
            XCTAssertLessThan(zip(target,r.pixels).map{abs($0-$1)}.max()!,1e-10)
            XCTAssertEqual(r.clippedFraction,0)
        }
    }
    func testMatchingToyModelReducesErrorWithoutClaimingHumanBenefit() throws {
        let target=pattern,r=try VisualPrecompensation.render(target:target,size:32,settings:settings())
        func error(_ values:[Double]) -> Double { zip(values,target).map{pow($0-$1,2)}.reduce(0,+)/Double(target.count) }
        XCTAssertLessThan(error(r.predictedProcessed),error(r.predictedOriginal))
        XCTAssertTrue(r.pixels.allSatisfy{$0.isFinite && (0...1).contains($0)})
    }
    func testCylinderAxisChangesPrefilterAndWrapsAt180Degrees() throws {
        let target=(0..<1024).map { k in k == 16*32+16 ? 0.8 : 0.5 }
        let a=try VisualPrecompensation.render(target:target,size:32,settings:settings(cylinder:-2,axis:0))
        let b=try VisualPrecompensation.render(target:target,size:32,settings:settings(cylinder:-2,axis:90))
        let c=try VisualPrecompensation.render(target:target,size:32,settings:settings(cylinder:-2,axis:180))
        XCTAssertGreaterThan(zip(a.pixels,b.pixels).map{abs($0-$1)}.max()!,1e-4)
        XCTAssertLessThan(zip(a.pixels,c.pixels).map{abs($0-$1)}.max()!,1e-10)
    }
    func testBoundedPixelsAndUnrepresentableBlurFailure() throws {
        let target=(0..<1024).map { k in (k%32 < 16) ? 0.0 : 1.0 }
        let r=try VisualPrecompensation.render(target:target,size:32,settings:settings(strength:1))
        XCTAssertTrue(r.pixels.allSatisfy{(0...1).contains($0)})
        XCTAssertGreaterThan(r.clippedFraction,0)
        var bad=settings(sphere:-20);bad.distanceMeters=3;bad.imageWidthMillimeters=20
        XCTAssertThrowsError(try VisualPrecompensation.render(target:target,size:32,settings:bad))
    }
    func testInvalidGeometryAndNonfiniteInputsRejected() {
        XCTAssertThrowsError(try VisualPrecompensation.render(target:[Double](repeating:0.5,count:31*31),size:31,settings:settings()))
        var bad=settings();bad.pupilMillimeters = .nan
        XCTAssertThrowsError(try VisualPrecompensation.render(target:pattern,size:32,settings:bad))
        var target=pattern;target[0] = .infinity
        XCTAssertThrowsError(try VisualPrecompensation.render(target:target,size:32,settings:settings()))
    }
}
