"""Validate the second adapter against the user's copy of DEEMO II 4.1.9.
Optional dependency directories provide UnityPy and Unicorn. No assets are exported.
"""
import json
import plistlib
import re
import struct
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(Path(p).resolve()) for p in sys.argv[2:]]
import UnityPy
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm64_const import (UC_ARM64_REG_X0, UC_ARM64_REG_X1, UC_ARM64_REG_X2,
                                UC_ARM64_REG_X3, UC_ARM64_REG_X4, UC_ARM64_REG_SP,
                                UC_ARM64_REG_LR, UC_ARM64_REG_PC, UC_ARM64_REG_S0)

with zipfile.ZipFile(sys.argv[1]) as ipa:
    app = 'Payload/DEEMOII.app/'
    info = plistlib.loads(ipa.read(app+'Info.plist'))
    assert (info['CFBundleIdentifier'],info['CFBundleShortVersionString'],info['CFBundleVersion']) == (
        'com.rayark.deemo2','4.1.9','97950010')
    image = ipa.read(app+'Frameworks/UnityFramework.framework/UnityFramework')
    header = (root/'src/DeemoII419.hpp').read_text(encoding='utf-8')
    entries = re.findall(r'(\w+)\{(0x[0-9a-f]+),(0x[0-9a-f]+)\}',header)
    for name,offset,word in entries:
        assert struct.unpack_from('<I',image,int(offset,16))[0] == int(word,16),name
    p = 32
    uuid = None
    for _ in range(struct.unpack_from('<I',image,16)[0]):
        tag,size = struct.unpack_from('<II',image,p)
        if tag == 0x1b:
            uuid = image[p+8:p+24].hex()
        p += size
    assert uuid == 'c5c57a1643e83df4a1b2d88e89449b21'
    for caller,callee in [(0x43daa54,0x43f7fe8),(0x43da9d4,0x43cba50),
                          (0x43dab1c,0x43c16f0),(0x43bed7c,0x43e33f4),
                          (0x15e8404,0x16d5dac),(0x15e8438,0x16d5dac)]:
        op = struct.unpack_from('<I',image,caller)[0]
        assert op>>26 == 0x25 and caller+((op&0x3ffffff)^0x2000000)*4-0x8000000 == callee

    # Run the game's first-pass bank decoder on its real compressed music.
    # This executes the RIFF parser and buffer sizing, without the iOS audio device.
    cpu = Uc(UC_ARCH_ARM64,UC_MODE_ARM)
    cpu.mem_map(0,(len(image)+4095)&~4095)
    cpu.mem_write(0,image)
    source,work,end = 0x10000000,0x14000000,0x15000000
    cpu.mem_map(source,64*1024*1024)
    cpu.mem_map(work,0x10000)
    found = set()
    checked_chart = False
    for name in ipa.namelist():
        if 'aaremote/salocal_soundbanks_ios_local_' in name and len(found)<3:
            env = UnityPy.load(ipa.read(name))
            asset = next(iter(env.container),'').split('/')[-1]
            if asset not in ('deja_vu.asset','abiogenesis.asset','op258.asset'):
                continue
            blob = next(o.get_raw_data() for o in env.objects if o.type.name=='MonoBehaviour')
            start = blob.index(b'BKHD')
            length = struct.unpack_from('<I',blob,start-4)[0]
            bank = blob[start:start+length]
            assert len(bank)==length
            fmt = bank.index(b'fmt ')+8
            channels,hz = struct.unpack_from('<HI',bank,fmt+2)
            frames = struct.unpack_from('<I',bank,fmt+24)[0]
            cpu.mem_write(source,bank)
            cpu.mem_write(work,bytes(16))
            for reg,val in [(UC_ARM64_REG_X0,source),(UC_ARM64_REG_X1,length),
                            (UC_ARM64_REG_X2,0xffffffff),(UC_ARM64_REG_X3,work),
                            (UC_ARM64_REG_X4,work+8),(UC_ARM64_REG_LR,end),(UC_ARM64_REG_SP,work+0xff00)]:
                cpu.reg_write(reg,val)
            cpu.emu_start(0x16d5dac,end,count=100000)
            decoded = struct.unpack('<I',cpu.mem_read(work+8,4))[0]
            assert cpu.reg_read(UC_ARM64_REG_X0)==1 and frames*channels*2 <= decoded < frames*channels*2+65536
            found.add(asset)
            print(f'{asset}: {hz} Hz, {channels} channels, {frames/hz:.1f} seconds, {decoded} decoded bytes')
        elif 'aaremote/salocal_rhythm_' in name and not checked_chart:
            env = UnityPy.load(ipa.read(name))
            for obj in env.objects:
                if obj.type.name!='TextAsset':continue
                asset = obj.read()
                if asset.m_Name!='deja_vu.hard':continue
                notes=json.loads(asset.m_Script)['notes']
                assert len(notes)==1747 and any(n.get('duration',0)>0 for n in notes)
                hard_notes = notes
                checked_chart=True
        if len(found)==3 and checked_chart:break
    assert checked_chart and len(found)==3

