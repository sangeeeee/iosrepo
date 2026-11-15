"""Exercise the compiled settlement hook with the two independent DEEMO II waits."""
import struct

from unicorn import UC_HOOK_CODE
from unicorn.arm64_const import UC_ARM64_REG_LR, UC_ARM64_REG_PC, UC_ARM64_REG_SP, UC_ARM64_REG_X0, UC_ARM64_REG_X1


def verify_practice_result(cpu, binary):
    # Map the signed adapter as a second image alongside the original game.
    base, heap, done = 0x20000000, 0x21000000, 0x2100ff00
    symbols = {}
    p = 32
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        cmd, size = struct.unpack_from('<II', binary, p)
        if cmd == 0x19:
            va, length, offset, n = struct.unpack_from('<4Q', binary, p+24)
            cpu.mem_map(base+va, (length+4095) & ~4095)
            if n:
                cpu.mem_write(base+va, binary[offset:offset+n])
        if cmd == 2:
            table, count, strings, _ = struct.unpack_from('<4I', binary, p+8)
            for j in range(count):
                index, _, _, _, va = struct.unpack_from('<IBBHQ', binary, table+16*j)
                start = strings+index
                name = binary[start:binary.index(b'\0', start)].decode()
                symbols[name] = base+va
        p += size
    cpu.mem_map(heap, 0x10000)

    def symbol(name, args='E'):
        return symbols[f'__ZN12_GLOBAL__N_1{len(name)}{name}{args}']

    def number(address, value, width=8):
        cpu.mem_write(address, value.to_bytes(width, 'little'))

    def read(address, width=1):
        return int.from_bytes(cpu.mem_read(address, width), 'little')

    def call(address, argument=0):
        cpu.reg_write(UC_ARM64_REG_X0, argument)
        cpu.reg_write(UC_ARM64_REG_LR, done)
        cpu.reg_write(UC_ARM64_REG_SP, heap+0xe000)
        cpu.emu_start(address, done, count=20000)
        assert cpu.reg_read(UC_ARM64_REG_PC) in (done, past_animation_wait)
        return cpu.reg_read(UC_ARM64_REG_X0)

    def substitute(address, fn):
        def handler(uc, pc, size, data):
            value = fn(uc.reg_read(UC_ARM64_REG_X0), uc.reg_read(UC_ARM64_REG_X1))
            if value is not None:
                uc.reg_write(UC_ARM64_REG_X0, value)
            uc.reg_write(UC_ARM64_REG_PC, uc.reg_read(UC_ARM64_REG_LR))
        cpu.hook_add(UC_HOOK_CODE, handler, begin=address, end=address)

    def static_block(game_slot, klass):
        number(game_slot, klass)
        number(klass+0xe0, 1, 4)
        number(klass+0xb8, klass+0x200)
        return klass+0x200

    interface = static_block(0x6630fb0, heap+0x1000)
    params = static_block(0x6630fc8, heap+0x2000)
    scores = static_block(0x6630fe0, heap+0x3000)
    owner, ids, delegate, coroutine = (heap+i for i in (0x4000, 0x5000, 0x6000, 0x7000))
    number(interface+0x120, delegate)
    number(delegate+0x18, heap+0x40)
    number(ids+0x18, 17, 4)
    number(coroutine+0x20, owner)
    past_animation_wait = 0x43d7d90
    # Execute the real leave coroutine up to its next UI operation.
    cpu.hook_add(UC_HOOK_CODE, lambda uc, *_: uc.emu_stop(),
                 begin=past_animation_wait, end=past_animation_wait)
    substitute(0x18558fc, lambda *_: None)  # IL2CPP write barrier
    events = []
    fields = {'_missCount': 0x64, 'IsAllCharming': 0x3b, 'IsFullCombo': 0x3a,
              'IsNewRecord': 0x39, 'IsClear': 0x3c, '_isSettlement': 0x90}
    # Model managed handles, field lookup and a clean result. The adapter
    # itself sets the miss count and flags before notifying the UI.
    def find_field(_, name):
        key = bytes(cpu.mem_read(name, 32)).split(b'\0')[0].decode()
        return fields[key]

    def reset_result(handle, _):
        assert handle == ids
        events.append('reset')
        cpu.mem_write(scores, bytes(0x100))

    def animation_started(*_):
        assert read(scores+0x20, 4) == read(scores+fields['_missCount'], 4) == 17
        assert all(read(scores+fields[name]) == 0 for name in ('IsFullCombo', 'IsAllCharming', 'IsClear'))
        events.append('animation')

    substitute(heap+0x40, animation_started)
    substitute(0x43e2c14, reset_result)
    for i, (name, function) in enumerate((
            ('heldObject', lambda h, _: {1: ids, 2: owner}[h]),
            ('findField', find_field), ('fieldOffset', lambda field, _: field),
            ('originalSettle', lambda *_: events.append('original')))):
        address = heap+0x80+i*4
        number(symbol(name), address)
        substitute(address, function)
    number(symbol('base'), 0)
    number(symbol('ready'), 1, 1)
    number(symbol('resultIDs'), 1, 4)
    number(symbol('practiceOwner'), 2, 4)
    settle = symbol('settle', 'EPKv')
    number(symbol('practiceUsed'), 0, 1)
    call(settle)
    assert events == ['original']
    events.clear()
    number(symbol('practiceUsed'), 1, 1)
    number(symbol('historyOK'), 1, 1)
    cpu.mem_write(symbol('region'), struct.pack('<ff', 20, 60))
    call(settle)
    assert not events and read(owner+0x75) == 0
    cpu.mem_write(symbol('region'), struct.pack('<ff', -1, -1))
    call(settle)
    call(settle)  # duplicate native notification
    assert read(owner+0x75) == 1 and call(0x43d8884, coroutine) == 0
    number(coroutine+0x10, 1, 4)
    assert call(0x43d7c10, coroutine) == 1  # still waiting for the animation
    assert events == ['reset', 'animation'], f'local settlement returned, animation was never started or repeated: {events}'
    number(params+4, 1, 1)  # simulated UI completion after the observed request
    call(0x43d7c10, coroutine)
    assert cpu.reg_read(UC_ARM64_REG_PC) == past_animation_wait
    print('PASS: compiled practice settlement starts the result animation once, clears both native waits, defers loops and preserves normal settlement')
