#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
python3 Tools/check_localization.py
app_version="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/RefractionCore/Models.swift)"
app_build="$(sed -n 's/.*static let build = "\(.*\)".*/\1/p' Sources/RefractionCore/Models.swift)"
swift build -c release
mkdir -p "$task_root/Build"
task_stage="$(mktemp -d "$task_root/Build/.package.XXXXXX")"
trap 'rm -rf -- "$task_stage"' EXIT
task_app="$task_stage/VisionMeasure.app"
mkdir -p "$task_app/Contents/MacOS"
mkdir -p "$task_app/Contents/Resources"
if [[ -f "$task_root/Resources/AppIcon.icns" ]]; then cp "$task_root/Resources/AppIcon.icns" "$task_app/Contents/Resources/"; fi
cp -R "$task_root"/Resources/Localization/*.lproj "$task_app/Contents/Resources/"
cp .build/release/VisionMeasureDesktop "$task_app/Contents/MacOS/VisionMeasure"
cat > "$task_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VisionMeasure</string>
<key>CFBundleIdentifier</key><string>org.visionmeasure.research</string>
<key>CFBundleName</key><string>VisionMeasure</string>
<key>CFBundleDisplayName</key><string>VisionMeasure Research</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>fr</string><string>es</string><string>ru</string><string>ar</string></array>
<key>LSHasLocalizedDisplayName</key><true/>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$app_version</string>
<key>CFBundleVersion</key><string>$app_build</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
<key>NSCameraUsageDescription</key><string>The camera helps measure eye-to-screen distance on this device. No face images are stored.</string>
<key>NSMicrophoneUsageDescription</key><string>Optional on-device voice answers let you say left, right or stop from a distance. No audio is recorded.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Only answer commands such as left, right and stop are processed, and only with on-device recognition. Cloud recognition is never used.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
task_final="$task_root/Build/VisionMeasure.app"
if [[ -d "$task_final" ]]; then mv "$task_final" "$task_stage/previous.app"; fi
mv "$task_app" "$task_final"
printf '%s\n' "$task_final"
