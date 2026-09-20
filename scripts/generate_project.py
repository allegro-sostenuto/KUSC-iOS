#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project with Python 3. No XcodeGen required."""
from pathlib import Path
import hashlib, json, plistlib
ROOT = Path(__file__).resolve().parents[1]
objects = {}
def oid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def add(key, **fields):
    identity=oid(key); objects[identity]=fields; return identity
def ref(key): return oid(key)
def file(path, kind=None):
    suffix=Path(path).suffix
    return add('file:'+path, isa='PBXFileReference', lastKnownFileType=kind or {'.swift':'sourcecode.swift','.xcassets':'folder.assetcatalog','.xcconfig':'text.xcconfig','.plist':'text.plist.xml','.entitlements':'text.plist.entitlements','.json':'text.json','.xcprivacy':'text.xml'}.get(suffix,'text'), path=path, sourceTree='<group>')
def buildfile(target,path): return add('build:'+target+':'+path,isa='PBXBuildFile',fileRef=file(path))
shared=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Shared').rglob('*.swift'))
modern=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Modern').rglob('*.swift'))
tests=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Tests').glob('*.swift'))
resources=['Assets.xcassets','Configuration/PrivacyInfo.xcprivacy']
app_configs=[('KUSC-SE','16.0',False,False),('KUSC-17','26.0',True,False),('KUSC-SE-CarPlay','16.0',False,True),('KUSC-17-CarPlay','26.0',True,True)]
alltargets=[x[0] for x in app_configs]+['KUSCLiveActivity','KUSCTests']
base_config=file('Configuration/Signing.xcconfig')
productrefs={}
for name in alltargets:
    ext='appex' if name=='KUSCLiveActivity' else 'xctest' if name=='KUSCTests' else 'app'
    productrefs[name]=add('product:'+name,isa='PBXFileReference',explicitFileType={'app':'wrapper.application','appex':'wrapper.app-extension','xctest':'wrapper.cfbundle'}[ext],includeInIndex=0,path=name+'.'+ext,sourceTree='BUILT_PRODUCTS_DIR')

