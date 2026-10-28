import SwiftUI
import Combine
import UniformTypeIdentifiers
import RefractionCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SessionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(record: SessionRecord?) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = (try? encoder.encode(record)) ?? Data()
    }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ContentView: View {
    @StateObject private var model = MeasurementModel()
    @StateObject private var camera = CameraService()
    @StateObject private var voice = VoiceControl()
    @Environment(\.scenePhase) private var scenePhase
    @State private var deleteCandidate: UUID?
    @State private var postureToken = 0
    @State private var showStimulusPreview = false
    @State private var pendingImageExport: PatternExportRequest?
    @State private var imageExportPresented = false
    private enum InputField: Hashable { case participant, screen, distance, uncertainty, cameraUncertainty, firstReference, secondReference }
    @FocusState private var focusedInput: InputField?
    @AppStorage(AppLanguage.preferenceKey) private var languagePreference = ""
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    private let accent = Color(red: 0.12, green: 0.30, blue: 0.74)
    private var language: AppLanguage { AppLanguage(rawValue: languagePreference) ?? AppLanguage.resolve(Locale.preferredLanguages) }
    private var tabs: [String] { [L("准备"), L("距离"), L("测试"), L("记录"), L("趣味")] }
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppInfo.version }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Picker(L("步骤"), selection: $model.page) {
                    ForEach(0..<tabs.count, id: \.self) { Text(tabs[$0]).tag($0) }
                }.pickerStyle(.segmented).disabled(model.testing)
                if model.page == 0 { setup }
                if model.page == 1 { distanceSetup }
                if model.page == 2 { test }
                if model.page == 3 { records }
                if model.page == 4 {
                    FunVisionView(language:language,screenConfirmed:model.screenConfirmed,pointsPerMillimeter:model.pointsPerMM,
                        availableWidth:model.displayContext?.widthPoints ?? 360,displaySignature:model.displayCalibrationSignature,
                        onCalibrate:{ model.page=0 },onSavePNG:{ request in pendingImageExport=request; imageExportPresented=true })
                    .id(language)
                }
                if !model.message.isEmpty {
                    Label(model.message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                }
                if !model.dataError.isEmpty { Text(model.dataError).foregroundColor(.red) }
                Text(L("仅使用设备自带屏幕与摄像头 · 图像在本机处理 · 不保存人脸照片"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24).frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.95, green: 0.97, blue: 0.99))
        .tint(accent).preferredColorScheme(.light)
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        .onChange(of: languagePreference) { _ in voice.stop(); model.message = "" }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement:.keyboard) {
                if model.page != 4 {
                Spacer()
                Button(L("完成")) { focusedInput = nil }.accessibilityIdentifier("dismiss-input-keyboard")
                }
            }
        }
        #endif
        .sheet(isPresented: $showStimulusPreview) { StimulusPreviewView() }
        .onReceive(timer) { _ in
            model.refresh(camera: camera)
            voice.updateMeasurement(trialID:model.stimulusID, ready:model.testing && model.canAnswer)
            // Re-sample scene geometry even if a panel transition does not trigger view layout.
            postureToken += 1
        }
        .onAppear {
            #if os(iOS)
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            #endif
            voice.onCommand = { side in
                guard model.testing else { return false }
                if side == -1 { model.stop(reason:L("用户通过语音停止，未完成的测试不输出度数。")); voice.stop(); return true }
                else {
                    let previousCount = model.record?.trials.count ?? 0
                    model.answer(side)
                    voice.updateMeasurement(trialID:model.stimulusID, ready:model.testing && model.canAnswer)
                    return (model.record?.trials.count ?? 0) > previousCount
                }
            }
        }
        .onChange(of: model.testing) { testing in if !testing { voice.stop(); camera.stop(); model.resetDistance() } }
        .background(DisplayObserver(refreshToken:postureToken) { context in
            if model.updateDisplayContext(context) { camera.stop(); voice.stop() }
        }.allowsHitTesting(false).accessibilityHidden(true))
        #if os(iOS)
        // Gravity notifications only refresh metadata; actual scene geometry controls calibration.
        .onReceive(NotificationCenter.default.publisher(for:UIDevice.orientationDidChangeNotification)) { _ in postureToken += 1 }
        .onDisappear { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        #endif
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                camera.stop(); voice.stop(); model.resetDistance()
                if model.testing { model.stop(reason: L("应用离开前台，测试已中止并保存。请重新开始，避免使用中断后的距离。")) }
            }
        }
        .fileExporter(isPresented:Binding(get:{model.showExport || imageExportPresented},set:{ value in
            if !value { model.showExport=false; imageExportPresented=false }
        }),document:PatternImageDocument(data:pendingImageExport?.data ?? SessionDocument(record:model.exportRecord).data),
            contentType:pendingImageExport == nil ? .json : .png,
            defaultFilename:pendingImageExport?.filename ?? "vision-\(model.exportRecord?.id.uuidString ?? "session").json") { result in
            if let request=pendingImageExport { pendingImageExport=nil; request.completion(result) }
            else if case .failure(let error)=result { model.message=L("导出失败：%@", error.localizedDescription) }
        }
        .confirmationDialog(L("删除这次本机记录？建议先导出备份。"), isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button(L("删除记录"), role: .destructive) { if let id = deleteCandidate { model.deleteRecord(id) }; deleteCandidate = nil }
            Button(L("取消"), role: .cancel) { deleteCandidate = nil }
        }
        #if DEBUG
        .overlay(alignment:.bottom) {
            if ProcessInfo.processInfo.arguments.contains("--ui-test") {
                Text(testDisplayState).font(.system(size:6)).accessibilityIdentifier("test-display-context")
            }
        }
        #endif
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L("视界"), systemImage: "eye.circle.fill").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(accent)
                Text(L("探索你的视觉边界")).font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(L("研究版 %@", appVersion)).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(accent.opacity(0.08), in: Capsule()).foregroundColor(accent)
                Picker(selection: $languagePreference) {
                    Text(L("跟随系统")).tag("")
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0.rawValue) }
                } label: { Label(L("界面语言"), systemImage: "globe") }
                .pickerStyle(.menu).fixedSize().disabled(model.testing)
                .accessibilityIdentifier("language-picker")
            }
        }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
    private var setup: some View {
        VStack(spacing: 20) {
            card(L("一次测量，从可靠的条件开始")) {
                Text(L("分别测量左右眼。请摘下眼镜和隐形眼镜，遮住另一只眼但不要按压眼球；保持均匀照明，关闭原彩与夜览，测试中勿眯眼。先辨认有条纹的一侧，再在不同距离重复。"))
                    .foregroundStyle(.secondary)
                Text(L("本版本用于研究，尚不能作为配镜处方。完整测试包含6个方向、各2次重复，可能需要较长时间；疲劳时应停止。"))
                    .font(.callout).foregroundColor(accent)
                TextField(L("匿名编号，例如 P001（不要填写姓名）"), text: $model.participantID).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("participant-id")
                    .focused($focusedInput,equals:.participant).submitLabel(.done).onSubmit { focusedInput = nil }
                Picker(L("测试眼"), selection: $model.eye) { ForEach(Eye.allCases, id: \.self) { Text($0.localizedName).tag($0) } }.pickerStyle(.segmented)
                Toggle(L("我已满18岁，无已知影响本测试的眼病，并按上述要求裸眼测试"), isOn: $model.adultSuitable)
                Toggle(L("我了解这只是未经临床验证的研究估计，记录仅保存在本机"), isOn: $model.acknowledged)
            }
            card(L("校准屏幕上的真实尺寸")) {
                Text(L("请用尺子测量下方蓝线两端之间的实际长度。更换屏幕、显示缩放、旋转设备或使用显示放大后，需要重新校准。"))
                    .font(.callout).foregroundStyle(.secondary)
                HStack { Spacer(); Rectangle().fill(accent).frame(width: 200, height: 4); Spacer() }.padding(.vertical, 16)
                HStack {
                    TextField(L("蓝线实测长度（厘米）"), text: $model.screenMeasuredCM).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("screen-length")
                        .focused($focusedInput,equals:.screen).submitLabel(.done).onSubmit { confirmScreen() }
                    Button(L("确认尺寸")) { confirmScreen() }.buttonStyle(.bordered).accessibilityIdentifier("confirm-screen")
                }
                if model.screenConfirmed {
                    Label(L("尺寸已校准 · 最近距离 %ld 厘米", Int(model.nearestMeters * 100)), systemImage: "checkmark.circle.fill").foregroundColor(.green)
                    Text(L("为避免像素不足，本机可测范围受到最近距离限制。高近视、远视及混合散光可能无法完成测量，应用会保留失败原因。")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { model.page = 1 } label: { Label(L("设置测距方式"), systemImage: "arrow.forward").frame(maxWidth: .infinity).padding(8) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("go-distance")
        }
    }
    private var manualFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("用尺子或卷尺测量受测眼到屏幕平面的距离；保持眼睛与图案等高、屏幕正对眼睛。每次换位置后重新测量。"))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField(L("距离（厘米）"), text: $model.manualCM).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("manual-distance")
                    .focused($focusedInput,equals:.distance).submitLabel(.done).onSubmit { confirmManualDistance() }
                TextField(L("估计误差（毫米）"), text: $model.manualErrorMM).textFieldStyle(.roundedBorder)
                    .focused($focusedInput,equals:.uncertainty).submitLabel(.done).onSubmit { confirmManualDistance() }
            }
            Button(L("确认已实测，并保持不动")) { confirmManualDistance() }.buttonStyle(.bordered).accessibilityIdentifier("confirm-distance")
            Text(L("确认后不会按时间重置。人工模式无法自动识别移动；每次移动、目标距离改变或中断后，需重新实测并确认。请如实填写误差。")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var distanceSetup: some View {
        VStack(spacing: 20) {
            card(L("选择适合当前设备的测距方式")) {
                Picker(L("测距方式"), selection: $model.distanceMode) { Text(L("人工测距")).tag(0); Text(L("摄像头辅助")).tag(1) }
                    .pickerStyle(.segmented).onChange(of: model.distanceMode) { _ in model.resetDistance(); camera.stop() }
                if model.distanceMode == 0 { manualFields }
                else { cameraFields }
                distanceBadge
            }
            card(L("测试时如何操作")) {
                Text(L("应用会提示目标距离。到达位置并稳定后，左右测试区域中会有一侧出现条纹，点击对应按钮。不确定时可以猜测；不要根据界面装饰判断。每个正式位置完成16次判断，必要时重复核验。"))
                Text(L("若无法自动测距，随时切换人工模式。没有可靠的距离参照时，无法计算可信的屈光度数。"))
                    .font(.callout).foregroundStyle(.secondary)
                Text(L("距离较远时，手机无法伸手点击，请先开启语音，或由协助者按你的回答点击；Mac 也可用键盘左右方向键。保持受测眼到屏幕的距离不变。")).font(.callout).foregroundStyle(.secondary)
                voiceControls
                Button(L("查看条纹显示示例")) { showStimulusPreview = true }.buttonStyle(.bordered)
            }
            Button { model.start() } label: { Label(L("开始练习与测量"), systemImage: "play.fill").frame(maxWidth: .infinity).padding(8) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("start-test")
        }
    }
    private var cameraFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(L("开启摄像头")) { model.resetDistance(); camera.start() }.buttonStyle(.bordered)
                Button(L("改用普通摄像头")) { model.resetDistance(); camera.start(preferDepth: false) }.buttonStyle(.bordered)
                if camera.running { Button(L("关闭")) { camera.stop(); model.resetDistance() } }
            }
            Text(camera.status).font(.callout).foregroundStyle(.secondary)
            Text(L("请关闭摄像头自动构图和变焦，保持视角固定；改变视角或坐姿后重新校准。")).font(.caption).foregroundStyle(.secondary)
            if camera.depth == nil {
                Text(L("普通摄像头需要两个已知距离。校准范围应覆盖本次所有测试位置（%ld厘米至300厘米）；若远处无法识别人脸，请使用人工测距。", Int(model.nearestMeters * 100)))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(L("人工测距的估计误差（毫米）"), text: $model.manualErrorMM).textFieldStyle(.roundedBorder)
                    .focused($focusedInput,equals:.cameraUncertainty).submitLabel(.done).onSubmit { focusedInput = nil }
                HStack {
                    TextField(L("第一个实测距离（厘米）"), text: $model.referenceCM).textFieldStyle(.roundedBorder)
                        .focused($focusedInput,equals:.firstReference).submitLabel(.done).onSubmit { focusedInput = nil }
                    Button(L("记录第一点")) { focusedInput = nil; model.captureReference(camera.face) }
                }
                HStack {
                    TextField(L("第二个实测距离（厘米）"), text: $model.verificationCM).textFieldStyle(.roundedBorder)
                        .focused($focusedInput,equals:.secondReference).submitLabel(.done).onSubmit { focusedInput = nil }
                    Button(L("核验第二点")) { focusedInput = nil; model.verifyCamera(camera.face) }
                }
                if model.calibration != nil { Label(L("个人两点校准通过"), systemImage: "checkmark.circle").foregroundColor(.green) }
            }
        }
    }
    private var distanceBadge: some View {
        HStack {
            Image(systemName: model.reading == nil ? "ruler" : "checkmark.circle.fill")
            if let value = model.reading {
                Text(L("当前 %1$.1f 厘米 · 距离误差估计 ±%2$.1f 毫米", value.meters * 100, value.uncertaintyMeters * 1000))
            } else { Text(model.distanceIssue) }
        }.font(.callout).foregroundColor(model.reading == nil ? .secondary : accent)
    }
    private var test: some View {
        VStack(spacing: 20) {
            if model.testing {
                card(model.training ? L("先熟悉图案") : L("寻找不同方向的清晰边界")) {
                    HStack {
                        Text(model.eye.localizedName).font(.headline)
                        Spacer()
                        Text(model.training ? L("练习 %ld/8", model.trainingCount) : L("方向 %1$ld/12 · 本位置 %2$ld/%3$ld", model.directionIndex+1, model.search.blockProgress, ThresholdSearch.blockSize))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L("请到距屏幕 %.1f 厘米的位置", model.targetMeters * 100)).font(.title2.weight(.semibold))
                    distanceBadge
                    if model.training {
                        Text(L("练习使用6倍宽条纹和更大的圆形区域，仅用于熟悉操作，不计算度数。正式测量的条纹会更细；若最近距离仍无法辨认，可能超出本机可测范围。"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Label(model.stimulusStatus, systemImage: model.canAnswer ? "checkmark.circle" : "info.circle")
                        .font(.callout).foregroundColor(model.canAnswer ? .secondary : accent)
                        .accessibilityIdentifier("stimulus-status")
                    if model.distanceMode == 0 { manualFields }
                    else {
                        Text(camera.status).font(.caption).foregroundStyle(.secondary)
                        Button(L("停止并改用人工测距")) { model.stop(reason: L("用户选择改用人工测距；请设置后重新开始。")); model.distanceMode = 0; model.page = 1; model.resetDistance(); camera.stop() }
                    }
                    HStack(spacing: 16) {
                        ForEach(0..<2) { side in
                            GeometryReader { geometry in
                                GratingView(side: side, correctSide: model.correctSide, meridian: model.meridian,
                                            stripeWidth: model.stripeWidth, diameter: model.patchDiameter, visible: model.stimulusVisible)
                                    .onAppear { model.maxPatchPoints = min(geometry.size.width, geometry.size.height) }
                                    .onChange(of: geometry.size) { size in model.maxPatchPoints = min(size.width, size.height) }
                                if !model.stimulusVisible {
                                    Text(L("等待显示条件")).font(.caption).foregroundColor(.white)
                                        .frame(maxWidth:.infinity,maxHeight:.infinity)
                                }
                            }.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(.vertical, 12)
                        // Patch 0 must stay physically on the left in right-to-left languages.
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityElement(children:.ignore).accessibilityLabel(L("左右测试区域"))
                        .accessibilityIdentifier("stimulus-pair")
                    if !model.stimulusVisible {
                        Button(L("查看条纹显示示例")) { showStimulusPreview = true }.buttonStyle(.bordered)
                    }
                    HStack(spacing: 16) {
                        Button(L("左侧有条纹")) { model.answer(0) }.frame(maxWidth: .infinity).keyboardShortcut(.leftArrow, modifiers: [])
                            .accessibilityIdentifier("answer-left")
                        Button(L("右侧有条纹")) { model.answer(1) }.frame(maxWidth: .infinity).keyboardShortcut(.rightArrow, modifiers: [])
                            .accessibilityIdentifier("answer-right")
                    }.buttonStyle(.borderedProminent).disabled(!model.canAnswer)
                        .environment(\.layoutDirection, .leftToRight)
                    voiceControls
                    if model.training {
                        Button(L("我仍无法辨认练习图案")) {
                            model.stop(reason:L("已使用加粗、放大的练习图案，用户仍无法辨认；本机当前条件无法完成练习，未输出度数。请勿将未完成理解为零度。"))
                        }.buttonStyle(.bordered).disabled(!model.stimulusVisible)
                    }
                    ProgressView(value: Double(model.directionIndex), total: 12)
                    Button(L("停止并保存已有记录"), role: .destructive) { voice.stop(); model.stop(reason: L("用户主动停止，未完成的测试不输出度数。")) }
                }
            } else {
                card(L("准备好后开始")) {
                    Text(L("先完成尺寸校准和测距设置。不会在缺少数据时自动猜测近视或散光度数。"))
                    Button(L("返回准备")) { model.page = 0 }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
    private var voiceControls: some View {
        VStack(alignment:.leading,spacing:8) {
            Button(voice.running ? L("关闭语音作答") : L("开启本机语音作答")) { if voice.running { voice.stop() } else { voice.start() } }.buttonStyle(.bordered)
            Text(voice.status).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var records: some View {
        VStack(spacing: 20) {
            if model.history.isEmpty {
                card(L("还没有测试记录")) { Text(L("完成或停止一次测试后，原始记录会出现在这里。记录仅保存在本机，可导出用于验光对照分析。")) }
            }
            ForEach(model.history) { item in
                card("\(item.participantID) · \(item.eye.localizedName)") {
                    Text(item.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(language.locale))).font(.caption).foregroundStyle(.secondary)
                    if item.sessionKind?.hasPrefix("SYNTHETIC") == true { Text(L("模拟／界面测试记录 · 不是真实测量")).font(.caption).foregroundColor(accent) }
                    if let estimate = item.estimate {
                        Text(L("实验估计 · 尚未临床验证")).font(.callout.weight(.semibold)).foregroundColor(accent)
                        HStack(alignment: .top, spacing: 24) {
                            resultValue(L("近视（球镜）"), powerText(estimate.vector.sphere))
                            resultValue(L("散光（柱镜）"), powerText(estimate.vector.cylinder))
                            resultValue(L("轴位"), estimate.axisReportable ? String(format: "%.0f°", estimate.vector.axis) : L("不稳定"))
                        }
                        Text(repeatDifferenceText(estimate.maximumRepeatDifference)).font(.caption).foregroundStyle(.secondary)
                        Text(L("按25度取整显示，不代表准确到25度。实际误差尚未验证，此结果不能用于配镜。")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L("本次未输出度数")).font(.headline)
                        Text(item.stopReason ?? L("数据尚不完整。")).foregroundStyle(.secondary)
                    }
                    Text(L("%1$ld次作答 · %2$ld个方向边界", item.trials.count, item.thresholds.count)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(L("导出完整记录")) { pendingImageExport=nil; imageExportPresented=false; model.prepareExport(item) }.buttonStyle(.bordered)
                        Spacer()
                        Button(L("删除"), role: .destructive) { deleteCandidate = item.id }
                    }
                }
            }
        }
    }
    private func resultValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.monospacedDigit().weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7) }
    }
    /// Chinese users read prescriptions in 度 (0.01 D); other languages use diopters.
    private func powerText(_ diopters: Double) -> String {
        let quarters = (abs(diopters) * 4).rounded()
        if language == .chinese { return L("约%ld度", Int(quarters) * 25) }
        return L("约%@ D", String(format: "%.2f", locale: language.locale, quarters / 4))
    }
    private func repeatDifferenceText(_ diopters: Double) -> String {
        language == .chinese ? L("重复测量最大相差约%.0f度", diopters * 100) : L("重复测量最大相差约%.2f D", diopters)
    }
    private func confirmScreen() { focusedInput = nil; model.calibrateScreen() }
    private func confirmManualDistance() { focusedInput = nil; model.setManualDistance() }
    private var testDisplayState: String {
        model.displayCalibrationSignature
    }
}
