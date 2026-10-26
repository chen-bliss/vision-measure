# 0.3.2 检查摘要 / Verification summary

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
