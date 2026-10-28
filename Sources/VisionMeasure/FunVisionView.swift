import SwiftUI
import CoreGraphics
import CoreText
import RefractionCore
#if os(iOS)
import Photos
#endif

struct FunVisionView: View {
    let language: AppLanguage
    let screenConfirmed: Bool
    let pointsPerMillimeter: Double
    let availableWidth: Double
    let displaySignature: String
    let onCalibrate: () -> Void
    let onSavePNG: (PatternExportRequest) -> Void
    @State private var sphere = ""
    @State private var cylinder = "0"
    @State private var axis = "0"
    @State private var distance = "60"
    @State private var pupil = "3"
    @State private var text = ""
    @State private var pattern = 0
    @State private var strength = 0.65
    @State private var contentFraction = 0.8
    @State private var mode = 1
    @State private var original: CGImage?
    @State private var processed: CGImage?
    @State private var busy = false
    @State private var message = ""
    @State private var requestID = UUID()
    @State private var imagePNG: Data?
    @State private var generatedWidthMM: Double?
    @State private var savingToPhotos = false
    @FocusState private var inputFocused: String?
    /// Chinese prescriptions are written in 度 (0.01 D); other languages enter diopters.
    private var usesDegrees: Bool { language == .chinese }
    private var powerScale: Double { usesDegrees ? 100 : 1 }
    private var panelPoints: CGFloat { CGFloat(min(320,max(160,availableWidth-100))) }
    init(language:AppLanguage,screenConfirmed:Bool,pointsPerMillimeter:Double,availableWidth:Double,displaySignature:String,
         onCalibrate:@escaping () -> Void,onSavePNG:@escaping (PatternExportRequest) -> Void) {
        self.language=language; self.screenConfirmed=screenConfirmed; self.pointsPerMillimeter=pointsPerMillimeter
        self.availableWidth=availableWidth; self.displaySignature=displaySignature
        self.onCalibrate=onCalibrate; self.onSavePNG=onSavePNG
        _sphere=State(initialValue:language == .chinese ? "300" : "3")
        _text=State(initialValue:language == .chinese ? "视界" : L("趣味示例文字"))
    }
    private var inputs: String {
        "\(sphere)|\(cylinder)|\(axis)|\(distance)|\(pupil)|\(text)|\(pattern)|\(strength)|\(contentFraction)|\(displaySignature)|\(pointsPerMillimeter)"
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L("趣味视觉实验")).font(.title2.bold())
            Text(L("按已有度数生成预处理图，对比裸眼辨认的感受。本页不测量度数，也不保证改善清晰度。"))
                .foregroundStyle(.secondary)
            HStack {
                entry(usesDegrees ? L("近视（度）") : L("近视（D）"),value:$sphere,label:L("趣味近视度数"))
                entry(usesDegrees ? L("散光（度）") : L("散光（D）"),value:$cylinder,label:L("趣味散光度数"))
            }
            HStack {
                entry(L("散光轴位（°）"),value:$axis,label:L("趣味散光轴位"))
                entry(L("实测观看距离（厘米）"),value:$distance,label:L("趣味观看距离"))
            }
            Text(usesDegrees ? L("按负柱镜处方填写正的度数：例如近视300度填300；散光100度填100。分别体验一只眼，保持输入的观看距离。")
                 : L("按负柱镜处方填写正的屈光度：例如 −3.00 D 填 3；柱镜 −1.00 D 填 1。分别体验一只眼，保持输入的观看距离。"))
                .font(.caption).foregroundStyle(.secondary)
            Picker(L("图案"),selection:$pattern) {
                Text(L("文字")).tag(0); Text(L("爱心")).tag(1); Text(L("箭头")).tag(2)
            }.pickerStyle(.segmented)
            if pattern == 0 {
                TextField(L("显示文字（最多4字）"),text:$text).textFieldStyle(.roundedBorder)
                    .focused($inputFocused,equals:"fun-text").submitLabel(.done).onSubmit { inputFocused=nil }
                    .onChange(of:text) { value in if value.count > 4 { text=String(value.prefix(4)) } }
            }
            VStack(alignment:.leading,spacing:6) {
                Text(L("字体／图案大小 · %.0f%%",contentFraction*100))
                Slider(value:$contentFraction,in:0.4...0.9).accessibilityLabel(L("字体图案大小"))
                    .accessibilityIdentifier("fun-content-size")
                Text(L("调整大小后请重新生成；原图和预处理图会保持相同的图案大小。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack { Text(L("处理强度")); Slider(value:$strength,in:0...1); Text(String(format:"%.0f%%",strength*100)).monospacedDigit() }
            DisclosureGroup(L("瞳孔假设与原理")) {
                VStack(alignment:.leading,spacing:10) {
                    entry(L("估计瞳孔直径（毫米）"),value:$pupil,label:L("趣味瞳孔假设"))
                    Text(L("用简化的眼睛模糊模型做傅里叶域逆滤波，再用逆傅里叶变换生成图像。真实瞳孔、调节和像差未测量，屏幕亮度也有限，因此可能出现光晕或没有改善。这里不是光场屏幕，也不是光学矫正。"))
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(.top,8)
            }
            if !screenConfirmed {
                Text(L("先用尺子校准屏幕尺寸，才能按实际图案大小计算预处理。"))
                Button(L("前往尺寸校准"),action:onCalibrate).buttonStyle(.bordered)
            }
            Button(busy ? L("正在生成…") : L("生成预处理图")) { generate() }
                .buttonStyle(.borderedProminent).disabled(busy || !screenConfirmed)
            if let original=original, let processed=processed {
                Picker(L("对比图像"),selection:$mode) { Text(L("原图")).tag(0); Text(L("预处理")).tag(1) }.pickerStyle(.segmented)
                Image(decorative:mode == 0 ? original : processed,scale:1,orientation:.up)
                    .resizable().interpolation(.none).frame(width:panelPoints,height:panelPoints)
                    .accessibilityElement(children:.ignore).accessibilityLabel(mode == 0 ? L("趣味原图") : L("趣味预处理图"))
                    .accessibilityIdentifier("fun-display-image")
                    .frame(maxWidth:.infinity)
                Text(L("切换原图与预处理图，图案的位置和大小保持一致。请按实际感受比较；看清内容不代表度数准确或近视已矫正。"))
                    .font(.callout).foregroundStyle(.secondary)
                Label(L("保存预处理图（PNG）"),systemImage:"square.and.arrow.down")
                HStack {
                    Button(L("保存到文件")) { beginImageExport() }.buttonStyle(.bordered)
                    #if os(iOS)
                    Button(savingToPhotos ? L("正在保存…") : L("保存到相册")) { saveToPhotos() }
                        .buttonStyle(.bordered).disabled(savingToPhotos)
                    #endif
                }.disabled(imagePNG == nil)
                if let width=generatedWidthMM {
                    Text(L("当前显示宽度约 %.1f 厘米。保存后若被相册自动缩放，预处理效果可能改变；请尽量保持相同显示大小和观看距离。",width/10))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("fun-status") }
            Text(L("输入只用于当前页面，不写入验光研究记录。显示环境或参数改变后，需要重新生成。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth:.infinity,alignment:.leading)
            .background(.white,in:RoundedRectangle(cornerRadius:20))
            .onChange(of:inputs) { _ in
                requestID=UUID(); original=nil; processed=nil; imagePNG=nil; generatedWidthMM=nil
                busy=false; message=L("参数已改变，请重新生成。")
            }
            #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement:.keyboard) {
                    Spacer(); Button(L("完成")) { inputFocused=nil }.accessibilityIdentifier("fun-dismiss-keyboard")
                }
            }
            #endif
    }
    private func entry(_ title:String,value:Binding<String>,label:String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.caption)
            TextField(title,text:value).textFieldStyle(.roundedBorder).accessibilityLabel(label)
                .focused($inputFocused,equals:label).submitLabel(.done).onSubmit { inputFocused=nil }
        }
    }
    private func generate() {
        inputFocused=nil
        guard screenConfirmed,pointsPerMillimeter > 0,
              let s=NumberInput.parse(sphere),let c=NumberInput.parse(cylinder),let a=NumberInput.parse(axis),
              let d=NumberInput.parse(distance),let p=NumberInput.parse(pupil), s >= 0,c >= 0,
              !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || pattern != 0 else {
            message=L("请填写有效的已有度数、观看距离和显示内容。"); return
        }
        let size=256
        guard let target=Self.target(size:size,text:text,pattern:pattern,fraction:contentFraction) else { message=L("图案生成失败，请重试。"); return }
        let settings=VisualPrecompensation.Settings(sphere:-s/powerScale,cylinder:-c/powerScale,axis:a,distanceMeters:d/100,
            pupilMillimeters:p,imageWidthMillimeters:Double(panelPoints)/pointsPerMillimeter,strength:strength)
        let token=UUID(); requestID=token; busy=true; message=""
        Task {
            do {
                let result=try await Task.detached(priority:.userInitiated) {
                    try VisualPrecompensation.render(target:target,size:size,settings:settings)
                }.value
                guard requestID == token else { return }
                guard let source=Self.image(target,size:size),let filtered=Self.image(result.pixels,size:size) else {
                    throw MeasurementError.invalid(L("图片生成失败，请重试。"))
                }
                let data=try PatternPNG.encode(filtered,displayWidthMillimeters:settings.imageWidthMillimeters)
                original=source; processed=filtered; imagePNG=data; generatedWidthMM=settings.imageWidthMillimeters
                mode=1; busy=false
                message=result.clippedFraction > 0.02
                    ? L("部分亮度已达到屏幕上限，可能出现光晕。可降低处理强度再比较；实际效果以你的观察为准。")
                    : L("已按输入的度数与距离生成。请保持观看条件不变，对比两种显示。")
            } catch {
                guard requestID == token else { return }
                busy=false; message=error.localizedDescription
            }
        }
    }
    private func beginImageExport() {
        inputFocused=nil
        guard let data=imagePNG else { return }
        let name="VisionMeasure-precompensated-"+UUID().uuidString.prefix(8)
        onSavePNG(PatternExportRequest(data:data,filename:name) { result in
            switch result {
            case .success: message=L("已保存预处理PNG图片。查看时请保持相同的显示大小和观看距离。")
            case .failure(let error):
                message=(error as NSError).code == NSUserCancelledError ? L("已取消保存。") : L("图片保存失败：%@", error.localizedDescription)
            }
        })
    }
    #if os(iOS)
    private func saveToPhotos() {
        inputFocused=nil
        guard let data=imagePNG,!savingToPhotos else { return }
        savingToPhotos=true
        PHPhotoLibrary.requestAuthorization(for:.addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { savingToPhotos=false; message=L("未获得相册写入权限，可以改用“保存到文件”。") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with:.photo,data:data,options:nil)
            } completionHandler: { success,error in
                DispatchQueue.main.async {
                    savingToPhotos=false
                    message=success ? L("已保存预处理图到相册。查看时请保持相同显示大小和观看距离。") : L("保存到相册失败：%@", error?.localizedDescription ?? L("请重试或保存到文件。"))
                }
            }
        }
    }
    #endif
    private static func encode(_ linear:Double) -> Double {
        linear <= 0.0031308 ? 12.92*linear : 1.055*pow(linear,1/2.4)-0.055
    }
    private static func decode(_ encoded:Double) -> Double {
        encoded <= 0.04045 ? encoded/12.92 : pow((encoded+0.055)/1.055,2.4)
    }
    private static func image(_ pixels:[Double],size:Int) -> CGImage? {
        let bytes=pixels.flatMap { value -> [UInt8] in
            let q=UInt8((min(1,max(0,encode(value)))*255).rounded()); return [q,q,q,255]
        }
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),let space=CGColorSpace(name:CGColorSpace.sRGB) else { return nil }
        return CGImage(width:size,height:size,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:size*4,
            space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,
            decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }
    private static func target(size:Int,text:String,pattern:Int,fraction:Double) -> [Double]? {
        var bytes=[UInt8](repeating:0,count:size*size*4)
        guard let space=CGColorSpace(name:CGColorSpace.sRGB) else { return nil }
        let success=bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,
                space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            let n=Double(size),bg=encode(0.5),ink=encode(0.2)
            context.setFillColor(red:bg,green:bg,blue:bg,alpha:1); context.fill(CGRect(x:0,y:0,width:n,height:n))
            context.setFillColor(red:ink,green:ink,blue:ink,alpha:1)
            if pattern == 0 {
                let baseFont=CTFontCreateWithName("PingFangSC-Semibold" as CFString,n,nil)
                let color=CGColor(colorSpace:space,components:[ink,ink,ink,1])!
                func makeLine(_ font:CTFont) -> CTLine {
                    let attributes:[NSAttributedString.Key:Any]=[NSAttributedString.Key(kCTFontAttributeName as String):font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String):color]
                    return CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:attributes))
                }
                let baseBounds=CTLineGetBoundsWithOptions(makeLine(baseFont),.useOpticalBounds)
                let factor=n*fraction/max(1,max(baseBounds.width,baseBounds.height))
                let line=makeLine(CTFontCreateCopyWithAttributes(baseFont,n*factor,nil,nil))
                let bounds=CTLineGetBoundsWithOptions(line,.useOpticalBounds)
                context.textPosition=CGPoint(x:(n-bounds.width)/2-bounds.minX,y:(n-bounds.height)/2-bounds.minY)
                CTLineDraw(line,context)
            } else if pattern == 1 {
                let path=CGMutablePath(); path.move(to:CGPoint(x:n*0.5,y:n*0.2))
                path.addCurve(to:CGPoint(x:n*0.18,y:n*0.65),control1:CGPoint(x:n*0.2,y:n*0.43),control2:CGPoint(x:n*0.12,y:n*0.53))
                path.addCurve(to:CGPoint(x:n*0.5,y:n*0.7),control1:CGPoint(x:n*0.2,y:n*0.87),control2:CGPoint(x:n*0.4,y:n*0.87))
                path.addCurve(to:CGPoint(x:n*0.82,y:n*0.65),control1:CGPoint(x:n*0.6,y:n*0.87),control2:CGPoint(x:n*0.8,y:n*0.87))
                path.addCurve(to:CGPoint(x:n*0.5,y:n*0.2),control1:CGPoint(x:n*0.88,y:n*0.53),control2:CGPoint(x:n*0.8,y:n*0.43))
                path.closeSubpath(); drawScaled(path,in:context,size:n,fraction:fraction)
            } else {
                let path=CGMutablePath(); path.move(to:CGPoint(x:n*0.2,y:n*0.42)); path.addLine(to:CGPoint(x:n*0.58,y:n*0.42))
                path.addLine(to:CGPoint(x:n*0.58,y:n*0.22)); path.addLine(to:CGPoint(x:n*0.84,y:n*0.5))
                path.addLine(to:CGPoint(x:n*0.58,y:n*0.78)); path.addLine(to:CGPoint(x:n*0.58,y:n*0.58))
                path.addLine(to:CGPoint(x:n*0.2,y:n*0.58)); path.closeSubpath(); drawScaled(path,in:context,size:n,fraction:fraction)
            }
            return true
        }
        guard success else { return nil }
        return stride(from:0,to:bytes.count,by:4).map { decode(Double(bytes[$0])/255) }
    }
    private static func drawScaled(_ path:CGPath,in context:CGContext,size:Double,fraction:Double) {
        let bounds=path.boundingBoxOfPath,scale=size*fraction/max(1,max(bounds.width,bounds.height))
        context.saveGState(); context.translateBy(x:size/2,y:size/2); context.scaleBy(x:scale,y:scale)
        context.translateBy(x:-bounds.midX,y:-bounds.midY); context.addPath(path); context.fillPath(); context.restoreGState()
    }
}
