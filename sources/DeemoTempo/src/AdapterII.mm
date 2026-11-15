#import <UIKit/UIKit.h>
#include "Settings.h"
#include "Transport.hpp"
#include "DeemoII419.hpp"
#include <atomic>
#include <cstring>
#include <unordered_map>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#import "TrainerAudioII.h"

namespace {
using Object=void*;
using Method=const void*;
using Action=void(*)(Object,Method);
using Static=void(*)(Method);
using Judge=void(*)(float,bool,int,Method);
using Sound=void(*)(Object,Object,float,Method);
using Hook=void(*)(void*,void*,void**);
namespace D=deemo2;
uintptr_t base;
template<class F> F fn(D::Entry entry) { return reinterpret_cast<F>(base+entry.offset); }
template<class T> T field(Object o,size_t offset) {
    T t{};if (o) memcpy(&t,static_cast<uint8_t*>(o)+offset,sizeof t);return t;
}
template<class T> void write(Object o,size_t offset,T value) {
    memcpy(static_cast<uint8_t*>(o)+offset,&value,sizeof value);
}
Object slot(uintptr_t offset) { return *reinterpret_cast<Object*>(base+offset); }
Object staticFields(uintptr_t typeInfo) {return field<Object>(slot(typeInfo),0xb8);}
Object listArray(Object list) {
    int n=field<int>(list,0x18);
    Object a=field<Object>(list,0x10);
    return n>=0 && n<=200000 && field<uintptr_t>(a,0x18)>=(unsigned)n?a:nullptr;
}
Object item(Object array,int i) {return field<Object>(array,0x20+size_t(i)*sizeof(Object));}
float clockTime() {return fn<float(*)(Method)>(D::songTime)(nullptr);}
void setTime(float t) {fn<void(*)(float,Method)>(D::setTime)(t,nullptr);}

NSString *const gameBundle=@"com.rayark.deemo2",*const gameVersion=@"4.1.9",*const gameBuild=@"97950010";
NSString *statusText=@"开曲前选择练习倍率";
bool ready,trainerEnabled,chartReady,paused,toolPaused,historyOK,dragging;
bool beginRequested,jumpRequested,finishRequested,cancelRequested,ratePending;
float positionSec,aimSec,progressSec,durationSec,scrubSensitivity=1;
std::atomic<float> selection{1};
std::atomic<int> offsetMs{0};
std::atomic<bool> playing{false};
unsigned transportID,audioGeneration;
double rateAfter,lastTick,nextBankCheck;
practice::LoopRange region;
Object manager,normalOwner,judgingNote;
Action originalInitPlane,originalRelease,originalPauseMusic,originalResumeMusic,originalSync,originalAlign;
bool (*originalFrame)(Object,Method);
void (*originalSpawn)(Object,Object,Method);
float (*originalJudge)(Object,bool,Method);
Action originalResultInit;
Static originalSettle;
Judge originalAdd;
Sound originalSound;
uint32_t (*retainObject)(Object,bool);
void (*dropObject)(uint32_t);
Object (*heldObject)(uint32_t);
Object (*newObject)(Object);
Object (*findField)(Object,const char*);
size_t (*fieldOffset)(Object);
void (*originalRetry)(Object,float,float,bool,Method);
uint32_t resultIDs,mutedID,practiceOwner;
bool practiceUsed,rebuilding,generatingResult,settled,decoding,decodeFailed,external,tail;
float actualRate=1,origin,lowest,bankDuration;
DTPracticeAudio *audio;
std::vector<practice::Note> notes;
practice::Journal history;
std::unordered_map<uintptr_t,bool> clicked;
std::unordered_map<int,Object> noteForID;
std::unordered_set<uintptr_t> known;
std::vector<float> earliestFuture; // prefix maxima allow binary search despite out-of-order notes
struct HoldNote { Object info; float from,to; };
std::vector<HoldNote> holds;
std::unordered_map<Object,uint32_t> voices;
struct KeyEvent {uint32_t handle; float issued,due;};
std::vector<KeyEvent> keyLog;
bool replayingKey;
float remainingWait;

bool practiceSession(){return manager && practiceUsed && !decodeFailed;}
void forgetPractice() {
    if(practiceOwner)dropObject(practiceOwner);
    practiceOwner=0;practiceUsed=settled=false;
}
void markPractice(){
    if (!manager || !trainerEnabled || practiceUsed) return;
    practiceUsed=true;practiceOwner=retainObject(manager,false);
}
Object plane(){return field<Object>(manager,0x38);}
Object resultFields(){return staticFields(0x6630fe0);}
Object chartParams(){return staticFields(0x6630fc8);}
float calibration(){return field<float>(chartParams(),0xdc)+offsetMs.load()*.001f;}
void updateDelay(int,int) {}
void nativeAction(int action,uint32_t id) {
    if(id) fn<void(*)(int,uint32_t)>(D::action)(action,id);
}
void muteNative() {
    uint32_t id=field<uint32_t>(manager,0x68);
    if (id && id!=mutedID) { nativeAction(1,id);mutedID=id; }
}
void releaseNative() {
    if (mutedID && mutedID==field<uint32_t>(manager,0x68)) nativeAction(2,mutedID);
    mutedID=0;
}
void nativeJump(float time) {
    if(!manager)return;
    // Seeking the exact EOF can drop the Wwise end callback.
    float end=audio.file?(float)(audio.file.length/audio.file.processingFormat.sampleRate):bankDuration;
    if(end>0){
        float last=end-.020f-field<float>(chartParams(),0xdc);
        time=std::min(time,std::max(0.f,last));
    }
    fn<void(*)(Object,float,Method)>(D::jump)(manager,time,nullptr);
}
void stopReplacement(){[audio.node stop];external=false;actualRate=1;}
void clearKeys(bool stop) {
    for (auto& e:voices) {
        Object key=heldObject(e.second);
        if (stop && field<Object>(key,0x10)) {
            fn<Action>(D::cancelKey)(key,nullptr);
            uint32_t id=field<uint32_t>(key,0x2c);
            if (id) {
                fn<void(*)(uint32_t,Method)>(D::cancelCallback)(id,nullptr);
                fn<void(*)(uint32_t,int,Method)>(D::stopID)(id,0,nullptr);
            }
            fn<Action>(D::resetKey)(key,nullptr);
        }
        dropObject(e.second);
    }
    voices.clear();
}
void sound(Object key,Object info,float volume,Method m) {
    if (!ready || !manager) {originalSound(key,info,volume,m);return;}
    if (toolPaused || dragging || rebuilding) return;
    if (!voices.count(key)) {
        auto handle=retainObject(key,false);
        if(handle) voices.emplace(key,handle);
    }
    if (info && !replayingKey && field<float>(info,0x10)>0) {
        uint32_t handle=retainObject(info,false);
        float now=clockTime();
        if(handle)keyLog.push_back({handle,now,now+field<float>(info,0x10)});
    }
    if (info && (replayingKey || (external && actualRate!=1))) {
        // The async voice retains this object. Other voices can share the
        // original chart entry, so adjust a distinct managed instance.
        Object copy=newObject(field<Object>(info,0));
        if (copy) {
            memcpy(static_cast<char*>(copy)+0x10,static_cast<char*>(info)+0x10,16);
            write(copy,0x10,(replayingKey?remainingWait:field<float>(info,0x10))/actualRate);
            write(copy,0x14,field<float>(info,0x14)/actualRate);
            info=copy;
        }
    }
    originalSound(key,info,volume,m);
}
void trimKeys(float branch){
    keyLog.erase(std::remove_if(keyLog.begin(),keyLog.end(),[&](const KeyEvent& e){
        if(e.issued<=branch)return false;
        dropObject(e.handle);return true;
    }),keyLog.end());
}
void recoverKeys(float time){
    replayingKey=true;
    for(const auto& event:keyLog){
        remainingWait=event.due-time;
        if(remainingWait>0 && event.issued<=time)
            fn<void(*)(Object,Object,Method)>(D::activeSound)(plane(),heldObject(event.handle),nullptr);
    }
    replayingKey=false;
}

bool loadNotes() {
    Object p=plane(),charts=field<Object>(p,0x50),array=listArray(charts);
    if (field<int>(charts,0x18)!=1 || !array || !resultIDs) return false;
    Object list=field<Object>(item(array,0),0x28),entries=listArray(list);
    const int count=field<int>(list,0x18);
    if (!entries || count<1) return false;
    std::vector<practice::Note> native;
    int playable=0;
    for(int i=0;i<count;++i) {
        Object entry=item(entries,i);
        float t=field<float>(entry,0x48)+field<float>(entry,0x4c),x=field<float>(entry,0x40);
        if (!entry || !std::isfinite(t) || !std::isfinite(x)) return false;
        native.push_back({reinterpret_cast<uintptr_t>(entry),t,x});
        playable+=native.back().scored();
    }
    if (!playable || playable!=field<int>(resultFields(),0x1c) ||
        playable!=field<int>(heldObject(resultIDs),0x18)) return false;
    known.clear();noteForID.clear();holds.clear();earliestFuture.clear();
    float maximum=-INFINITY;
    for(const auto& n:native) {
        maximum=std::max(maximum,n.time);earliestFuture.push_back(maximum);
        Object info=reinterpret_cast<Object>(n.id);
        if(n.scored()){
            float length=field<float>(info,0x54);
            if(length>0 && std::isfinite(length))holds.push_back({info,n.time,n.time+length});
            known.insert(n.id);
            auto k=noteForID.emplace(field<int>(info,0x30),info);
            if(!k.second) k.first->second=nullptr;
        }
    }
    notes=practice::chronologicalNotes(native);
    float finish=field<float>(p,0x44);
    durationSec=std::isfinite(finish)?std::max(maximum,finish):maximum;
    historyOK=field<int>(resultFields(),0x20)==0;
    return std::isfinite(durationSec) && durationSec>0;
}
songbank::Bytes currentBank() {
    Object name=fn<Object(*)(Method)>(D::getSong)(nullptr);
    if(!name || !fn<bool(*)(Object,Method)>(D::hasBank)(name,nullptr)) return {};
    Object dict=field<Object>(staticFields(0x662e150),0),info=nullptr;
    Method method=slot(0x6646348);
    if (!dict || !method || !fn<bool(*)(Object,Object,Object*,Method)>(D::tryBank)(dict,name,&info,method)) return {};
    int size=field<int>(info,0x28);
    auto data=field<const uint8_t*>(info,0x20);
    return size>0 && size<=64*1024*1024 && data ? songbank::Bytes{data,(size_t)size}:songbank::Bytes{};
}
void readAudio(bool decode) {
    auto bank=currentBank();
    if(!bank.size){
        if(decode)statusText=@"正在等待本曲音频包，当前使用 1×";
        return;
    }
    auto wave=songbank::singleSong(bank);
    if(!wave.fmt.data){
        if(decode){decodeFailed=true;statusText=@"本曲音轨格式暂不支持保调，使用 1×";}
        return;
    }
    bankDuration=wave.seconds();
    if(bankDuration>0) durationSec=std::max(durationSec,bankDuration);
    if(!decode || audio || decoding || decodeFailed)return;
    NSData *owned=[NSData dataWithBytes:bank.data length:bank.size];
    unsigned generation=audioGeneration;
    decoding=true;statusText=@"正在准备保调伴奏";
    static dispatch_queue_t queue=dispatch_queue_create("com.linghe.deemotrainer.decode",DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue,^{ @autoreleasepool {
        NSURL *url=DTDecodeSong(owned,fn<DTDecodeBank>(D::decode));
        dispatch_async(dispatch_get_main_queue(),^{
            if(generation==audioGeneration){
                decoding=false;
                DTPracticeAudio *player=[DTPracticeAudio new];
                if(url && [player load:url]) audio=player;
                else {decodeFailed=true;statusText=@"本曲保调伴奏不可用，使用 1×";}
            }
            if(url) [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        });
    }});
}
void playFrom(float t) {
    if (!manager || paused || toolPaused || dragging) return;
    const float rate=trainerEnabled?selection.load():1;
    bool use=rate!=1 && audio && !tail && field<uint32_t>(manager,0x68);
    if (use && [audio startAt:std::max(0.f,t+calibration()) rate:rate volume:fn<float(*)(Method)>(D::volume)(nullptr)]) {
        muteNative();actualRate=rate;external=true;statusText=@"本曲伴奏保调";return;
    }
    if (use) {decodeFailed=true;audio=nil;statusText=@"音频输出不可用，使用 1×";}
    stopReplacement();
    if(mutedID) {nativeJump(std::max(0.f,t));releaseNative();}
}
void syncAudio(Object o,Method m) {
    if(!ready || o!=manager || !external){originalSync(o,m);return;}
    if(audio.engine.running) setTime((float)[audio position]-calibration());
    else {
        stopReplacement();nativeJump(clockTime());releaseNative();
        statusText=@"音频输出中断，本曲已恢复原速";decodeFailed=true;audio=nil;
    }
}
void alignAudio(Object o,Method m) {
    if (!ready || o!=manager || !external) originalAlign(o,m);
}
void freezeAudio(){if(external)[audio.node pause];muteNative();clearKeys(true);}
void originalPause(Object o,Method m) {
    if(o==manager){
        if(dragging || beginRequested)cancelRequested=true;
        [audio.node pause];releaseNative();paused=true;
    }
    originalPauseMusic(o,m);
}
void originalResume(Object o,Method m) {
    originalResumeMusic(o,m);
    if(o==manager){paused=false;if(toolPaused)muteNative();else if(external)playFrom(clockTime());}
}
void initScore(Object ids,Method m) {
    if (ready) {
        if(resultIDs) dropObject(resultIDs);
        resultIDs=ids?retainObject(ids,false):0;
        if(!manager)forgetPractice();
        history={};clicked.clear();
    }
    originalResultInit(ids,m);
}
float judge(Object self,bool click,Method m) {
    if(ready && manager && (dragging || toolPaused || rebuilding)) return 0;
    Object previous=judgingNote;
    judgingNote=field<Object>(field<Object>(self,0x10),0x28);
    if(manager && practiceUsed && history.done.count(reinterpret_cast<uintptr_t>(judgingNote))){
        judgingNote=previous;return 0;
    }
    float r=originalJudge(self,click,m);judgingNote=previous;return r;
}
void addJudge(float ratio,bool click,int id,Method m) {
    if(ready && chartReady && manager && !generatingResult) {
        if(rebuilding || toolPaused || dragging) return;
        Object info=judgingNote;
        if(!info){auto f=noteForID.find(id);if(f!=noteForID.end())info=f->second;}
        uintptr_t key=reinterpret_cast<uintptr_t>(info);
        if (!known.count(key) || !history.record(key,clockTime(),ratio)) historyOK=false;
        else clicked[key]=click;
    }
    originalAdd(ratio,click,id,m);
}
template<class T> void setResultField(const char *name,T value) {
    Object f=findField(slot(0x6630fe0),name);
    if(f) write(resultFields(),fieldOffset(f),value);
}
void settle(Method m) {
    if (generatingResult) return;
    if (!ready || !practiceUsed || !resultIDs) {originalSettle(m);return;}
    // Normal settlement writes records and dispatches the network request.
    // Complete the game's local wait directly, with a zeroed result.
    if(rebuilding || (region.complete() && historyOK)){
        setResultField("_isSettlement",false);return;
    }
    if(!settled) {
        generatingResult=true;
        Object ids=heldObject(resultIDs);
        fn<Action>(D::resetResult)(ids,nullptr);
        const int count=field<int>(ids,0x18);
        write(resultFields(),0x20,count); // CurJudge
        setResultField("_missCount",count);
        setResultField("IsAllCharming",false);setResultField("IsFullCombo",false);setResultField("IsNewRecord",false);
        setResultField("IsClear",false);setResultField("_isSettlement",true);
        Object owner=practiceOwner?heldObject(practiceOwner):manager;
        // _LeaveRhythmAsync waits for the UI to finish this animation even
        // after _WaitForSettlementAsync has received SetRhythmResult.
        fn<Static>(D::showResultAnimation)(nullptr);
        if(owner)fn<Action>(D::resultDone)(owner,nullptr);
        generatingResult=false;settled=true;
        // Keep the BGM handoff running through the outro after the final note.
        historyOK=false;region={};
    }
}
void spawn(Object p,Object info,Method m) {
    if (ready && p==plane() && practiceUsed && history.done.count(reinterpret_cast<uintptr_t>(info))) return;
    originalSpawn(p,info,m);
}
void rebuild(float t) {
    Object p=plane();
    rebuilding=true;
    fn<Action>(D::disableNotes)(p,nullptr);
    int i=(int)(std::lower_bound(earliestFuture.begin(),earliestFuture.end(),t)-earliestFuture.begin());
    write(p,0x58,i);write(p,0x60,0);
    setTime(t);
    // Native UpdateNote skips heads earlier than t. Recreate the board of a
    // hold that crosses the seek, without synthesizing a second head judgement.
    for(auto h:holds)if(h.from<t && h.to>t)originalSpawn(p,h.info,nullptr);
    // Restore notes still in the late-hit window when rolling back a judgement.
    auto late=practice::visibleNotes(notes,t-.25f,t);
    for(size_t j=late.first;j<late.end;++j){
        const auto& n=notes[j];Object info=reinterpret_cast<Object>(n.id);
        if(n.scored() && n.time<t && !history.done.count(n.id) && n.time+field<float>(info,0x54)<=t)
            originalSpawn(p,info,nullptr);
    }
    fn<Action>(D::updatePlane)(p,nullptr);
    rebuilding=false;
}
void commit(float t,float branch) {
    trimKeys(branch);
    history.move(origin,branch,notes);
    for(auto it=clicked.begin();it!=clicked.end();){
        if (!history.done.count(it->first))it=clicked.erase(it);else ++it;
    }
    history.move(branch,t,notes);
    rebuilding=true;
    fn<Action>(D::resetResult)(heldObject(resultIDs),nullptr);
    for(auto d:history.decisions){
        Object info=reinterpret_cast<Object>(d.id);
        auto c=clicked.find(d.id);
        originalAdd(d.ratio,c!=clicked.end()?c->second:true,field<int>(info,0x30),nullptr);
    }
    rebuilding=false;
    tail=false;
    rebuild(t);progressSec=positionSec=t;
    nativeJump(t);
}
void abandon(){
    beginRequested=jumpRequested=finishRequested=cancelRequested=dragging=false;
}
void toggleHold() {
    if(!trainerEnabled || !chartReady || settled || paused || dragging || beginRequested)return;
    markPractice();toolPaused=!toolPaused;
    if(toolPaused)freezeAudio();else {nativeJump(progressSec);playFrom(progressSec);recoverKeys(progressSec);}
}
void markRegion(){
    if (!trainerEnabled || !chartReady || paused || dragging || beginRequested || !historyOK)return;
    markPractice();region.mark(std::clamp(progressSec,0.f,durationSec));
}
void changeEnabled(bool enabled) {
    if(trainerEnabled==enabled)return;
    trainerEnabled=enabled;++transportID;
    if (!manager)return;
    if(enabled){ratePending=true;return;}
    bool restore=dragging || toolPaused || external || mutedID;
    if(dragging) {rebuild(origin);progressSec=origin;}
    abandon();region={};toolPaused=false;ratePending=false;stopReplacement();
    if(restore){clearKeys(true);nativeJump(progressSec);releaseNative();if(!paused)recoverKeys(progressSec);}
    statusText=@"开曲前选择练习倍率";
}
void closeSession() {
    ++transportID;++audioGeneration;
    stopReplacement();releaseNative();audio=nil;decoding=decodeFailed=tail=false;
    clearKeys(false);trimKeys(-INFINITY);
    region={};abandon();toolPaused=paused=ratePending=chartReady=false;
    playing=false;manager=nullptr;history={};clicked.clear();known.clear();noteForID.clear();
    notes.clear();earliestFuture.clear();holds.clear();progressSec=durationSec=bankDuration=0;
    statusText=@"开曲前选择练习倍率";
}
void initPlane(Object owner,Method m) {
    if(ready){closeSession();forgetPractice();normalOwner=owner;}
    originalInitPlane(owner,m);
}
void release(Object owner,Method m) {
    if(ready && owner==normalOwner){closeSession();normalOwner=nullptr;}
    originalRelease(owner,m);
}
void retry(Object owner,float init,float start,bool fade,Method m){
    if(ready && owner==normalOwner){closeSession();forgetPractice();}
    originalRetry(owner,init,start,fade,m);
}
bool frame(Object e,Method m) {
    Object owner=field<Object>(e,0x20);
    if(!ready || !owner || owner!=normalOwner)return originalFrame(e,m);
    if(!manager && fn<bool(*)(Method)>(D::normalSong)(nullptr)) {
        manager=owner;
        chartReady=loadNotes();
        if(!chartReady){manager=nullptr;return originalFrame(e,m);}
        ++transportID;playing=true;tail=false;nextBankCheck=0;readAudio(false);
        if(trainerEnabled && selection.load()!=1)markPractice();
    }
    if(!manager)return originalFrame(e,m);
    paused=fn<bool(*)(Object,Method)>(D::isPaused)(owner,nullptr);
    float t=clockTime();
    if(practiceUsed && !settled && !paused && !toolPaused && !dragging && !beginRequested && !region.complete() &&
       field<int>(resultFields(),0x20)==field<int>(resultFields(),0x1c))settle(nullptr);
    if(trainerEnabled && !paused){
        auto now=CACurrentMediaTime();
        if(selection.load()!=1 && !audio && !decoding && !decodeFailed && now>=nextBankCheck){
            nextBankCheck=now+.35;readAudio(true);
        }
        if(external)muteNative();
        if(decoding && !audio && selection.load()!=1 && t>=0 && field<uint32_t>(manager,0x68) && !dragging && !beginRequested && !toolPaused){
            muteNative();return true;
        }
        if(mutedID && !external && !toolPaused && !dragging && !beginRequested &&
           (selection.load()==1 || decodeFailed)){nativeJump(t);releaseNative();}
        if(!toolPaused && !dragging && !beginRequested && now>=rateAfter &&
           (ratePending || (!external && audio && !tail && selection.load()!=1 && t>=0 && field<uint32_t>(manager,0x68)))){
            ratePending=false;
            if(selection.load()!=1)markPractice();
            float previousRate=actualRate;
            playFrom(t);
            if(previousRate!=actualRate){clearKeys(true);recoverKeys(t);}
        }
        if(beginRequested) {
            beginRequested=false;
            if(!historyOK || field<int>(resultFields(),0x20)!=(int)history.decisions.size()){abandon();}
            else{
                markPractice();origin=lowest=positionSec=std::clamp(t,0.f,durationSec);
                dragging=true;freezeAudio();lastTick=now;
            }
        }
        if(dragging){
            if(jumpRequested)positionSec=region.constrain(aimSec);
            else if(!finishRequested && !cancelRequested){
                float lo=region.complete()?region.first:0,hi=region.complete()?region.second:durationSec;
                float next=lo+practice::follow(positionSec-lo,aimSec-lo,hi-lo,now-lastTick,scrubSensitivity);
                if(next!=positionSec){positionSec=next;rebuild(next);}
            }
            lastTick=now;lowest=std::min(lowest,positionSec);
            if(jumpRequested || finishRequested || cancelRequested){
                float to=cancelRequested?origin:positionSec,branch=cancelRequested?origin:lowest;
                abandon();commit(to,branch);if(!toolPaused){playFrom(to);recoverKeys(to);}
            }
            return true;
        }
        if(toolPaused) {muteNative();return true;}
        if(region.complete() && historyOK && t>=region.second){
            origin=t;freezeAudio();commit(region.first,region.first);playFrom(region.first);recoverKeys(region.first);return true;
        }
        if(external && [audio position]>=audio.file.length/audio.file.processingFormat.sampleRate-.030){
            tail=true;stopReplacement();nativeJump(t);releaseNative();
        }
    }
    bool more=originalFrame(e,m);
    if(!more){closeSession();return false;}
    if(manager) progressSec=std::clamp(clockTime(),0.f,durationSec);
    return true;
}


#include "InstallII.inc"
} // namespace
#include "TrainerOverlay.inc"
