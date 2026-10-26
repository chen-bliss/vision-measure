import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assets = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
var images: [[String:String]] = []
for size in [16,20,29,32,40,58,60,64,76,80,87,120,128,152,167,180,256,512,1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = Double(size)
    NSGradient(starting:NSColor(calibratedRed:0.05,green:0.16,blue:0.48,alpha:1),
        ending:NSColor(calibratedRed:0.12,green:0.49,blue:0.91,alpha:1))!
        .draw(in:NSBezierPath(rect:NSRect(x:0,y:0,width:s,height:s)),angle:55)
    let eye = NSBezierPath()
    eye.move(to: NSPoint(x:s*0.16,y:s*0.5))
    eye.curve(to: NSPoint(x:s*0.84,y:s*0.5), controlPoint1:NSPoint(x:s*0.32,y:s*0.83),controlPoint2:NSPoint(x:s*0.68,y:s*0.83))
    eye.curve(to: NSPoint(x:s*0.16,y:s*0.5), controlPoint1:NSPoint(x:s*0.68,y:s*0.17),controlPoint2:NSPoint(x:s*0.32,y:s*0.17))
    eye.close(); NSColor.white.setFill(); eye.fill()
    NSColor(calibratedRed:0.12,green:0.69,blue:0.89,alpha:1).setFill()
    NSBezierPath(ovalIn:NSRect(x:s*0.34,y:s*0.34,width:s*0.32,height:s*0.32)).fill()
    NSColor(calibratedRed:0.05,green:0.18,blue:0.48,alpha:1).setFill()
    NSBezierPath(ovalIn:NSRect(x:s*0.40,y:s*0.40,width:s*0.20,height:s*0.20)).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn:NSRect(x:s*0.53,y:s*0.53,width:s*0.065,height:s*0.065)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using:.png,properties:[:])!.write(to:assets.appendingPathComponent("icon-\(size).png"))
}
for base in [16,32,128,256,512] {
    for scale in [1,2] { images.append(["idiom":"mac","size":"\(base)x\(base)","scale":"\(scale)x","filename":"icon-\(base*scale).png"]) }
}
for (base, scales) in [(20,[2,3]),(29,[2,3]),(40,[2,3]),(60,[2,3])] {
    for scale in scales { images.append(["idiom":"iphone","size":"\(base)x\(base)","scale":"\(scale)x","filename":"icon-\(base*scale).png"]) }
}
for (base, scales) in [(20,[1,2]),(29,[1,2]),(40,[1,2]),(76,[1,2])] {
    for scale in scales { images.append(["idiom":"ipad","size":"\(base)x\(base)","scale":"\(scale)x","filename":"icon-\(base*scale).png"]) }
}
images.append(["idiom":"ipad","size":"83.5x83.5","scale":"2x","filename":"icon-167.png"])
images.append(["idiom":"ios-marketing","size":"1024x1024","filename":"icon-1024.png"])
let json: [String:Any] = ["images":images,"info":["author":"xcode","version":1]]
try JSONSerialization.data(withJSONObject:json,options:[.prettyPrinted,.sortedKeys]).write(to:assets.appendingPathComponent("Contents.json"))
let parent = assets.deletingLastPathComponent()
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to:parent.appendingPathComponent("Contents.json"))
