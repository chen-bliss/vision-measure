import SwiftUI
import RefractionCore

struct GratingView: View {
    let side: Int
    let correctSide: Int
    let meridian: Double
    let stripeWidth: Double
    let diameter: Double
    let visible: Bool
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.5)))
            guard visible, stripeWidth > 0 else { return }
            guard diameter <= min(size.width, size.height) - 8 else { return }
            let rect = CGRect(x: (size.width-diameter)/2, y: (size.height-diameter)/2, width: diameter, height: diameter)
            guard side == correctSide else { return }
            context.clip(to: Path(ellipseIn: rect))
            let original = context
            context.translateBy(x: size.width/2, y: size.height/2)
            // SwiftUI's y coordinate points down; optical meridians use counterclockwise angles.
            context.rotate(by: .degrees(-Optics.stripeAngle(forMeridian: meridian)))
            let extent = diameter
            var y = -ceil(extent / (stripeWidth * 2)) * stripeWidth * 2
            while y < extent {
                context.fill(Path(CGRect(x: -extent, y: y, width: extent*2, height: stripeWidth)), with: .color(Color(white: 0.05)))
                context.fill(Path(CGRect(x: -extent, y: y+stripeWidth, width: extent*2, height: stripeWidth)), with: .color(Color(white: 0.95)))
                y += stripeWidth * 2
            }
            // Taper the aperture to suppress low-frequency edge cues in the detection task.
            let overlay = original
            overlay.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(white: 0.5).opacity(0), Color(white: 0.5)]),
                center: CGPoint(x: size.width/2, y: size.height/2), startRadius: diameter * 0.22, endRadius: diameter/2))
        }
        .accessibilityLabel(side == 0 ? "左侧测试区域" : "右侧测试区域")
        .accessibilityHidden(true)
    }
}

struct StimulusPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("条纹显示示例").font(.title2.bold())
            Text("左侧为放大的示意条纹，右侧为灰色。此页仅检查屏幕显示，不需要测距，不记录作答，也不计算度数。")
            HStack(spacing:16) {
                ForEach(0..<2) { side in
                    GratingView(side:side,correctSide:0,meridian:0,stripeWidth:4,diameter:80,visible:true)
                        .frame(maxWidth:.infinity).frame(height:160)
                }
            }.accessibilityElement(children:.ignore).accessibilityLabel("条纹显示示例区域")
                .accessibilityIdentifier("preview-stimulus-pair")
            Text("正式测试会使用更细的条纹，并在距离已确认、到达目标且读数稳定后显示。示例清晰不代表测量准确。")
                .font(.callout).foregroundStyle(.secondary)
            Button("返回测距与测试") { dismiss() }.buttonStyle(.borderedProminent)
        }.padding(24).frame(maxWidth:600).preferredColorScheme(.light)
    }
}
