// Included in Adapter.mm's namespace. Unity object references below are scoped to
// the current chart. All callbacks which touch this state run on the Unity/UI main thread.
using PairAction = void (*)(Object,Object,Method);
using FloatAction = void (*)(Object,float,Method);
using Spawn = Object (*)(Object,Object,Method);
using JudgeCall = void (*)(Object,bool,Method);
Action originalUpdate,originalRetry;
Action originalNoteSound;
FloatAction originalAddRatio;
PairAction originalSendSound;
Spawn originalSpawn,originalMakeKey;
JudgeCall originalJudge;
JudgeCall originalSetupNote;
struct PreviewNote {
    Object pooledNote;
    uint32_t positionHandle;
};
std::unordered_map<size_t,PreviewNote> previewNotes;

struct SoundEvent { Object sound; float time; };
struct DeferredKey { unsigned epoch; bool continuing; float remaining; };
std::unordered_map<Object,DeferredKey> pendingKeys;
std::vector<SoundEvent> soundLog;
std::vector<SoundEvent> backingLog;
unsigned audioEpoch=1;
bool rescheduling,transportSeek;
float remainingWait;
practice::Journal journal;
std::vector<practice::Note> nativeNotes,notesByTime;
std::unordered_map<uintptr_t,size_t> noteIndices;
std::unordered_set<uintptr_t> rebuildSkip;
bool chartReady,historyOK,dragging,beginRequested,finishRequested,cancelRequested;
bool previewing,blockPast,jumpRequested;
float originSec,lowestSec,positionSec,aimSec,durationSec,progressSec;
double previousTick;
Object judgingInfo;
unsigned transportID;
constexpr size_t managerPlane=0x38, managerResult=0x58, managerUI=0x40, planeParams=0x10;

template<class T> void writeField(Object object,size_t offset,T value) {
    memcpy(static_cast<char*>(object)+offset,&value,sizeof value);
}
Object currentPlane() { return field<Object>(manager,managerPlane); }
#include "HitEffects.inc"
float songClock() { return field<float>(field<Object>(currentPlane(),planeParams),0x10); }
practice::LoopRange region;
practice::RateObservation externalRate;
bool toolPaused,heldPreview,ratePending,recoverOnResume;
double rateAfter;
uint32_t practiceResultHandle;
Object practiceResult; // still rooted by game if GC handle allocation fails

Step originalEndStep,originalLinkEndStep;
Action originalResultInit,originalPlaneUpdate,originalClick;
thread_local Object settlingOwner;
using CountReset=void(*)(Object,int,Method);
CountReset originalCountReset;

void forgetPractice() {
    if (practiceResultHandle) dropObject(practiceResultHandle);
    practiceResultHandle=0;
    practiceResult=nullptr;
}
void markPractice() {
    if (!trainerEnabled) return;
    Object result=field<Object>(manager,managerResult);
    if (!result || result==practiceResult) return;
    forgetPractice();
    practiceResult=result;
    practiceResultHandle=retainObject(result,false);
}
void allMissForSettlement(Object result) {
    if (!result || result!=practiceResult) return;
    const int total=field<int>(result,0x1c);
    if (total<=0) return;
    if (field<int>(result,0x3c)==total && field<int>(result,0x20)==total &&
        field<int>(result,0x14)==0 && field<double>(result,0x28)==0) return;
    at<Action>(Deemo::resetResult)(result,nullptr);
    // Accumulate exactly what the game would have produced for a fully missed chart.
    for (int i=0;i<total;++i) originalAddRatio(result,0,nullptr);
}
void newResult(Object result,int count,Method method) {
    if (result==practiceResult) forgetPractice();
    originalCountReset(result,count,method);
}
bool settleStep(Object e,Method m,Step original) {
    // End can yield several times waiting for the native end animation.
    Object previous=settlingOwner;
    settlingOwner=field<Object>(e,Deemo::coroutineOwner);
    bool more=original(e,m);
    settlingOwner=previous;
    return more;
}
bool settle(Object e,Method m) {return settleStep(e,m,originalEndStep);}
bool settleLink(Object e,Method m) {return settleStep(e,m,originalLinkEndStep);}
void resultScreen(Object owner,Method m) {
    originalResultInit(owner,m);
    allMissForSettlement(field<Object>(owner,0x90));
    if (manager) endSong();
}
void setupNote(Object note,bool background,Method method) {
    if (!previewing) originalSetupNote(note,background,method);
}
void planeUpdate(Object plane,Method method) {
    if ((toolPaused || previewing) && plane==currentPlane()) return;
    originalPlaneUpdate(plane,method);
}
void clickNote(Object note,Method method) {
    if (!toolPaused && !previewing) originalClick(note,method);
}

