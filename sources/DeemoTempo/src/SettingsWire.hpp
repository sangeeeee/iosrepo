#pragma once
#include <cstdint>

namespace settings {
enum Key { Enabled, Rate, Theme, Gain, Delay, Count };
// Delay is encoded as milliseconds + 200 so all wire values are unsigned.
constexpr int minimum[]={0,2,0,25,0}, maximum[]={1,40,2,250,400};
constexpr const char *requests[]={
    "com.linghe.deemotrainer.request.enabled","com.linghe.deemotrainer.request.rate",
    "com.linghe.deemotrainer.request.theme","com.linghe.deemotrainer.request.gain",
    "com.linghe.deemotrainer.request.delay"
};
constexpr char changed[]="com.linghe.deemotrainer.committed.v1";
constexpr char failed[]="com.linghe.deemotrainer.saveFailed.v1";
constexpr uint64_t marker=uint64_t{1}<<60;
struct Snapshot {
    int values[Count]={1,20,0,100,200};
    unsigned present=0;
    uint64_t pack() const {
        uint64_t word=marker|(uint64_t(present)<<45);
        for(int k=0;k<Count;++k) word|=uint64_t(values[k])<<(9*k);
        return word;
    }
    bool unpack(uint64_t word) {
        Snapshot next;
        next.present=(word>>45)&31;
        for(int k=0;k<Count;++k) {
            next.values[k]=(word>>(9*k))&511;
            if(next.values[k]<minimum[k] || next.values[k]>maximum[k]) return false;
        }
        if (next.pack()!=word) return false;
        *this=next;
        return true;
    }
    bool apply(Key k,uint64_t request) {
        if (!(request&marker) || (request&~(marker|1023ULL))) return false;
        int v=request&511;
        if (v<minimum[k] || v>maximum[k] || ((request&512) && (present&(1u<<k)))) return false;
        present|=1u<<k;
        values[k]=v;
        return true;
    }
};
inline uint64_t request(int value,bool migrate=false) {
    return marker|uint64_t(value)|(migrate?512:0);
}
}
