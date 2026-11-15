#import <UIKit/UIKit.h>
#import "Settings.h"
#include "Tempo.hpp"
#include "Transport.hpp"
#include <unordered_map>
#include "Deemo508.hpp"
#include <atomic>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <cstring>
#include <climits>

namespace {
using Object = void *;
using Method = const void *;
using Action = void (*)(Object,Method);
using Step = bool (*)(Object,Method);
using Clock = float (*)(Method);
using Integer = int (*)(Object,Method);
using Seek = void (*)(Object,int,Method);
using PlayDelay = void (*)(Object,float,Method);
using Key = void (*)(Object,int,int,float,Method);
using EffectHook = void (*)(void *,void *,void **);

uintptr_t base;
bool ready;
bool trainerEnabled=false; // The first committed settings snapshot supplies the default (on).
NSString *statusText;
std::atomic<float> selection{1.0f};
std::atomic<int> offsetMs{0};
std::atomic<bool> playing{false};
float scrubSensitivity=1;
Tempo tempo;
Object manager, source;
uint32_t sourceHandle;
float normalPitch=1, frequency=0, delaySeconds=0;
double keyEpoch=0;
bool paused;
double pauseAt;
PitchSession pitchSession;
PitchBackend backend;
uint32_t (*retainObject)(Object,bool);
Object (*heldObject)(uint32_t);
void (*dropObject)(uint32_t);
Step originalFrame,originalKeyStep;
Action originalPlay,originalStop,originalLeave,originalPause;
Object (*originalEnd)(Object,Method);
Clock originalDelta,originalTime;
Integer originalSamples;
Seek originalSeek;
PlayDelay originalDelay;
PlayDelay originalSetPitch;
Action originalPauseAudio;
Key originalKey;
static thread_local bool inFrame,inKeys;
static thread_local Object startingSource;

template<class T> T at(Deemo::Entry e) { return reinterpret_cast<T>(base+e.offset); }
template<class T> T field(Object object,size_t offset) {
    T value{};
    if (object) memcpy(&value,static_cast<char *>(object)+offset,sizeof value);
    return value;
}
void onPlay(Object owner,Method method);
void endSong();
#include "TransportAdapter.inc"
void setPitch(float value) { originalSetPitch(source,value,nullptr); }
void observePitch(Object object,float value,Method method) {
    if (ready && trainerEnabled && manager && object==source && std::isfinite(value) && value!=tempo.rate)
        markPractice();
    originalSetPitch(object,value,method);
}
void observeAudioPause(Object object,Method method) {
    if (ready && trainerEnabled && manager && object==source && !paused) markPractice();
    originalPauseAudio(object,method);
}
void releaseAudio() {
    if (!sourceHandle) return;
    Object retained=heldObject(sourceHandle);
    if (retained && field<Object>(retained,Deemo::objectNative)) {
        source=retained;
        setPitch(normalPitch);
    }
    pitchSession.stop(backend);
    dropObject(sourceHandle);
    sourceHandle=0;
    frequency=0;
}
void endSong() {
    resetTransport();
    releaseAudio();
    source=nullptr; manager=nullptr; tempo={1};
    playing.store(false); paused=false;
}
void useNormalSpeed(NSString *reason) {
    releaseAudio(); tempo={1};
    statusText=[NSString stringWithFormat:@"本曲使用 1× · %@",reason];
    NSLog(@"[DeemoTempo] %@",statusText);
}
void prepareAudio(Object target) {
    if (tempo.rate==1) return;
    auto native=field<Object>(target,Deemo::objectNative);
    auto audio=at<Object(*)()>(Deemo::audioManager)();
    auto system=field<Object>(audio,Deemo::systemSlot);
    if (!native || !system) { useNormalSpeed(@"音源未就绪");return; }
    auto clip=at<Object(*)(Object,Method)>(Deemo::getClip)(target,nullptr);
    if (!clip) {useNormalSpeed(@"尚无歌曲");return;}
    frequency=at<Integer>(Deemo::clipHz)(clip,nullptr);
    int outputHz=0;
    auto format=at<int(*)(Object,int*,void*,void*,void*,void*,void*)>(Deemo::softwareFormat);
    if (!(frequency>0) || format(system,&outputHz,nullptr,nullptr,nullptr,nullptr,nullptr) || outputHz<8000) {
        useNormalSpeed(@"音频格式不可用");return;
    }
    at<void(*)(Object)>(Deemo::ensureSourceGroups)(native);
    auto bus=field<Object>(native,Deemo::sourceDryBus);
    normalPitch=field<float>(native,Deemo::sourcePitch);
    if (!std::isfinite(normalPitch) || std::fabs(normalPitch-1)>.001f) {
        useNormalSpeed(@"歌曲音源已有调音");return;
    }
    int rc=pitchSession.start(backend,system,bus,Deemo::pitchShifterType,tempo);
    if (rc) {useNormalSpeed([NSString stringWithFormat:@"音频效果 %d",rc]);return;}
    sourceHandle=retainObject(target,false);
    if (!sourceHandle) {
        pitchSession.stop(backend);useNormalSpeed(@"音源绑定失败");return;
    }
    // Real-time FFT latency estimate (window minus hop), plus the user's
    // measured correction for this output route. Unity keeps its own calibration.
    delaySeconds=pitchSession.latencySeconds(outputHz)+offsetMs.load()*.001f;
    setPitch(tempo.rate);
    statusText=[NSString stringWithFormat:@"本曲 %.2f× · BGM 保调",tempo.rate];
}
void onStop(Object object,Method method) {
    originalStop(object,method);
    // PlayMusic stops before seeking and replaying. Re-create the effect after
    // Stop so a resume never emits the previous section's FFT history.
    if (ready && object==startingSource && object==source && tempo.rate!=1) {
        releaseAudio();prepareAudio(object);
    }
}
void onPlay(Object owner,Method method) {
    if (!ready) {originalPlay(owner,method);return;}
    Object target=field<Object>(owner,Deemo::managerSource);
    if (!target) {endSong();originalPlay(owner,method);return;}
    if (owner!=manager || target!=source) {
        endSong(); manager=owner;source=target;
        chartReady=loadChart();
        tempo.rate=trainerEnabled?selection.load():1.f;playing.store(true);
        Object native=field<Object>(target,Deemo::objectNative);
        if (trainerEnabled && (tempo.rate!=1.f || (native && field<float>(native,Deemo::sourcePitch)!=1.f))) markPractice();
        keyEpoch=originalTime(nullptr);
        statusText=[NSString stringWithFormat:@"本曲 %.2f×",tempo.rate];
    } else if (paused) {
        keyEpoch+=originalTime(nullptr)-pauseAt;
        paused=false;
        if (ratePending) {
            stopKeyVoices();
            releaseAudio();
            tempo.rate=trainerEnabled?selection.load():1.f;
            ratePending=false;
            recoverOnResume=true;
        }
        if (recoverOnResume) keyEpoch=originalTime(nullptr);
    }
    Object previous=startingSource;startingSource=target;
    originalPlay(owner,method);
    startingSource=previous;
    if (recoverOnResume && !paused && !toolPaused) {
        recoverOnResume=false;
        recoverKeys(songClock());
    }
    if (toolPaused) at<Action>(Deemo::pauseAudio)(source,nullptr);
}
void applyLiveRate() {
    ratePending=false;
    float rate=selection.load();
    if (rate==tempo.rate || !manager) return;
    markPractice();
    // Discard scheduled key waits in the previous timebase before reanchoring.
    stopKeyVoices();
    releaseAudio();
    tempo.rate=rate;
    keyEpoch=originalTime(nullptr);
    if (!toolPaused) {
        replayHere();
        recoverKeys(songClock());
    }
    if (rate==tempo.rate) statusText=[NSString stringWithFormat:@"练习 · %.2f×",tempo.rate];
}
void changeEnabled(bool enabled) {
    if (trainerEnabled==enabled) return;
    trainerEnabled=enabled;
    ++transportID; // Invalidate pending popover edits and touches from the old state.
    if (!manager) return;
    externalRate={};
    if (enabled) {
        ratePending=tempo.rate!=selection.load();
        if (ratePending) markPractice();
        return;
    }
    region={};
    ratePending=false;
    bool restartAudio=tempo.rate!=1 || toolPaused || dragging;
    if (restartAudio) {
        stopKeyVoices();
        releaseAudio();
        tempo.rate=1.f;
        keyEpoch=originalTime(nullptr);
    }
    if (dragging) {
        // Restore the last committed position without an intermediate audio restart.
        toolPaused=true;
        cancelRequested=true;
        finishScrub();
    }
    abandonGesture();
    toolPaused=false;
    releaseHeldPreview();
    if (restartAudio && paused) recoverOnResume=true;
    if (restartAudio && !paused) {
        replayHere();
        recoverKeys(songClock());
    }
}
bool onFrame(Object enumerator,Method method) {
    if (ready && trainerEnabled && manager && !paused && !toolPaused && !previewing &&
        manager==field<Object>(enumerator,Deemo::coroutineOwner) &&
        practiceResult!=field<Object>(manager,managerResult) &&
        externalRate.changed(originalDelta(nullptr),at<Clock>(Deemo::unscaledDelta)(nullptr))) markPractice();
    bool prior=inFrame;inFrame=ready && trainerEnabled;
    bool more=originalFrame(enumerator,method);
    inFrame=prior;
    if (ready && !more && manager && manager==field<Object>(enumerator,Deemo::coroutineOwner)) {
        if (region.complete() && historyOK && !paused && !field<bool>(manager,0x60)) {
            loopToStart(std::max(songClock(),region.second));
            writeField<int>(enumerator,0x10,1);
            return true;
        }
        endSong();
    }
    return more;
}
void seek(Object obj,int frame,Method method) {
    // In 5.0.8 the native song seeks only in PlayMusic and after exiting for retry.
    if (ready && trainerEnabled && manager && obj==source && obj!=startingSource) markPractice();
    if ((sourceHandle || transportSeek) && obj==startingSource) {
        Object clip=at<Object(*)(Object,Method)>(Deemo::getClip)(obj,nullptr);
        int length=clip?at<Integer>(Deemo::clipSamples)(clip,nullptr):0;
        if (length>0) frame=(int)fmax(0,fmin(length-1.0,frame+(sourceHandle?tempo.audibleSampleDelay(delaySeconds,frequency):0)));
    }
    originalSeek(obj,frame,method);
}
float chartDelta(Method method) {
    float delta=originalDelta(method);
    return inFrame ? tempo.chartDelta(delta) : delta;
}
void delayed(Object obj,float delay,Method method) {
    if (sourceHandle && obj==startingSource) delay=fmaxf(0,tempo.wallDuration(delay)-delaySeconds);
    originalDelay(obj,delay,method);
}
int samples(Object obj,Method method) {
    int count=originalSamples(obj,method);
    if (!inFrame || obj!=source || !sourceHandle) return count;
    double audible=count-tempo.audibleSampleDelay(delaySeconds,frequency);
    return static_cast<int>(fmax(0,fmin(INT_MAX,audible)));
}
bool onKeyStep(Object enumerator,Method method) {
    auto pending=pendingKeys.find(enumerator);
    if (pending!=pendingKeys.end()) {
        if (pending->second.epoch!=audioEpoch) {pendingKeys.erase(pending);return false;}
        if (toolPaused) return true;
        if (pending->second.continuing) {
            float now=originalTime(nullptr);
            float deadline=(tempo.rate==1?now:(now-keyEpoch)*tempo.rate)+pending->second.remaining;
            writeField<int>(enumerator,0x10,1);
            writeField<float>(enumerator,0x30,deadline);
            pending->second.continuing=false;
        }
    }
    bool prior=inKeys;inKeys=ready && manager && tempo.rate!=1;
    bool more=originalKeyStep(enumerator,method);inKeys=prior;if (!more) pendingKeys.erase(enumerator);return more;
}
float keyTime(Method method) {
    float time=originalTime(method);
    if (!inKeys) return time;
    return static_cast<float>(((paused?pauseAt:time)-keyEpoch)*tempo.rate);
}
void keyPlay(Object bank,int pitch,int velocity,float duration,Method method) {
    originalKey(bank,pitch,velocity,inKeys?tempo.wallDuration(duration):duration,method);
}
void onPause(Object owner,Method method) {
    if (ready && owner==manager && !paused) {
        if (toolPaused) recoverOnResume=true;
        toolPaused=false;
        releaseHeldPreview();
        externalRate={};
        paused=true;
        pauseAt=originalTime(nullptr);
    }
    originalPause(owner,method);
}
void leave(Object owner,Method method) {
    // This build calls OnLeaveGamePlay without reloading x0 after get_finished().
    // Its body does not use this. The method identity itself signals scene exit.
    if (settlingOwner) allMissForSettlement(field<Object>(settlingOwner,managerResult));
    if (ready && playing.load()) endSong();
    originalLeave(owner,method);
}
Object end(Object owner,Method method) {
    if (ready && owner==manager) endSong();
    return originalEnd(owner,method);
}
bool matches(const mach_header_64 *h) {
    if (h->magic!=MH_MAGIC_64 || h->cputype!=CPU_TYPE_ARM64) return false;
    const char *p=reinterpret_cast<const char *>(h+1);
    for (unsigned i=0;i<h->ncmds;i++) {
        auto cmd=reinterpret_cast<const load_command *>(p);
        if (cmd->cmd==LC_UUID) return !memcmp(reinterpret_cast<const uuid_command *>(p)->uuid,Deemo::uuid,16);
        p+=cmd->cmdsize;
    }
    return false;
}
template<class F> bool install(EffectHook hook,Deemo::Entry e,F replacement,F &original) {
    hook(at<void *>(e),reinterpret_cast<void *>(replacement),reinterpret_cast<void **>(&original));
    return original!=nullptr;
}
bool installAll(const mach_header_64 *header,const char *path) {
    if (!matches(header)) {statusText=@"Unity 构建不匹配";return false;}
    base=reinterpret_cast<uintptr_t>(header);
    for(auto e:Deemo::entries) if (*at<const uint32_t *>(e)!=e.word) {statusText=@"版本校验失败";return false;}
    void *runtime=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
    if (!runtime) {statusText=@"Unity 运行库不可用";return false;}
    retainObject=reinterpret_cast<decltype(retainObject)>(dlsym(runtime,"il2cpp_gchandle_new"));
    heldObject=reinterpret_cast<decltype(heldObject)>(dlsym(runtime,"il2cpp_gchandle_get_target"));
    dropObject=reinterpret_cast<decltype(dropObject)>(dlsym(runtime,"il2cpp_gchandle_free"));
    EffectHook hook=reinterpret_cast<EffectHook>(dlsym(RTLD_DEFAULT,"MSHookFunction"));
    if (!hook) {
        void *compat=dlopen("/var/jb/usr/lib/libsubstrate.dylib",RTLD_LAZY);
        if (compat) hook=reinterpret_cast<EffectHook>(dlsym(compat,"MSHookFunction"));
    }
    if (!hook || !retainObject || !heldObject || !dropObject) {statusText=@"运行接口不可用";return false;}
    backend={at<decltype(backend.create)>(Deemo::createDSPByType),at<decltype(backend.parameter)>(Deemo::setDSPParameter),
             at<decltype(backend.attach)>(Deemo::addDSP),at<decltype(backend.remove)>(Deemo::removeDSP),at<decltype(backend.release)>(Deemo::releaseDSP)};
    ready=install(hook,Deemo::getDelta,chartDelta,originalDelta)
       && install(hook,Deemo::getTime,keyTime,originalTime)
       && install(hook,Deemo::playDelayed,delayed,originalDelay)
       && install(hook,Deemo::setSamples,seek,originalSeek)
       && install(hook,Deemo::getSamples,samples,originalSamples)
       && install(hook,Deemo::bankPlay,keyPlay,originalKey)
       && install(hook,Deemo::noteStep,onKeyStep,originalKeyStep)
       && install(hook,Deemo::pause,onPause,originalPause)
       && install(hook,Deemo::leave,leave,originalLeave)
       && install(hook,Deemo::end,end,originalEnd)
       && install(hook,Deemo::mainStep,onFrame,originalFrame)
       && install(hook,Deemo::stopSource,onStop,originalStop)
       && install(hook,Deemo::setPitch,observePitch,originalSetPitch)
       && install(hook,Deemo::pauseAudio,observeAudioPause,originalPauseAudio)
       && install(hook,Deemo::playMusic,onPlay,originalPlay)
       && install(hook,Deemo::resetCount,newResult,originalCountReset)
       && install(hook,Deemo::endStep,settle,originalEndStep)
       && install(hook,Deemo::linkEndStep,settleLink,originalLinkEndStep)
       && install(hook,Deemo::resultInit,resultScreen,originalResultInit)
       && install(hook,Deemo::managerUpdate,updateTransport,originalUpdate)
       && install(hook,Deemo::charmingStep,observeCharming,originalCharmingStep)
       && install(hook,Deemo::pianoEffect,makePianoEffect,originalPianoEffect)
       && install(hook,Deemo::pianoEffectStep,stepPianoEffect,originalPianoStep)
       && install(hook,Deemo::stepPlane,planeUpdate,originalPlaneUpdate)
       && install(hook,Deemo::judgeNote,judge,originalJudge)
       && install(hook,Deemo::clickNote,clickNote,originalClick)
       && install(hook,Deemo::addRatio,addRatio,originalAddRatio)
       && install(hook,Deemo::activeNote,spawn,originalSpawn)
       && install(hook,Deemo::setupNote,setupNote,originalSetupNote)
       && install(hook,Deemo::retry,retrySong,originalRetry)
       && install(hook,Deemo::noteSound,noteSound,originalNoteSound)
       && install(hook,Deemo::keyEnumerator,makeKey,originalMakeKey)
       && install(hook,Deemo::sendSound,sendSound,originalSendSound);
    statusText=ready?@"开曲前选择练习倍率":@"适配未就绪";
    return ready;
}
bool practiceSession() { return manager && practiceResult && practiceResult==field<Object>(manager,managerResult); }
void updateDelay(int before,int after) {
    if (sourceHandle && before!=after) delaySeconds+=(after-before)*.001f;
}
NSString *const gameBundle=@"com.rayark.pluto", *const gameVersion=@"5.0.8", *const gameBuild=@"1001405";
} // namespace
#include "TrainerOverlay.inc"
