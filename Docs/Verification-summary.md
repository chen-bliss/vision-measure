# 0.4.0 检查摘要 / Verification summary

版本 / Version: **0.4.0 (build 8)**. Date: **2026-10-28**.

| 项目 / Check | 结果 / Result |
| --- | --- |
| Localization source check | 249 keys × 5 translated languages, no missing keys or placeholder mismatches; six localized app-name/permission tables |
| Core XCTest | 55 passed, 0 failed, including 8 localization cases and 9 voice-routing cases |
| Python checks | 31 passed, 0 failed; localization, clinical-analysis and distance-analysis tools |
| Swift Package debug / Release build | Passed locally on Apple silicon |
| Native Mac Xcode build | Passed with signing disabled in an isolated verification copy |
| iPhone localization UI | 2 passed, 0 failed: all six languages launch with translated labels; Arabic left/right answer buttons retain their physical sides |
| iPhone workflow regression UI | 2 passed, 0 failed: manual-distance gates, visible stripes, confirmation after 30 seconds, stopped-session JSON export; fun-pattern generation, original/processed switching and PNG file export |
| Mac release bundle | Version 0.4.0/build 8, all six declared languages, exact shipped translation contents, runnable arm64 executable and ad hoc signature verified, including after ZIP extraction |
| Synthetic benchmark | 120 synthetic sessions; ideal 40/40, noisy 38/40, systematic-bias 34/40 complete; analysis remains NOT_ESTABLISHED |
| Physical iPhone / multilingual microphone | Not rerun for 0.4.0; previous Chinese voice feedback below is historical |
| Clinical refraction / distance accuracy | NOT_ESTABLISHED; no new professional-reference or independent physical-distance dataset |

核心测试和原生构建使用另一台 Apple 芯片 Mac 的 **Xcode 27.1 (27A9275)、macOS 27.0.1**；界面检查使用 **iPhone 16 Pro / iOS 27.0 模拟器**。本机只有 Command Line Tools，`swift test` 因缺少 XCTest 无法运行，故改用完整 Xcode 环境完成，不计为产品测试失败。

Core tests and native builds used a separate Apple-silicon Mac with **Xcode 27.1 (27A9275), macOS 27.0.1**. UI checks used an **iPhone 16 Pro / iOS 27.0 simulator**. The local Mac has Command Line Tools only, so local `swift test` could not find XCTest; the tests were completed with full Xcode instead.

模拟器本轮仍报告 `Invalid frame dimension (negative or non-finite)` 布局警告，未导致上述断言失败，尚未定位原因；没有据此声称所有设备和系统均兼容。模拟器不能验证物理尺寸、真实摄像头距离、麦克风识别或裸眼光学收益。六语言译文和词表检查不能代替母语专业审校及真机识别测试。系统权限弹窗语言由操作系统决定。

The simulator still reports an `Invalid frame dimension (negative or non-finite)` layout warning. Its cause remains unresolved; the assertions above passed. Compatibility across all devices and supported OS versions is not established. Simulator checks do not validate physical dimensions, actual camera distance, microphone recognition or unaided optical benefit. Translation and vocabulary checks do not replace native-speaking professional review or physical-device speech tests. Operating-system preferences control permission-sheet language.

原始日志、截图及 `.xcresult` 留在本机或验证机，不随公开源码发布。研究记录、设备标识、账户和签名材料不随 Release 分发。

Raw logs, screenshots and `.xcresult` bundles remain local or on the verification machine. Research records, device identifiers, account details and signing material are excluded from release assets.

---

# 0.3.2 历史检查摘要 / Historical verification summary

版本 / Version: **0.3.2 (build 7)**. Date: **2026-10-26**.

| 项目 / Check | 结果 / Result |
| --- | --- |
| Core XCTest | 47 passed, 0 failed; includes 9 voice-routing cases |
| Validation scripts | 27 passed on 0.3.1 (17 clinical-analysis, 10 distance-analysis); scripts unchanged, not rerun for documentation/publication |
| Focused Duo simulator manual workflow | Recheck: 1 passed, 0 failed; keyboard dismissal, visible stripe pixels, manual confirmation after 30 seconds, answer storage and JSON export |
| Initial UI run | Keyboard-dismissal assertion timed out; retained locally, not counted as a pass |
| Recheck finalization | Test case passed; slow optional simulator diagnostic collection was stopped, then Xcode finalized normally and exited 0 |
| Mac archive | Apple silicon Release build; ad hoc signature and extracted-archive executable verified |
| Physical iPhone | Signed 0.3.2/build 7 installed; installed version read back |
| Physical continuous voice | User subsequently reported normal use; self-reported feedback, not a controlled recognition-rate or interruption-recovery study |
| Clinical refraction / distance accuracy | NOT_ESTABLISHED; no professional-reference dataset or independent physical-distance observations imported |

模拟器仍有未定位的布局警告；真实内屏移动、相册写入、语音中断恢复及预处理对裸眼的实际收益尚未完成独立验证。
The simulator still reports an unlocalized layout warning. Physical inner-screen movement, Photos writing, speech-interruption recovery and unaided optical benefit have not completed independent verification.

原始诊断、旧版报告和截图保留在本地 `Docs/Verification/`，可能含设备标识、签名信息或本机路径，因此未上传。这里仅发布结果和范围摘要；不能把使用反馈或模拟实验作为临床证据。
Raw diagnostics, historical reports and screenshots remain local under `Docs/Verification/` because they may contain device identifiers, signing information or machine paths. This repository publishes the results and scope summary; feedback and simulations are not clinical evidence.
