#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace songbank {
struct Bytes {
    const uint8_t *data=nullptr;
    size_t size=0;
    Bytes slice(size_t at,size_t n) const {
        if (at>size || n>size-at) return {};
        return {data+at,n};
    }
    uint32_t u32(size_t i) const {
        uint32_t v=0;
        if (i<=size && size-i>=4) std::memcpy(&v,data+i,4);
        return v;
    }
    uint16_t u16(size_t i) const {
        uint16_t v=0;
        if (i<=size && size-i>=2) std::memcpy(&v,data+i,2);
        return v;
    }
    bool tag(size_t i,const char *s) const {
        return i<=size && size-i>=4 && !std::memcmp(data+i,s,4);
    }
};
inline Bytes chunk(Bytes b,const char *tag,bool padded) {
    size_t i=0;
    while (b.size-i>=8) {
        size_t size=b.u32(i+4);
        Bytes payload=b.slice(i+8,size);
        if (!payload.data) return {};
        if (b.tag(i,tag)) return payload;
        i+=8+size;
        if (padded && (size&1) && i<b.size) ++i;
    }
    return {};
}
struct Wave {
    Bytes fmt,samples;
    unsigned hz() const { return fmt.u32(4); }
    unsigned channels() const { return fmt.u16(2); }
    float seconds() const {
        unsigned frames=fmt.u16(0)==1 ? samples.size/(2*channels()) : fmt.u32(24);
        return float(frames)/hz();
    }
};
inline Wave singleSong(Bytes bank) {
    Bytes index=chunk(bank,"DIDX",false),data=chunk(bank,"DATA",false);
    if (index.size!=12 || !data.size) return {};
    Bytes wav=data.slice(index.u32(4),index.u32(8));
    if (!wav.tag(0,"RIFF") || !wav.tag(8,"WAVE")) return {};
    // DecodeBank can retain the compressed RIFF length; DIDX gives the
    // actual allocated extent, including the replacement PCM data chunk.
    Bytes chunks=wav.slice(12,wav.size-12);
    Wave w{chunk(chunks,"fmt ",true),chunk(chunks,"data",true)};
    if (w.fmt.size<16 || !w.samples.size || w.channels()<1 || w.channels()>2 ||
        w.hz()<8000 || w.hz()>192000) return {};
    return w;
}
}