void releasePreviewNote(const PreviewNote& v) {
    Object gameObject=field<Object>(v.pooledNote,0x40);
    if (gameObject) at<JudgeCall>(Deemo::setNoteObjectActive)(gameObject,false,nullptr);
    if (v.positionHandle) dropObject(v.positionHandle);
}
void discardPreview() {
    for (const auto& item:previewNotes) releasePreviewNote(item.second);
    previewNotes.clear();
}

// Run DEEMO's actual position coroutine independently of the gameplay Hit/Miss
// scheduler. MoveNext #1 enables its renderer. MoveNext #2 writes localPosition
// and opacity. Keep the iterator alive across frames, including backwards motion.
void renderPreview(float time) {
    Object plane=currentPlane();
    Object params=field<Object>(plane,planeParams);
    at<FloatAction>(Deemo::setSongTime)(params,time,nullptr);
    float horizon=at<float(*)(Object,Method)>(Deemo::activeTime)(params,nullptr);
    const auto range=practice::visibleNotes(notesByTime,time,std::max(time,horizon));
    for (auto it=previewNotes.begin();it!=previewNotes.end();) {
        if (it->first>=range.first && it->first<range.end) {++it;continue;}
        releasePreviewNote(it->second);
        it=previewNotes.erase(it);
    }
    const auto step=at<Step>(Deemo::positionStep);
    for (size_t index=range.first;index<range.end;++index) {
        const auto &note=notesByTime[index];
        if (!note.scored()) continue;
        auto found=previewNotes.find(index);
        Object iterator=nullptr;
        if (found==previewNotes.end()) {
            Object obj=originalSpawn(plane,reinterpret_cast<Object>(note.id),nullptr);
            if (!obj) continue;
            iterator=at<Object(*)(Object,Method)>(Deemo::positionIterator)(obj,nullptr);
            PreviewNote entry{obj,iterator?retainObject(iterator,false):0};
            if (!entry.positionHandle || !step(iterator,nullptr)) {releasePreviewNote(entry);continue;}
            previewNotes.emplace(index,entry);
        } else {
            iterator=heldObject(found->second.positionHandle);
        }
        if (iterator) {
            // During normal playback opacity ramps by .02 per animation tick.
            // A seek needs the opacity at its destination, even on its first tick.
            writeField<float>(iterator,0x2c,1.f);
            step(iterator,nullptr);
        }
    }
}
void abandonGesture() {
    jumpRequested=false;
    dragging=beginRequested=finishRequested=cancelRequested=previewing=false;
}
void resetTransport() {
    releaseCharming();
    pianoEffects.clear();
    discardPreview();
    region={}; externalRate={}; toolPaused=heldPreview=ratePending=recoverOnResume=false;
    ++transportID;++audioEpoch;
    abandonGesture();
    chartReady=false;historyOK=true;blockPast=false;
    journal={};nativeNotes.clear();notesByTime.clear();noteIndices.clear();soundLog.clear();backingLog.clear();rebuildSkip.clear();
    durationSec=progressSec=positionSec=aimSec=0;
    // Pending coroutines can survive a retry. Their generation invalidates them
    // until their next step; a newly allocated enumerator always replaces its entry.
    pendingKeys.clear();
}