# Rebuild at several positions with the real ARM64 NotePlaneBase._UpdateNote.
# Substitute the managed list accessor, chart clock and renderer only.
def f32(x): return struct.unpack('<f',struct.pack('<f',x))[0]
times = [f32(f32(n.get('_time',0))+f32(n.get('shift',0))) for n in hard_notes]
p,charts,chart,notes,objects = (source+i for i in (0,0x100,0x200,0x300,0x1000))
def ptr(at,x): cpu.mem_write(at,struct.pack('<Q',x))
def integer(at,x): cpu.mem_write(at,struct.pack('<I',x))
def set_float(x): cpu.reg_write(UC_ARM64_REG_S0,struct.unpack('<I',struct.pack('<f',x))[0])
cpu.mem_write(p,bytes(0x1000+128*len(times)))
ptr(p+0x50,charts);ptr(chart+0x28,notes);integer(notes+0x18,len(times))
klass,statics=work+0x100,work+0x800
ptr(0x6630fc8,klass);integer(klass+0xe0,1);ptr(klass+0xb8,statics)
for i,t in enumerate(times):
    cpu.mem_write(objects+i*128+0x48,struct.pack('<fff',t,0,1))
now = 0
visible = []
def intercept(uc,address,size,user):
    if address==0x2c2fe44:
        container=uc.reg_read(UC_ARM64_REG_X0);i=uc.reg_read(UC_ARM64_REG_X1)
        assert container in (charts,notes)
        uc.reg_write(UC_ARM64_REG_X0,chart if container==charts else objects+i*128)
    elif address==0x43dbeac:set_float(now+2)
    elif address==0x43c73ac:set_float(now)
    elif address==0x43c1ba4:visible.append((uc.reg_read(UC_ARM64_REG_X1)-objects)//128)
    uc.reg_write(UC_ARM64_REG_PC,uc.reg_read(UC_ARM64_REG_LR))
for target in (0x2c2fe44,0x43dbeac,0x43c73ac,0x43c1ba4,0x1855960):
    cpu.hook_add(UC_HOOK_CODE,intercept,begin=target,end=target)
for now in (5,60,30,60,30,90):
    visible.clear()
    start=next((i for i,t in enumerate(times) if t>=now),len(times))
    integer(p+0x58,start);cpu.reg_write(UC_ARM64_REG_X0,p)
    cpu.reg_write(UC_ARM64_REG_LR,end);cpu.reg_write(UC_ARM64_REG_SP,work+0xf000)
    cpu.emu_start(0x43c1768,end,count=100000)
    expected=[i for i,t in enumerate(times) if now<=t<=now+2]
    assert visible==expected and expected,(now,visible,expected)
print(f'PASS: {len(entries)} native entries, three music banks and six native Hard-chart previews in both directions')
