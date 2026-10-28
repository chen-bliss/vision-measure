#!/usr/bin/env python3
"""Generate native iOS/macOS app, shared framework and UI test targets without package resolution."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
objects = {}
models = (ROOT / "Sources/RefractionCore/Models.swift").read_text(encoding="utf-8")
VERSION = re.search(r'static let version = "([^"]+)"', models).group(1)
BUILD = re.search(r'static let build = "([^"]+)"', models).group(1)
LANGUAGES = sorted(path.stem for path in (ROOT / "Resources/Localization").glob("*.lproj"))

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(name, value):
    objects[uid(name)] = value
    return uid(name)

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

files = sorted((ROOT / "Sources/VisionMeasure").glob("*.swift"))
refs, builds = [], []
for file in files:
    ref = add(str(file.name), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote("Sources/VisionMeasure/"+file.name)}; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    builds.append(add("build:"+file.name, f"isa = PBXBuildFile; fileRef = {ref};"))
product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = VisionMeasure.app; sourceTree = BUILT_PRODUCTS_DIR;')
ui_ref = add("ui_ref", 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UITests/FlowTests.swift; sourceTree = SOURCE_ROOT;')
ui_build = add("ui_build",f'isa = PBXBuildFile; fileRef = {ui_ref};')
ui_product = add("ui_product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = VisionMeasureUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
core_refs, core_builds = [], []
for file in sorted((ROOT / "Sources/RefractionCore").glob("*.swift")):
    ref = add("core:"+file.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote("Sources/RefractionCore/"+file.name)}; sourceTree = SOURCE_ROOT;')
    core_refs.append(ref)
    core_builds.append(add("core-build:"+file.name,f'isa = PBXBuildFile; fileRef = {ref};'))
core = add("core", 'isa = PBXFileReference; explicitFileType = wrapper.framework; path = RefractionCore.framework; sourceTree = BUILT_PRODUCTS_DIR;')
core_build = add("core_build", f'isa = PBXBuildFile; fileRef = {core};')
sources = add("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')
frameworks = add("frameworks", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_build}); runOnlyForDeploymentPostprocessing = 0;')
resources = add("resources", 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
asset_ref = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
asset_build = add("asset_build",f'isa = PBXBuildFile; fileRef = {asset_ref};')
variant_groups, variant_builds = [], []
for table in ["Localizable.strings", "InfoPlist.strings"]:
    children = []
    for language in LANGUAGES:
        if (ROOT / f"Resources/Localization/{language}.lproj/{table}").exists():
            children.append(add(f"l10n:{language}:{table}", f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {quote(language)}; path = {quote(f"Resources/Localization/{language}.lproj/{table}")}; sourceTree = SOURCE_ROOT;'))
    group_id = add(f"l10n-group:{table}", f'isa = PBXVariantGroup; children = ({",".join(children)}); name = {quote(table)}; sourceTree = "<group>";')
    variant_groups.append(group_id)
    variant_builds.append(add(f"l10n-build:{table}", f"isa = PBXBuildFile; fileRef = {group_id};"))
objects[resources] = f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join([asset_build]+variant_builds)}); runOnlyForDeploymentPostprocessing = 0;'
products = add("products", f'isa = PBXGroup; children = ({product},{core},{ui_product}); name = Products; sourceTree = "<group>";')
core_group = add("core_group",f'isa = PBXGroup; children = ({",".join(core_refs)}); name = RefractionCore; sourceTree = "<group>";')
group = add("group", f'isa = PBXGroup; children = ({",".join(refs+[core_group,asset_ref]+variant_groups+[ui_ref,products])}); sourceTree = "<group>";')

base = {
    "SDKROOT": "auto", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
    "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "MACOSX_DEPLOYMENT_TARGET": "13.0",
    "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES", "SWIFT_STRICT_CONCURRENCY": "minimal",
}
app = {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "org.visionmeasure.research",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "GENERATE_INFOPLIST_FILE": "YES", "CURRENT_PROJECT_VERSION": BUILD, "MARKETING_VERSION": VERSION,
    "INFOPLIST_KEY_CFBundleDisplayName": "VisionMeasure Research",
    "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription": "Adds the generated precompensated image only when you choose Save to Photos. Existing photos are never read.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "The camera helps measure eye-to-screen distance on this device. No face images are stored.",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": "Optional on-device voice answers let you say left, right or stop from a distance. No audio is recorded.",
    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription": "Only answer commands such as left, right and stop are processed, and only with on-device recognition. Cloud recognition is never used.",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.healthcare-fitness",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "TARGETED_DEVICE_FAMILY": "1,2", "ENABLE_APP_SANDBOX": "YES", "ENABLE_RESOURCE_ACCESS_CAMERA": "YES",
    "ENABLE_RESOURCE_ACCESS_AUDIO_INPUT":"YES",
    "CODE_SIGN_STYLE": "Automatic", "SUPPORTS_MACCATALYST": "NO",
    "LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks @executable_path/../Frameworks",
    "FRAMEWORK_SEARCH_PATHS":"$(inherited) $(BUILT_PRODUCTS_DIR)",
}
ui_settings = {"PRODUCT_NAME":"$(TARGET_NAME)","PRODUCT_BUNDLE_IDENTIFIER":"org.visionmeasure.research.uitests",
               "GENERATE_INFOPLIST_FILE":"YES","TEST_TARGET_NAME":"VisionMeasure","CODE_SIGN_STYLE":"Automatic",
               "TEST_TARGET_PATH":"$(BUILT_PRODUCTS_DIR)/VisionMeasure.app",
               "IPHONEOS_DEPLOYMENT_TARGET":"17.0",
               "SUPPORTED_PLATFORMS":"iphoneos iphonesimulator","TARGETED_DEVICE_FAMILY":"1,2"}
core_settings = {"PRODUCT_NAME":"RefractionCore","PRODUCT_BUNDLE_IDENTIFIER":"org.visionmeasure.research.core",
                 "GENERATE_INFOPLIST_FILE":"YES","DEFINES_MODULE":"YES","SKIP_INSTALL":"YES",
                 "MACH_O_TYPE":"staticlib","DYLIB_INSTALL_NAME_BASE":"@rpath",
                 "CURRENT_PROJECT_VERSION":"1","MARKETING_VERSION":"0.1.0","CODE_SIGN_STYLE":"Automatic"}
for prefix, settings in [("project", base), ("app", app), ("ui", ui_settings), ("core",core_settings)]:
    configs = []
    for mode in ["Debug", "Release"]:
        values = dict(settings)
        if prefix == "project":
            values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if mode == "Debug" else "-O"
            if mode == "Debug": values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        config = add(prefix+mode, f'isa = XCBuildConfiguration; buildSettings = {{{"".join(quote(k)+" = "+quote(v)+";" for k,v in values.items())}}}; name = {mode};')
        configs.append(config)
    add(prefix+"configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
core_sources = add("core_sources",f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(core_builds)}); runOnlyForDeploymentPostprocessing = 0;')
core_target = add("core_target",f'isa = PBXNativeTarget; buildConfigurationList = {uid("coreconfigs")}; buildPhases = ({core_sources}); buildRules = (); dependencies = (); name = RefractionCore; productName = RefractionCore; productReference = {core}; productType = "com.apple.product-type.framework";')
core_proxy = add("core_proxy",f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {core_target}; remoteInfo = RefractionCore;')
core_dependency = add("core_dependency",f'isa = PBXTargetDependency; target = {core_target}; targetProxy = {core_proxy};')
target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {uid("appconfigs")}; buildPhases = ({sources},{frameworks},{resources}); buildRules = (); dependencies = ({core_dependency}); name = VisionMeasure; productName = VisionMeasure; productReference = {product}; productType = "com.apple.product-type.application";')
ui_sources = add("ui_sources",f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ui_build}); runOnlyForDeploymentPostprocessing = 0;')
proxy = add("ui_proxy",f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = VisionMeasure;')
dependency = add("ui_dependency",f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
ui_target = add("ui_target",f'isa = PBXNativeTarget; buildConfigurationList = {uid("uiconfigs")}; buildPhases = ({ui_sources}); buildRules = (); dependencies = ({dependency}); name = VisionMeasureUITests; productName = VisionMeasureUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
project = add("project", f'isa = PBXProject; attributes = {{LastUpgradeCheck = 1600;}}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = ({",".join(quote(code) for code in LANGUAGES+["Base"])}); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},{core_target},{ui_target});')
out = ROOT / "VisionMeasure.xcodeproj"
out.mkdir(exist_ok=True)
(out / "project.pbxproj").write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+"\n".join(k+" = {"+v+"};" for k,v in objects.items())+f'\n}}; rootObject = {project};}}\n')
schemes = out / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="VisionMeasure.app" BlueprintName="VisionMeasure" ReferencedContainer="container:VisionMeasure.xcodeproj"/>'
(schemes / "VisionMeasure.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="VisionMeasureUITests.xctest" BlueprintName="VisionMeasureUITests" ReferencedContainer="container:VisionMeasure.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
''')
print(out)