bool loadChart() {
    Object plane=currentPlane(),result=field<Object>(manager,managerResult);
    Object chart=field<Object>(plane,0x58),list=field<Object>(chart,0x18);
    Object array=field<Object>(list,0x10);
    int count=field<int>(list,0x18);
    Object clip=at<Object(*)(Object,Method)>(Deemo::getClip)(source,nullptr);
    if (!clip || count<1 || count>200000 || !array || !result ||
        !field<Object>(manager,managerUI) || !field<Object>(plane,planeParams) ||
        field<uintptr_t>(array,0x18)<static_cast<unsigned>(count)) return false;
    float duration=at<float(*)(Object,Method)>(Deemo::clipLength)(clip,nullptr);
    if (!std::isfinite(duration) || duration<=0) return false;
    nativeNotes.clear();noteIndices.clear();
    nativeNotes.reserve(count);
    int scored=0;
    for (int i=0;i<count;++i) {
        Object info=field<Object>(array,0x20+i*sizeof(Object));
        if (!info) return false;
        float t=field<float>(info,0x38)+field<float>(info,0x3c);
        float x=field<float>(info,0x30);
        if (!std::isfinite(t) || !std::isfinite(x)) return false;
        auto id=reinterpret_cast<uintptr_t>(info);
        if (!noteIndices.emplace(id,i).second) return false;
        nativeNotes.push_back({id,t,x});
        scored+=nativeNotes.back().scored();
    }
    if (scored!=field<int>(result,0x1c) || field<int>(result,0x20)!=0) return false;
    notesByTime=practice::chronologicalNotes(nativeNotes);
    durationSec=duration;
    return true;
}

