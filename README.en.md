# VisionMeasure · 视界

[简体中文](README.md) · **English** · [Releases](https://github.com/chen-bliss/vision-measure/releases)

<img src="Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="96" alt="VisionMeasure app icon">

A native iPhone and Mac research app for exploring refractive measurements using the built-in screen, without external optical accessories. The interface is available in the six official UN languages (Chinese, English, French, Spanish, Russian and Arabic); project documentation is in Chinese and English.

**This is a working research prototype, not a clinically validated refraction device or an eyeglass prescription tool.** Accurate sphere, cylinder and axis measurements have not been established against professional refraction. Software tests and user feedback do not replace clinical evidence.

## Features

- Separate eye selection, anonymous participant IDs and ruler-based screen calibration.
- Supported iPhone depth sensing, individually calibrated ordinary-camera distance estimation, or manual ruler measurements. A camera alone does not imply reliable distance measurement.
- Screen-resolution and distance gates, coarse practice patterns, randomized left/right stripe decisions, and repeated searches in six meridians.
- Research estimates of sphere, negative cylinder and axis, with checks for incomplete boundaries and inconsistent repeats. An incomplete test produces no estimate.
- Interface, app name and permission prompts in Simplified Chinese, English, French, Spanish, Russian and Arabic. The app follows the system language (English fallback) and has an in-app language menu. Arabic uses right-to-left layout, but the stimulus patches and left/right answer buttons are pinned to their physical sides. See [interface languages](Docs/Localization.md).
- Optional on-device voice answers in the interface language, e.g. “left/right/stop”, “gauche/droite/stop”, “左边/右边/停止”. Mac arrow keys and helper-operated buttons are also available.
- Number fields accept decimal commas and Arabic-Indic digits. Chinese shows powers in 度 (0.01 D); other languages show diopters.
- Local JSON records and export, plus Python tools for independent distance checks and comparison with professional refraction data.
- A fun visual experiment using a known prescription, text/heart/arrow patterns, adjustable content size, bounded Fourier precompensation, original/processed previews, and processed PNG export. iPhone can optionally add the generated image to Photos.

The fun experiment uses a simplified blur model. It is not a light-field display, does not measure the eye's point spread function, and cannot promise clear unaided vision at a distance. See [experiment details](Docs/Fun-vision-experiment.md).

## Download and run on Mac

Download `VisionMeasure-0.4.0-macOS-arm64.zip` from [v0.4.0](https://github.com/chen-bliss/vision-measure/releases/tag/v0.4.0), extract it, and open `VisionMeasure.app` (Finder shows a localized name).

The supplied app is built for Apple silicon and is ad hoc signed, without Apple notarization or App Store distribution. macOS may require approval in Privacy & Security. No verified Intel binary is included; Intel Macs require a source build.

1. Read the suitability and research notices. The current workflow targets adult unaided participants; it does not establish validity for children, known eye disease, hyperopia or mixed astigmatism.
2. Measure the blue line with a ruler and enter its real length. Recalibrate if the actual display geometry changes.
3. Choose manual distance or a camera method. An ordinary camera requires two individually measured calibration distances.
4. Start practice, then move to each requested distance. A formal position uses 16 decisions; the complete research workflow is lengthy and can be stopped.
5. A confirmed manual distance remains valid at the same position. Re-measure after moving, a target-distance change, a display change or an interruption. At longer distances, use voice or a helper rather than reaching toward the phone.
6. Review/export local records. A failed or incomplete test does not mean zero refractive error. Research estimates are not prescriptions.

For voice responses, wait until the picture is ready and the answer buttons are enabled. Since 0.4.0 the words follow the interface language and recognition stays on-device; languages without an on-device model fall back to buttons. Version 0.3.2 opens a fresh recognition task for each ready trial, accepts one answer per trial, discards stale callbacks and recovers from short interruptions. The user has reported normal continuous voice responses on the physical iPhone after this fix; no controlled recognition-rate study has been performed.

## Build for iPhone

Open `VisionMeasure.xcodeproj`, select the `VisionMeasure` scheme, choose your own developer team under Signing & Capabilities, and run on a trusted device with Developer Mode enabled. The release does not include a generally installable iPhone IPA; device signing is performed with your own team.

- Declared minimum versions: iOS 16 and macOS 13. Compatibility with every supported version/device has not been verified.
- The simulator can test UI and manual workflows, but cannot validate physical screen size, real camera distance, microphone recognition or optical benefit.
- Both platforms share the SwiftUI application and measurement core. The native Xcode project uses a static shared framework; command-line builds use the same sources through Swift Package Manager. There are no third-party package dependencies.
- Regenerate the portable Xcode project with `python3 Tools/create_xcode_project.py`. Select your team again after regeneration. No developer team or remote credentials are hardcoded.

## Build and test locally

```sh
python3 Tools/check_localization.py
swift build
Tools/build_mac.sh
python3 Tools/check_mac_bundle.py Build/VisionMeasure.app
swift test
python3 -m unittest discover -s Tools -p 'test_*.py' -v
```

GitHub Actions runs the localization check, Python tests, `swift build`, `swift test`, Mac packaging and bundle verification on every push and pull request. It also builds the native Mac target and checks six-language iPhone launches and Arabic answer positions. The packaged Mac app is written to `Build/VisionMeasure.app`. Running XCTest requires full Xcode; Command Line Tools alone may compile the app without providing a working XCTest environment.

## Validation tools

Create a professional-refraction template and compare exported sessions with reference data:

```sh
python3 Tools/validate_study.py --template Docs/reference-template.csv
python3 Tools/validate_study.py session-1.json session-2.json \
  --references clinical-references.csv --out Build/validation
```

Open the generated `report.html`; `report.json` contains exclusions, repeatability and grouped results. Reference rows match sessions through `session_id`. See the [validation plan](Docs/Validation-plan.md).

Check distance independently before evaluating refractive accuracy:

```sh
python3 Tools/validate_distance.py --template Docs/distance-reference-template.csv
python3 Tools/validate_distance.py collected-distance.csv --out Build/distance-validation
```

This tool compares app readings against independent ruler measurements, accounts for failed readings and reference uncertainty, excludes personal-calibration positions, and converts distance errors into possible dioptric errors. See [distance collection details](Docs/Distance-check.md).

The tools do not count repeated sessions or both eyes as independent participants, or select only the best repeat. Synthetic data is explicitly labeled and cannot satisfy real-data requirements. No clinical reference dataset or independent hardware-distance dataset is included; clinical status remains `NOT_ESTABLISHED`.

## Synthetic experiment

```sh
swift run RefractionBench Build/synthetic-benchmark
python3 Tools/validate_study.py Build/synthetic-benchmark/SYNTHETIC-sessions.json \
  --references Build/synthetic-benchmark/SYNTHETIC-references.csv \
  --out Build/validation-synthetic
```

The benchmark simulates ideal, noisy and systematically biased observers. It tests computation and failure handling, not actual human vision. Repeatable measurements can still be systematically wrong.

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/RefractionCore` | Distance and display validation, boundary search, refraction fitting, voice-answer routing, localization, precompensation and PNG encoding |
| `Resources/Localization` | Translations (`Localizable.strings`) and localized app name/permission prompts (`InfoPlist.strings`) |
| `Sources/VisionMeasure` | Shared SwiftUI app, camera and speech services, local records and export |
| `Sources/RefractionBench` | Synthetic observers and stress experiments |
| `Tests/RefractionCoreTests` | Deterministic core checks |
| `UITests` | UI and manual-distance workflow checks |
| `Tools` | Project/icon generation, Mac packaging, localization checking and reference-data analysis |
| `Docs` | Research limits, collection procedures and verification summary |

## Verification and privacy

Version 0.4.0 (build 8) passed 55 core tests, 31 Python tests and checks for 249 keys across five translation tables. The Apple-silicon Mac release bundle has been checked for its version, actual language resources and signature. See the [verification summary](Docs/Verification-summary.md) for native Xcode builds, simulator results and environments. This release adds six-language support; it introduces no new clinical or distance-accuracy evidence.

Records stay in the system Application Support `VisionMeasure` directory, or the application container for sandboxed builds. Export records before deleting them. Face images, recordings and speech transcripts are not saved by the app. Photos access is add-only and requested only when saving a generated image. Exported text patterns still contain any text the user entered.

Local diagnostic captures, research records, signing material, credentials and build caches are excluded from the repository and source release. The prebuilt Mac archive is distributed separately as a release asset.

The release includes the Mac app, source and `SHA256SUMS.txt`. With all assets in one directory, run `shasum -a 256 -c SHA256SUMS.txt` to check file integrity. See the [v0.4.0 release notes](Docs/Releases/v0.4.0.md).
