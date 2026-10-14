#!/usr/bin/env python3
"""Generate the dependency-free Xcode project, with stable object identifiers."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
# Never replace an existing project's signing or user settings.
if (root / 'LifePreserver.xcodeproj/project.pbxproj').exists():
    import runpy
    runpy.run_path(str(root / 'scripts/sync-project.py'))
    raise SystemExit(0)
def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def quote(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'

objects = []
def obj(name, content):
    objects.append(f'{ident(name)} = {{ {content} }};')
    return ident(name)

sources = sorted(root.glob('Sources/**/*.swift'))
resources = [root / 'Resources/AppIcon.icns', root / 'Resources/PrivacyInfo.xcprivacy']
source_builds, resource_builds, refs = [], [], []
for path in sources + resources:
    relative = str(path.relative_to(root))
    filetype = 'sourcecode.swift' if path.suffix == '.swift' else 'image.icns' if path.suffix == '.icns' else 'text.xml'
    ref = obj(relative, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quote(relative)}; sourceTree = "<group>";')
    refs.append(ref)
    build = obj(relative + '.build', f'isa = PBXBuildFile; fileRef = {ref};')
    (source_builds if path.suffix == '.swift' else resource_builds).append(build)
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = "Life Preserver.app"; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('products', f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
signing = obj('Resources/Signing.xcconfig', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Resources/Signing.xcconfig; sourceTree = "<group>";')
refs.append(signing)
main = obj('main', f'isa = PBXGroup; children = ({",".join(refs + [products])},); sourceTree = "<group>";')
src = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(source_builds)},); runOnlyForDeploymentPostprocessing = 0;')
res = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0;')
fw = obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for mode in ['Debug', 'Release']:
    project_settings = 'MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0;'
    target_settings = '''PRODUCT_NAME = "Life Preserver"; PRODUCT_BUNDLE_IDENTIFIER = "$(LP_MAC_BUNDLE_IDENTIFIER)"; DEVELOPMENT_TEAM = "$(LP_DEVELOPMENT_TEAM)"; MACOSX_DEPLOYMENT_TARGET = 15.6;
        INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO;
        CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-";
        CODE_SIGN_ENTITLEMENTS = Resources/LifePreserver.entitlements;
        ENABLE_HARDENED_RUNTIME = YES; COMBINE_HIDPI_IMAGES = YES;
        SWIFT_EMIT_LOC_STRINGS = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
        CURRENT_PROJECT_VERSION = 3; MARKETING_VERSION = 1.2.0;
        '''
    target_settings += 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; ENABLE_TESTABILITY = YES;' if mode == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; SWIFT_COMPILATION_MODE = wholemodule;'
    project_configs.append(obj('project'+mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {project_settings} }};'))
    target_configs.append(obj('target'+mode, f'isa = XCBuildConfiguration; name = {mode}; baseConfigurationReference = {signing}; buildSettings = {{ {target_settings} }};'))
pc = obj('project.configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc = obj('target.configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({src},{fw},{res},); buildRules = (); dependencies = (); name = LifePreserver; productName = "Life Preserver"; productReference = {product}; productType = "com.apple.product-type.application";')
project = obj('project', f'isa = PBXProject; attributes = {{ LastSwiftUpdateCheck = 2660; LastUpgradeCheck = 2660; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
output = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n'
(root / 'LifePreserver.xcodeproj/project.pbxproj').write_text(output)
scheme_dir = root / 'LifePreserver.xcodeproj/xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Life Preserver.app" BlueprintName="LifePreserver" ReferencedContainer="container:LifePreserver.xcodeproj"/>'
(scheme_dir / 'LifePreserver.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print('Generated LifePreserver.xcodeproj')