void judge(Object note,bool hit,Method method) {
    if (previewing || toolPaused) return;
    if (!chartReady) {originalJudge(note,hit,method);return;}
    Object previous=judgingInfo;
    judgingInfo=field<Object>(note,0x60);
    originalJudge(note,hit,method);
    judgingInfo=previous;
}
void addRatio(Object result,float ratio,Method method) {
    if (previewing || toolPaused) return;
    if (manager && chartReady && result==field<Object>(manager,managerResult)) {
        auto id=reinterpret_cast<uintptr_t>(judgingInfo);
        if (noteIndices.find(id)==noteIndices.end() || !journal.record(id,songClock(),ratio))
            historyOK=false; // Refuse a later seek instead of dropping a real native judgement.
    }
    originalAddRatio(result,ratio,method);
}
Object spawn(Object plane,Object info,Method method) {
    if (plane==currentPlane() && (blockPast || previewing)) {
        uintptr_t id=reinterpret_cast<uintptr_t>(info);
        if (rebuildSkip.count(id)) return nullptr;
        if (previewing) {
            auto it=noteIndices.find(id);
            if (it!=noteIndices.end() && nativeNotes[it->second].time<positionSec) return nullptr;
        }
    }
    return originalSpawn(plane,info,method);
}
void noteSound(Object note,Method method) {
    if (previewing || toolPaused) return;
    if (!chartReady) {originalNoteSound(note,method);return;}
    Object info=field<Object>(note,0x60);
    if (chartReady && field<float>(info,0x30)>2 && noteIndices.count(reinterpret_cast<uintptr_t>(info)))
        backingLog.push_back({info,songClock()});
    originalNoteSound(note,method);
}
void sendSound(Object owner,Object sound,Method method) {
    if (previewing || toolPaused) return;
    if (manager==owner && sound && chartReady && !rescheduling) soundLog.push_back({sound,songClock()});
    originalSendSound(owner,sound,method);
}
Object makeKey(Object player,Object sound,Method method) {
    Object enumerator=originalMakeKey(player,sound,method);
    if (manager && player==field<Object>(manager,0x20) && enumerator)
        pendingKeys[enumerator]={audioEpoch,rescheduling,remainingWait};
    return enumerator;
}
void stopKeyVoices() {
    ++audioEpoch;
    Object bank=field<Object>(field<Object>(manager,0x20),0x10);
    if (!bank) return;
    Object worker=field<Object>(bank,0x50),pool=field<Object>(bank,0x28);
    if (worker) at<Action>(Deemo::clearWorker)(worker,nullptr);
    uintptr_t count=field<uintptr_t>(pool,0x18);
    if (!pool || count>4096) return;
    for (uintptr_t i=0;i<count;i++) {
        Object voice=field<Object>(pool,0x20+i*sizeof(Object));
        if (!field<Object>(voice,Deemo::objectNative)) continue;
        originalStop(voice,nullptr);
        at<void(*)(Object,bool,Method)>(Deemo::enableBehaviour)(voice,false,nullptr);
    }
    writeField<int>(bank,0x34,0);
}
void recoverKeys(float target) {
    soundLog.erase(std::remove_if(soundLog.begin(),soundLog.end(),
                    [&](const SoundEvent& e){return e.time>target;}),soundLog.end());
    rescheduling=true;
    for (const auto& e:soundLog) {
        remainingWait=e.time+field<float>(e.sound,0x10)-target;
        if (remainingWait>0) originalSendSound(manager,e.sound,nullptr);
    }
    rescheduling=false;
}
void restoreScore() {
    Object result=field<Object>(manager,managerResult),ui=field<Object>(manager,managerUI);
    at<Action>(Deemo::resetResult)(result,nullptr);
    for (auto event:journal.decisions) originalAddRatio(result,event.ratio,nullptr);
    at<Action>(Deemo::resetUI)(ui,nullptr);
    int combo=field<int>(result,0x18),count=field<int>(result,0x20);
    // Restore the digits without synthesizing another perfect-hit animation.
    at<void(*)(Object,int,float,Method)>(Deemo::comboUI)(ui,combo,0.f,nullptr);
    at<void(*)(Object,bool,bool,Method)>(Deemo::comboStatus)(ui,field<int>(result,0x10)==count,combo==count,nullptr);
    int score=at<Integer>(Deemo::scoreValue)(result,nullptr);
    at<FloatAction>(Deemo::scoreUI)(ui,floorf(score*.01f),nullptr);
}
void rebuildPlane(float target) {
    Object plane=currentPlane();
    at<Action>(Deemo::clearPlane)(plane,nullptr);
    rebuildSkip.clear();
    rebuildSkip=journal.done;
    for (auto e:backingLog) rebuildSkip.insert(reinterpret_cast<uintptr_t>(e.sound));
    const size_t i=practice::resumeIndex(nativeNotes,target,rebuildSkip);
    writeField<int>(plane,0x60,(int)i);
    blockPast=true;
    at<FloatAction>(Deemo::updatePlaneTime)(plane,target,nullptr);
    // Keep the skip set in force for already-scored early hits not yet spawned.
}
void finishScrub() {
    float target=cancelRequested?originSec:positionSec;
    float branch=cancelRequested?originSec:std::min(lowestSec,target);
    journal.move(originSec,branch,notesByTime);
    journal.move(branch,target,notesByTime);
    backingLog.erase(std::remove_if(backingLog.begin(),backingLog.end(),
                        [&](const SoundEvent& e){return e.time>branch;}),backingLog.end());
    if (target>branch) {
        std::unordered_set<Object> consumed;
        for (auto e:backingLog) consumed.insert(e.sound);
        for (const auto& n:notesByTime) {
            if (n.time>=target) break;
            Object info=reinterpret_cast<Object>(n.id);
            if (n.position>2 && consumed.insert(info).second)
                backingLog.push_back({info,std::nextafter(std::max(n.time,branch),target)});
        }
    }
    restoreScore();
    if (toolPaused) {
        renderPreview(target);
        heldPreview=true;
    } else {
        discardPreview();
        previewing=false;
        rebuildPlane(target);
    }
    keyEpoch=originalTime(nullptr);
    soundLog.erase(std::remove_if(soundLog.begin(),soundLog.end(),
                  [&](const SoundEvent& e){return e.time>branch;}),soundLog.end());
    abandonGesture();
    progressSec=target;
    if (!paused && !toolPaused) {
        transportSeek=true;
        onPlay(manager,nullptr);
        transportSeek=false;
        recoverKeys(target);
    }
}
void replayHere() {
    transportSeek=true;
    onPlay(manager,nullptr);
    transportSeek=false;
}
void releaseHeldPreview() {
    if (!heldPreview) return;
    heldPreview=false;
    float time=songClock();
    discardPreview();
    rebuildPlane(time);
}
void toggleHold() {
    if (!trainerEnabled || !manager || paused || !chartReady || dragging || beginRequested) return;
    markPractice();
    if (toolPaused) {
        toolPaused=false;
        releaseHeldPreview();
        keyEpoch=originalTime(nullptr);
        replayHere();
        recoverKeys(songClock());
    } else {
        toolPaused=true;
        at<Action>(Deemo::pauseAudio)(source,nullptr);
        stopKeyVoices();
    }
}
void markRegion() {
    if (!trainerEnabled || !manager || !chartReady || paused || (!historyOK && !region.complete()) || dragging || beginRequested) return;
    markPractice();
    region.mark(std::clamp(songClock(),0.f,durationSec));
}
void loopToStart(float now) {
    clearHitEffects();
    stopKeyVoices();
    originSec=now;
    positionSec=lowestSec=region.first;
    cancelRequested=false;
    finishScrub();
}
void applyLiveRate();
void updateTransport(Object owner,Method method) {
    // While disabled, keep only the chart history needed to attach mid-song.
    // Native playback, input and scoring run without transport commands.
    if (!trainerEnabled) {originalUpdate(owner,method);return;}
    if (owner==manager && ratePending && CACurrentMediaTime()>=rateAfter && !paused && !dragging && !beginRequested) applyLiveRate();
    if (!manager || owner!=manager || !chartReady) {
        originalUpdate(owner,method);return;
    }
    if (beginRequested) {
        beginRequested=false;
        if (historyOK && !paused && field<int>(field<Object>(manager,managerResult),0x20)==(int)journal.decisions.size()) {
            lowestSec=originSec=positionSec=std::clamp(songClock(),0.f,durationSec);
            markPractice();
            dragging=previewing=true;
            clearHitEffects();
            at<Action>(Deemo::pauseAudio)(source,nullptr);
            stopKeyVoices();
            if (!heldPreview && (!jumpRequested || toolPaused || cancelRequested))
                at<Action>(Deemo::clearPlane)(currentPlane(),nullptr);
            heldPreview=false;
            if (jumpRequested && !cancelRequested) {
                positionSec=region.constrain(std::clamp(aimSec,0.f,durationSec));
                lowestSec=std::min(originSec,positionSec);
                finishScrub();
                return;
            }
            renderPreview(positionSec);
            previousTick=CACurrentMediaTime();
        } else {
            abandonGesture();
        }
    }
    if (dragging) {
        double now=CACurrentMediaTime();
        float start=region.complete()?region.first:0;
        float end=region.complete()?region.second:durationSec;
        float next=finishRequested ? positionSec :
            region.constrain(start+practice::follow(positionSec-start,aimSec-start,end-start,now-previousTick,scrubSensitivity));
        previousTick=now;
        if (!cancelRequested && fabsf(next-positionSec)>1.e-6f) {
            positionSec=next;
            lowestSec=std::min(lowestSec,next);
            renderPreview(next);
        }
        if (paused) cancelRequested=true;
        if (finishRequested || cancelRequested) finishScrub();
        return;
    }
    if (toolPaused) return;
    if (region.complete() && !paused && historyOK) {
        float now=songClock();
        if (now>=region.second) {
            loopToStart(now);
            return;
        }
    }
    originalUpdate(owner,method);
    if (owner==manager && region.complete() && historyOK && !paused && songClock()>=region.second)
        loopToStart(songClock());
    if (manager==owner && chartReady) progressSec=std::clamp(songClock(),0.f,durationSec);
}
void retrySong(Object owner,Method method) {
    Object result=field<Object>(owner,managerResult);
    if (manager==owner) endSong();
    originalRetry(owner,method);
    // The retry button uses the parameterless Reset on the same object.
    if (result==practiceResult) forgetPractice();
}
