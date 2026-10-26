#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
swift build -c release
mkdir -p "$task_root/Build"
task_stage="$(mktemp -d "$task_root/Build/.package.XXXXXX")"
task_app="$task_stage/视界研究版.app"
mkdir -p "$task_app/Contents/MacOS"
mkdir -p "$task_app/Contents/Resources"
if [[ -f "$task_root/Resources/AppIcon.icns" ]]; then cp "$task_root/Resources/AppIcon.icns" "$task_app/Contents/Resources/"; fi
cp .build/release/VisionMeasureDesktop "$task_app/Contents/MacOS/VisionMeasure"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VisionMeasure</string>
<key>CFBundleIdentifier</key><string>org.visionmeasure.research</string>
<key>CFBundleName</key><string>视界研究版</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSCameraUsageDescription</key><string>在本机辅助测量眼睛到屏幕的距离；不保存人脸图像。</string>
<key>NSMicrophoneUsageDescription</key><string>可选的本机语音作答，不保存录音。</string>
<key>NSSpeechRecognitionUsageDescription</key><string>仅在设备支持本机识别时处理左边、右边、停止等作答指令。</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
task_final="$task_root/Build/视界研究版.app"
if [[ -d "$task_final" ]]; then mv "$task_final" "$task_stage/previous.app"; fi
mv "$task_app" "$task_final"
printf '%s\n' "$task_final"
