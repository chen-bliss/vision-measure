import Foundation

/// Window-local geometry: a foldable phone can change panels without changing its model.
public struct DisplayContext: Codable, Equatable {
    public let displayID: String
    public let widthPoints: Double
    public let heightPoints: Double
    public let scale: Double
    public let nativeWidthPixels: Double
    public let nativeHeightPixels: Double
    public let physicalOrientation: Int?
    public let interfaceOrientation: Int?
    public let calibrationPolicy: String?
    public init(displayID: String, widthPoints: Double, heightPoints: Double, scale: Double,
                nativeWidthPixels: Double, nativeHeightPixels: Double, physicalOrientation: Int? = nil,
                interfaceOrientation: Int? = nil, calibrationPolicy: String? = "geometry_interface_axis_v2") {
        self.displayID = displayID; self.widthPoints = widthPoints; self.heightPoints = heightPoints
        self.scale = scale; self.nativeWidthPixels = nativeWidthPixels; self.nativeHeightPixels = nativeHeightPixels
        self.physicalOrientation = physicalOrientation
        self.interfaceOrientation = interfaceOrientation; self.calibrationPolicy = calibrationPolicy
    }
    public var isUsable: Bool {
        !displayID.isEmpty && [widthPoints,heightPoints,scale,nativeWidthPixels,nativeHeightPixels].allSatisfy { $0.isFinite && $0 > 0 }
    }
    public var signature: String { displayID + ":" + auditKey }
    /// Stable across app launches; avoid merging measurements from different physical panels.
    public var auditKey: String {
        [nativeWidthPixels,nativeHeightPixels,widthPoints,heightPoints,scale].map { String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),$0) }.joined(separator:"x")
    }
    /// A gravity reading does not describe which way UIKit is drawing the interface.
    public var interfaceAxis: Int? {
        switch interfaceOrientation {
        case 1,2: return 0
        case 3,4: return 1
        default: return nil
        }
    }
    public func hasSameCalibrationGeometry(as other: DisplayContext) -> Bool {
        guard isUsable, other.isUsable, displayID == other.displayID,
              abs(scale-other.scale) < 0.000001,
              abs(nativeWidthPixels-other.nativeWidthPixels) < 0.5,
              abs(nativeHeightPixels-other.nativeHeightPixels) < 0.5 else { return false }
        // Ignore up to one physical pixel of layout rounding, anchored to the accepted geometry.
        return abs(widthPoints-other.widthPoints)*scale <= 1.000001
            && abs(heightPoints-other.heightPoints)*scale <= 1.000001
    }
}

public struct DisplayCalibrationTracker {
    public enum Change: Equatable { case initial, unchanged, geometry, interfaceAxis }
    public private(set) var accepted: DisplayContext?
    public init() {}
    public mutating func update(_ value: DisplayContext?) -> Change {
        // Reparenting/detachment is not evidence that the physical display changed.
        guard let value=value,value.isUsable else { return .unchanged }
        guard let old=accepted else { accepted=value; return .initial }
        if !old.hasSameCalibrationGeometry(as:value) { accepted=value; return .geometry }
        if let a=old.interfaceAxis,let b=value.interfaceAxis,a != b {
            accepted=value; return .interfaceAxis
        }
        accepted=DisplayContext(displayID:old.displayID,widthPoints:old.widthPoints,heightPoints:old.heightPoints,
            scale:old.scale,nativeWidthPixels:old.nativeWidthPixels,nativeHeightPixels:old.nativeHeightPixels,
            physicalOrientation:value.physicalOrientation,interfaceOrientation:value.interfaceAxis != nil ? value.interfaceOrientation : old.interfaceOrientation)
        return .unchanged
    }
}