def configlist(name,settings):
    ids=[]
    for config in ['Debug','Release']:
        bs=dict(settings)
        bs.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O', 'DEBUG_INFORMATION_FORMAT':'dwarf' if config=='Debug' else 'dwarf-with-dsym','ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO'})
        bs['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = (bs.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS','') + (' DEBUG' if config=='Debug' else '')).strip()
        ids.append(add('config:'+name+':'+config,isa='XCBuildConfiguration',baseConfigurationReference=base_config,buildSettings=bs,name=config))
    return add('configs:'+name,isa='XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

def dep(target,other):
    proxy=add('proxy:'+target+other,isa='PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=ref('target:'+other),remoteInfo=other)
    return add('dep:'+target+other,isa='PBXTargetDependency',target=ref('target:'+other),targetProxy=proxy)
common={'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','CODE_SIGN_STYLE':'Automatic','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'1','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','GENERATE_INFOPLIST_FILE':'NO','SWIFT_EMIT_LOC_STRINGS':'YES'}
for name,version,is_modern,carplay in app_configs:
    sources=shared+(modern if is_modern else [])+(['CarPlay/CarPlaySceneDelegate.swift'] if carplay else [])
    phases=[add('sources:'+name,isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=[buildfile(name,p) for p in sources],runOnlyForDeploymentPostprocessing=0),add('resources:'+name,isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=[buildfile(name,p) for p in resources],runOnlyForDeploymentPostprocessing=0),add('frameworks:'+name,isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)]
    dependencies=[]
    if is_modern:
        embed=add('embedfile:'+name,isa='PBXBuildFile',fileRef=productrefs['KUSCLiveActivity'],settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
        phases.append(add('embed:'+name,isa='PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
        dependencies=[dep(name,'KUSCLiveActivity')]
    settings=dict(common,IPHONEOS_DEPLOYMENT_TARGET=version,PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_MODULE_NAME='KUSC_SE' if not is_modern else 'KUSC_17',PRODUCT_BUNDLE_IDENTIFIER='$(KUSC_BUNDLE_PREFIX).'+('modern' if is_modern else 'classic'),INFOPLIST_FILE='Configuration/'+('App-CarPlay.plist' if carplay else 'App.plist'),ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',SWIFT_ACTIVE_COMPILATION_CONDITIONS=' '.join(x for x in ['MODERN' if is_modern else '', 'CARPLAY' if carplay else ''] if x))
    settings['CODE_SIGN_ENTITLEMENTS']='Configuration/'+('CarPlay.entitlements' if carplay else 'App.entitlements')
    add('target:'+name,isa='PBXNativeTarget',buildConfigurationList=configlist(name,settings),buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,productName=name,productReference=productrefs[name],productType='com.apple.product-type.application')
name='KUSCLiveActivity'
sources=['Modern/LiveActivityAttributes.swift','Modern/PlaybackIntents.swift','Widget/KUSCLiveActivity.swift']
phases=[add('sources:'+name,isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=[buildfile(name,p) for p in sources],runOnlyForDeploymentPostprocessing=0)]
settings=dict(common,IPHONEOS_DEPLOYMENT_TARGET='26.0',PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='$(KUSC_BUNDLE_PREFIX).modern.activity',INFOPLIST_FILE='Configuration/Widget.plist',APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES',SWIFT_ACTIVE_COMPILATION_CONDITIONS='WIDGET_EXTENSION',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks')
add('target:'+name,isa='PBXNativeTarget',buildConfigurationList=configlist(name,settings),buildPhases=phases,buildRules=[],dependencies=[],name=name,productName=name,productReference=productrefs[name],productType='com.apple.product-type.app-extension')
name='KUSCTests'
fixture_files=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Tests'/'Fixtures').glob('*.json'))
phases=[add('sources:'+name,isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=[buildfile(name,p) for p in tests],runOnlyForDeploymentPostprocessing=0),add('resources:'+name,isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=[buildfile(name,p) for p in fixture_files],runOnlyForDeploymentPostprocessing=0)]
settings=dict(common,IPHONEOS_DEPLOYMENT_TARGET='16.0',PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='$(KUSC_BUNDLE_PREFIX).tests',GENERATE_INFOPLIST_FILE='YES',TEST_HOST='$(BUILT_PRODUCTS_DIR)/KUSC-SE.app/KUSC-SE',BUNDLE_LOADER='$(TEST_HOST)')
add('target:'+name,isa='PBXNativeTarget',buildConfigurationList=configlist(name,settings),buildPhases=phases,buildRules=[],dependencies=[dep(name,'KUSC-SE')],name=name,productName=name,productReference=productrefs[name],productType='com.apple.product-type.bundle.unit-test')
for path in ['Configuration/App.plist','Configuration/App-CarPlay.plist','Configuration/Widget.plist','Configuration/App.entitlements','Configuration/CarPlay.entitlements']: file(path)
products=add('products',isa='PBXGroup',children=list(productrefs.values()),name='Products',sourceTree='<group>')
files=[i for i,o in objects.items() if o['isa']=='PBXFileReference' and o.get('sourceTree')!='BUILT_PRODUCTS_DIR']
main=add('main',isa='PBXGroup',children=files+[products],sourceTree='<group>')
projectsettings={'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','CLANG_WARN_UNGUARDED_AVAILABILITY':'YES_AGGRESSIVE','ENABLE_STRICT_OBJC_MSGSEND':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','SWIFT_STRICT_CONCURRENCY':'minimal','SWIFT_VERSION':'5.0'}
add('project',isa='PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2600','TargetAttributes':{ref('target:'+n):{'CreatedOnToolsVersion':'26.0','ProvisioningStyle':'Automatic'} for n in alltargets}},buildConfigurationList=configlist('Project',projectsettings),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[ref('target:'+n) for n in alltargets])
def fmt(value, indent=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(indent+1)+json.dumps(str(k))+' = '+fmt(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(indent+1)+fmt(v,indent+1)+',\n' for v in value)+'\t'*indent+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value)
project=ROOT/'KUSC.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+fmt({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ref('project')})+'\n')
workspace=project/'project.xcworkspace';workspace.mkdir(exist_ok=True)
(workspace/'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
schemes=project/'xcshareddata'/'xcschemes';schemes.mkdir(parents=True,exist_ok=True)
for name,*_ in app_configs:
    def br(n): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("target:"+n)}" BuildableName="{n}.app" BlueprintName="{n}" ReferencedContainer="container:KUSC.xcodeproj"/>'
    tests_xml=''
    if name=='KUSC-SE': tests_xml=f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("target:KUSCTests")}" BuildableName="KUSCTests.xctest" BlueprintName="KUSCTests" ReferencedContainer="container:KUSC.xcodeproj"/></TestableReference>'
    (schemes/(name+'.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{br(name)}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{tests_xml}</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{br(name)}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{br(name)}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {project.name}: {len(app_configs)} app schemes, one extension, one test target.')
