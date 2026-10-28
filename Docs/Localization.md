# 界面语言 / Interface languages

自0.4.0起，应用界面支持联合国六种官方语言：简体中文、英语、法语、西班牙语、俄语和阿拉伯语。默认跟随系统语言；系统语言不在六种之内时使用英语。页首“界面语言”菜单可在应用内切换，测试进行中不可切换。

Since 0.4.0 the interface supports the six official UN languages: Simplified Chinese, English, French, Spanish, Russian and Arabic. It follows the system language and falls back to English. The header language menu switches languages in the app; it is disabled during a test.

应用内切换只控制应用界面和语音词表；系统权限弹窗、文件选择器及访达名称由操作系统的语言偏好决定。历史记录中的停止原因保留记录时的语言。

The in-app choice controls interface text and voice vocabulary. System permission sheets, file pickers and Finder names follow operating-system language preferences. Saved stop reasons retain the language used when the record was created.

## 实现 / Implementation

- 中文原文同时作为查找键。所有界面文字通过 `L("…")` 查表（`Sources/RefractionCore/Localization.swift`），译文位于 `Resources/Localization/<语言>.lproj/Localizable.strings`；权限说明和应用名位于同目录的 `InfoPlist.strings`。
- `Tools/check_localization.py` 检查每个键在五种译文中都存在、格式占位符（含整数宽度）一致、没有遗漏的中文字面量或废弃键。`Tools/build_mac.sh` 打包前会先运行它，持续集成也会运行。`Tools/check_mac_bundle.py` 另检查实际安装包的版本、六语言资源、可执行文件和签名。
- 新增或修改界面文字时，用 `L("中文原文")` 包裹，然后在五个 `Localizable.strings` 中加入译文，再运行检查脚本。需要换序的参数使用 `%1$@`、`%2$ld` 这类位置占位符。

- Chinese source strings double as keys. All UI text goes through `L("…")`; translations live in `Resources/Localization/<code>.lproj/Localizable.strings`, with app name and permission prompts in `InfoPlist.strings`.
- `Tools/check_localization.py` verifies that every key exists in all five translations with matching printf placeholders (including integer widths), and that no Chinese literal bypasses `L()`. Mac packaging and CI run it. `Tools/check_mac_bundle.py` also checks the packaged version, six-language resources, executable and signature.
- To add text, wrap the Chinese source in `L("…")`, add the five translations, and run the checker. Use positional placeholders such as `%1$@` when word order differs.

## 测量相关的约束 / Measurement constraints

- **阿拉伯语从右到左排版不能镜像测试区域。** 左右条纹区域、作答按钮和条纹示例被固定为从左到右布局，否则“左侧有条纹”会跑到屏幕右边，镜像的条纹还会把30°方向变成150°，直接破坏散光轴位。界面测试 `testArabicKeepsLeftAnswerOnPhysicalLeft` 检查这一点。
- 屈光度显示：中文界面沿用“度”（0.01 D）；其他语言显示屈光度 D。趣味页的输入单位同样随语言变化。
- 数字输入接受逗号小数点（法语、西班牙语、俄语键盘）以及阿拉伯-印度数字。
- 导出的JSON中 `eye` 字段仍为“右眼／左眼”，以保持与旧记录和 `validate_study.py` 兼容；新增 `interfaceLanguage` 字段，记录测试时的界面语言，分析时可按语言分层。

- **Right-to-left Arabic must not mirror the test area.** The stimulus patches, answer buttons and preview are pinned left-to-right; otherwise “stripes on left” would sit on the right and a mirrored grating would turn a 30° meridian into 150°, corrupting the axis.
- Chinese shows powers in 度 (0.01 D); other languages show diopters. Fun-page inputs follow the same convention.
- Number fields accept decimal commas and Arabic-Indic digits.
- Exported `eye` values stay `右眼`/`左眼` for compatibility. The new `interfaceLanguage` field allows stratifying analyses by instruction language.

## 语音作答词表 / Voice answer words

| 语言 Language | 左 Left | 右 Right | 停止 Stop | 识别区域 Recognizer |
| --- | --- | --- | --- | --- |
| 简体中文 | 左边 | 右边 | 停止 | zh-CN |
| English | left | right | stop | en-US |
| Français | gauche | droite | stop, arrête | fr-FR |
| Español | izquierda | derecha | alto, parar, detener | es-ES |
| Русский | слева, налево | справа, направо | стоп | ru-RU |
| العربية | يسار، اليسار | يمين، اليمين | توقف، قف | ar-SA |

仍只使用设备端识别。某语言没有本机识别模型时，应用会提示改用按钮、键盘或协助者，不会转向云端。除中文外，其他语言的真实麦克风识别尚未在真机上逐一验证。

Recognition remains on-device only. If a language has no on-device model, the app asks for buttons, keyboard or a helper and never falls back to the cloud. Real-microphone recognition in languages other than Chinese has not yet been verified on a physical device.

## 译文质量 / Translation quality

译文由项目维护者准备，未经各语言母语验光专业人员审校。用于研究招募或知情同意前，应请母语者及眼科、视光专业人员复核，尤其是适用条件、风险提示和“不能用于配镜”的表述。欢迎通过 issue 或 pull request 提交修订。

Translations were prepared by the maintainer and have not been reviewed by native-speaking eye-care professionals. Before using them for recruitment or consent, have native speakers and clinicians review eligibility, risk and “not a prescription” wording. Corrections are welcome via issues or pull requests.
