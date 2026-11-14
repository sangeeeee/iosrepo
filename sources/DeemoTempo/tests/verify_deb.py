"""Check the two binaries, SpringBoard registration and settings dependency in the finished DEB."""
import io
import plistlib
import struct
import sys
import tarfile
from pathlib import Path

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root.parent/'PianoLab'))
sys.dont_write_bytecode=True
from packaging_helpers import signature_check

raw=Path(sys.argv[1]).read_bytes()
assert raw.startswith(b'!<arch>\n')
archives={}
offset=8
while offset<len(raw):
    header=raw[offset:offset+60]
    name=header[:16].decode().strip().rstrip('/')
    size=int(header[48:58])
    if name.endswith('.tar.gz'):
        with tarfile.open(fileobj=io.BytesIO(raw[offset+60:offset+60+size])) as tar:
            archives[name]={m.name.removeprefix('./'):(tar.extractfile(m).read(),m.mode)
                            for m in tar if m.isfile()}
    offset+=60+size+(size%2)

data=archives['data.tar.gz']
control=archives['control.tar.gz']
metadata=control['control'][0].decode().splitlines()
for field in ['Package: com.linghe.deemotempo','Name: DEEMO Trainer','Version: 0.9~beta4','Architecture: iphoneos-arm64']:
    assert field in metadata,field
deps=next(line for line in metadata if line.startswith('Depends:'))
assert 'ws.hbang.common' not in deps and 'firmware (>= 15.0)' in deps and 'uikittools' in deps
app='var/jb/Applications/DeemoTrainer.app/'
info=plistlib.loads(data[app+'Info.plist'][0])
assert info['CFBundleDisplayName']=='DEEMO Trainer' and info['UIDeviceFamily']==[1,2] and info['MinimumOSVersion']=='15.0'
for name,edge in [('Icon-60@2x',120),('Icon-60@3x',180),('Icon-76',76),('Icon-76@2x',152),('Icon-83.5@2x',167)]:
    png=data[app+name+'.png'][0]
    assert struct.unpack_from('>II',png,16)==(edge,edge)
assert info['CFBundleIcons~ipad']['CFBundlePrimaryIcon']['CFBundleIconFiles']==['Icon-76','Icon-83.5']
lib='var/jb/Library/MobileSubstrate/DynamicLibraries/DeemoTempo'
assert plistlib.loads(data[lib+'.plist'][0])=={'Filter':{'Bundles':['com.rayark.pluto']}}
job=plistlib.loads(data['var/jb/Library/LaunchDaemons/com.linghe.deemotrainer.settings.plist'][0])
assert job['UserName']=='mobile' and job['KeepAlive']
daemon=job['ProgramArguments'][0].lstrip('/')
for path,kind in [(app+info['CFBundleExecutable'],2),(lib+'.dylib',6),(daemon,2)]:
    binary,mode=data[path]
    assert mode==0o755 and signature_check(binary,0,kind)['code_pages_verified']>0
    pos=32
    versions=[]
    for _ in range(struct.unpack_from('<I',binary,16)[0]):
        cmd,length=struct.unpack_from('<II',binary,pos)
        if cmd==0x32: versions.append(struct.unpack_from('<II',binary,pos+8))
        pos+=length
    assert versions==[(2,15<<16)],(path,versions)
    assert b'com.linghe.deemotrainer.committed.v1' in binary
for script,flag in [('postinst','-p'),('prerm','-u')]:
    body,mode=control[script]
    assert mode==0o755 and f'uicache {flag} /{app[:-1]}'.encode() in body
print('PASS: signed arm64 app and tweak, iOS 15 minimum, iPad and iPhone icons, registration scripts, DEEMO filter and settings daemon and shared notification names.')

assert b'launchctl bootstrap system' in control['postinst'][0]
assert b'launchctl bootout system/' in control['prerm'][0]
