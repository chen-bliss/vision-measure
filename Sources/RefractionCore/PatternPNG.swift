import Foundation
import CoreGraphics
import ImageIO

public enum PatternPNG {
    /// Export the generated pixels, not a screenshot. No prescription or identity is embedded.
    public static func encode(_ image:CGImage,displayWidthMillimeters:Double) throws -> Data {
        let dpi=Double(image.width)*25.4/displayWidthMillimeters
        guard displayWidthMillimeters.isFinite,displayWidthMillimeters > 0,
              dpi.isFinite,dpi > 0,dpi <= 100_000 else {
            throw MeasurementError.invalid(L("图片的显示尺寸无效，请重新校准并生成。"))
        }
        guard let data=CFDataCreateMutable(nil,0),
              let destination=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else {
            throw MeasurementError.invalid(L("无法创建PNG图片，请重试。"))
        }
        let properties:[CFString:Any]=[kCGImagePropertyDPIWidth:dpi,kCGImagePropertyDPIHeight:dpi]
        CGImageDestinationAddImage(destination,image,properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MeasurementError.invalid(L("PNG编码失败，请重新生成后再保存。")) }
        return data as Data
    }
}
