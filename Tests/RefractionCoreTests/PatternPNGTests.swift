import XCTest
import CoreGraphics
import ImageIO
@testable import RefractionCore

final class PatternPNGTests: XCTestCase {
    private func image() throws -> CGImage {
        let bytes=[UInt8](repeating:180,count:16*16)
        let provider=try XCTUnwrap(CGDataProvider(data:Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width:16,height:16,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:16,
            space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
    }
    func testPNGReopensWithPixelsAndPhysicalDisplaySize() throws {
        let data=try PatternPNG.encode(image(),displayWidthMillimeters:25.4)
        XCTAssertEqual(Array(data.prefix(8)),[137,80,78,71,13,10,26,10])
        let source=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
        let restored=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertEqual(restored.width,16); XCTAssertEqual(restored.height,16)
        let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any])
        let dpi=try XCTUnwrap(properties[kCGImagePropertyDPIWidth as String] as? Double)
        XCTAssertEqual(dpi,16,accuracy:0.03)
    }
    func testInvalidPhysicalSizesCannotProduceAnExport() throws {
        let image=try image()
        for width in [0.0,-1,.nan,.infinity] {
            XCTAssertThrowsError(try PatternPNG.encode(image,displayWidthMillimeters:width))
        }
    }
}
