#import <AVFoundation/AVFoundation.h>
#include "SongBank.hpp"

// DecodeBank's size query and caller-owned destination are also used by the
// game's LoadAndDecodeBankFromMemory. Never re-register the decoded bank.
using DTDecodeBank=int(*)(const void*,uint32_t,int,void**,uint32_t*);
static NSURL *DTDecodeSong(NSData *bank,DTDecodeBank decode) {
    uint32_t bytes=0;
    void *out=nullptr;
    if (decode(bank.bytes,(uint32_t)bank.length,-1,&out,&bytes)!=1 || !bytes || bytes>256u*1024*1024) return nil;
    NSMutableData *decoded=[NSMutableData dataWithLength:bytes];
    out=decoded.mutableBytes;
    if (decode(bank.bytes,(uint32_t)bank.length,-1,&out,&bytes)!=1 || out!=decoded.mutableBytes || bytes>decoded.length) return nil;
    auto w=songbank::singleSong({(const uint8_t*)out,bytes});
    if (!w.samples.size || (w.fmt.u16(0)!=1 && w.fmt.u16(0)!=0xfffe) || w.fmt.u16(14)!=16 ||
        w.samples.size%(2*w.channels())) return nil;
    uint32_t dataLen=(uint32_t)w.samples.size;
    uint8_t header[44]={};
    memcpy(header,"RIFF",4);memcpy(header+8,"WAVEfmt ",8);memcpy(header+36,"data",4);
    auto u32=[&](size_t i,uint32_t v){memcpy(header+i,&v,4);};
    auto u16=[&](size_t i,uint16_t v){memcpy(header+i,&v,2);};
    u32(4,dataLen+36);u32(16,16);u16(20,1);u16(22,w.channels());u32(24,w.hz());
    u32(28,w.hz()*2*w.channels());u16(32,2*w.channels());u16(34,16);u32(40,dataLen);
    NSURL *url=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                URLByAppendingPathComponent:[NSString stringWithFormat:@"DT-%@.wav",NSUUID.UUID.UUIDString]];
    NSOutputStream *stream=[NSOutputStream outputStreamWithURL:url append:NO];
    [stream open];
    bool ok=[stream write:header maxLength:sizeof header]==sizeof header;
    size_t done=0;
    while (ok && done<w.samples.size) {
        NSInteger n=[stream write:w.samples.data+done maxLength:w.samples.size-done];
        if (n<=0) ok=false; else done+=(size_t)n;
    }
    [stream close];
    if (!ok) { [NSFileManager.defaultManager removeItemAtURL:url error:nil];return nil; }
    return url;
}
@interface DTPracticeAudio : NSObject
@property(nonatomic,strong) AVAudioFile *file;
@property(nonatomic,strong) AVAudioPlayerNode *node;
@property(nonatomic,strong) AVAudioEngine *engine;
@property(nonatomic,strong) AVAudioUnitTimePitch *stretch;
@property(nonatomic) AVAudioFramePosition startFrame;
- (BOOL)load:(NSURL *)url;
- (BOOL)startAt:(double)time rate:(float)rate volume:(float)volume;
- (double)position;
@end
@implementation DTPracticeAudio
- (BOOL)load:(NSURL *)url {
    self.file=[[AVAudioFile alloc] initForReading:url error:nil];
    if (!self.file || !self.file.length) return NO;
    @try {
        self.engine=[AVAudioEngine new];self.node=[AVAudioPlayerNode new];self.stretch=[AVAudioUnitTimePitch new];
        self.stretch.pitch=0;
        [self.engine attachNode:self.node];[self.engine attachNode:self.stretch];
        [self.engine connect:self.node to:self.stretch format:self.file.processingFormat];
        [self.engine connect:self.stretch to:self.engine.mainMixerNode format:self.file.processingFormat];
        return YES;
    } @catch(NSException *error) {
        NSLog(@"[DEEMO Trainer] Audio graph: %@",error.reason);return NO;
    }
}
- (BOOL)startAt:(double)time rate:(float)rate volume:(float)volume {
    if (!self.file || !std::isfinite(time)) return NO;
    @try {
        [self.node stop];
        self.stretch.rate=rate;self.node.volume=std::clamp(volume,0.f,1.f);
        self.startFrame=std::clamp<AVAudioFramePosition>(llround(time*self.file.processingFormat.sampleRate),0,self.file.length-1);
        if (!self.engine.running && ![self.engine startAndReturnError:nil]) return NO;
        [self.node scheduleSegment:self.file startingFrame:self.startFrame frameCount:(AVAudioFrameCount)(self.file.length-self.startFrame) atTime:nil completionHandler:nil];
        [self.node play];
        return YES;
    } @catch(NSException *error) {
        NSLog(@"[DEEMO Trainer] Audio route: %@",error.reason);return NO;
    }
}
- (double)position {
    AVAudioTime *render=self.node.lastRenderTime;
    AVAudioTime *t=render?[self.node playerTimeForNodeTime:render]:nil;
    double hz=self.file.processingFormat.sampleRate;
    return self.startFrame/hz+(t.sampleTimeValid?t.sampleTime/t.sampleRate:0.);
}
- (void)dealloc { [_node stop];[_engine stop]; }
@end
