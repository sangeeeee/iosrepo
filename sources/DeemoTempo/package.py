import sys,hashlib,plistlib,os
from pathlib import Path
root=Path(__file__).resolve().parent
repo=root.parents[1]
sys.dont_write_bytecode=True
sys.path.insert(0,str(repo/'sources/PianoLab'))
from packaging_helpers import signature_check,archive
package='com.linghe.deemotempo'
version='0.9~beta2'
binary=(root/'build/DeemoTempo.dylib').read_bytes()
check=signature_check(binary,expected_subtype=0,expected_kind=6)
assert check['code_pages_verified']>0
base='./var/jb/Library/MobileSubstrate/DynamicLibraries/DeemoTempo'
payload={base+'.dylib':(binary,0o755),base+'.plist':(plistlib.dumps({'Filter':{'Bundles':['com.rayark.pluto']}}),0o644)}
app='./var/jb/Applications/DeemoTrainer.app'
executable=(root/'build/DeemoTrainer').read_bytes()
signature_check(executable,expected_subtype=0,expected_kind=2)
orient=['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']
info={'CFBundleExecutable':'DeemoTrainer','CFBundleIdentifier':'com.linghe.deemotrainer',
      'CFBundleName':'DEEMO Trainer','CFBundleDisplayName':'DEEMO Trainer','CFBundlePackageType':'APPL',
      'CFBundleVersion':'91','CFBundleShortVersionString':'0.9','MinimumOSVersion':'15.0',
      'UIDeviceFamily':[1,2],'LSRequiresIPhoneOS':True,'UILaunchScreen':{},
      'UISupportedInterfaceOrientations':orient,'UISupportedInterfaceOrientations~ipad':orient+['UIInterfaceOrientationPortraitUpsideDown'],
      'CFBundleIcons':{'CFBundlePrimaryIcon':{'CFBundleIconFiles':['Icon-60']}},
      'CFBundleIcons~ipad':{'CFBundlePrimaryIcon':{'CFBundleIconFiles':['Icon-76','Icon-83.5']}}}
payload[app+'/DeemoTrainer']=(executable,0o755)
payload[app+'/Info.plist']=(plistlib.dumps(info),0o644)
for size,name in [(76,'Icon-76'),(120,'Icon-60@2x'),(152,'Icon-76@2x'),(167,'Icon-83.5@2x'),(180,'Icon-60@3x')]:
    payload[f'{app}/{name}.png']=((root/f'resources/Icon-{size}.png').read_bytes(),0o644)
service='com.linghe.deemotrainer.settings'
daemon='./var/jb/usr/libexec/deemotrainer-settings'
helper=(root/'build/deemotrainer-settings').read_bytes()
signature_check(helper,expected_subtype=0,expected_kind=2)
payload[daemon]=(helper,0o755)
job=f'/var/jb/Library/LaunchDaemons/{service}.plist'
payload['.'+job]=(plistlib.dumps({'Label':service,'ProgramArguments':[daemon[1:]],'UserName':'mobile',
                                  'RunAtLoad':True,'KeepAlive':True}),0o644)
control=f"""Package: {package}
Name: DEEMO Trainer
Version: {version}
Architecture: iphoneos-arm64
Description: Home Screen settings and live practice controls for DEEMO 5.0.8 (1001405).
Section: Tweaks
Author: Local Build
Maintainer: Local Build
Depends: mobilesubstrate, uikittools, firmware (>= 15.0)
""".encode()
scripts={'./control':(control,0o644)}
for name,phase,flag in [('postinst','configure','-p'),('prerm','remove','-u')]:
    content=f'''#!/bin/sh
set -e
if [ "$1" = "{phase}" ]; then
    if [ -x /var/jb/usr/bin/uicache ]; then
        /var/jb/usr/bin/uicache {flag} /var/jb/Applications/DeemoTrainer.app
    else
        uicache {flag} /var/jb/Applications/DeemoTrainer.app
    fi
fi
'''
    if name=='postinst':
        content=content.replace('    if [ -x', f'    launchctl bootout system/{service} 2>/dev/null || true\n    launchctl bootstrap system {job}\n    if [ -x',1)
    else:
        content=content.replace('    if [ -x', f'    launchctl bootout system/{service} 2>/dev/null || true\n    if [ -x',1)
    scripts['./'+name]=(content.encode(),0o755)
out=bytearray(b'!<arch>\n')
for name,data in [('debian-binary',b'2.0\n'),('control.tar.gz',archive(scripts)),('data.tar.gz',archive(payload))]:
    out.extend(f'{name:<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode());out.extend(data)
    if len(data)%2:out.extend(b'\n')
path=repo/'debs'/f'{package}_{version}_iphoneos-arm64.deb'
temp=path.with_suffix('.deb.tmp')
temp.write_bytes(out);os.replace(temp,path)
print(f'{path.name}: {len(out)} bytes, SHA256 {hashlib.sha256(out).hexdigest()}')
