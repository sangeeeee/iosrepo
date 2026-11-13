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
bool trainerEnabled=true;
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
} // namespace

@interface DTRatePanel : UIViewController
@property(nonatomic,strong) UILabel *readout;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic) BOOL changed;
@property(nonatomic) unsigned openedSession;
@end
@implementation DTRatePanel
- (void)commitRate {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(commitRate) object:nil];
    if (!self.changed || !trainerEnabled || self.openedSession!=transportID) return;
    self.changed=NO;
    float value=steppedTempo(self.slider.value);
    if (value==selection.load()) return;
    if (manager) {
        markPractice();
        ratePending=true;
        self.statusLabel.text=@"本局练习 · 结算 0%";
    }
    selection.store(value);
    DTSet(DTRate,@(tempoTick(value)));
}
- (void)applyRate:(UISlider *)slider {
    slider.value=steppedTempo(slider.value);
    self.changed=YES;
    self.readout.text=[NSString stringWithFormat:@"练习倍率   %.2f×",slider.value];
    slider.accessibilityValue=[NSString stringWithFormat:@"%.2f×",slider.value];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(commitRate) object:nil];
    [self performSelector:@selector(commitRate) withObject:nil afterDelay:.22 inModes:@[NSRunLoopCommonModes]];
}
- (void)viewWillDisappear:(BOOL)animated {
    [self commitRate];
    [super viewWillDisappear:animated];
}
- (void)reset {
    [self.slider setValue:1 animated:YES];
    [self applyRate:self.slider];
    [self commitRate];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)editDelay {
    UIAlertController *edit=[UIAlertController alertControllerWithTitle:@"声音延迟微调（毫秒）" message:@"正值将判定线向后移。对当前设备保存，默认 0。" preferredStyle:UIAlertControllerStyleAlert];
    [edit addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=[NSString stringWithFormat:@"%d",offsetMs.load()];f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;}];
    [edit addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [edit addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSScanner *scan=[NSScanner scannerWithString:edit.textFields.firstObject.text?:@""];
        NSInteger ms=0;if ([scan scanInteger:&ms] && scan.isAtEnd && ms>=-200 && ms<=200) {
            offsetMs.store((int)ms);[NSUserDefaults.standardUserDefaults setInteger:ms forKey:@"DTPracticeOffset"];
        }
    }]];
    [self presentViewController:edit animated:YES completion:nil];
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    UIStackView *stack=[UIStackView new];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.spacing=8;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14]
    ]];
    self.readout=[UILabel new];
    self.readout.font=[UIFont monospacedDigitSystemFontOfSize:19 weight:UIFontWeightSemibold];
    self.readout.text=[NSString stringWithFormat:@"练习倍率   %.2f×",selection.load()];
    [stack addArrangedSubview:self.readout];
    UILabel *status=[UILabel new];
    status.font=[UIFont systemFontOfSize:13];
    status.textColor=UIColor.secondaryLabelColor;
    self.statusLabel=status;
    status.text=manager && practiceResult && practiceResult==field<Object>(manager,managerResult)?@"本局练习 · 结算 0%":statusText;
    [stack addArrangedSubview:status];
    if (ready) {
        self.slider=[UISlider new];
        self.slider.minimumValue=.1f;
        self.slider.maximumValue=2.f;
        self.slider.value=selection.load();
        self.slider.continuous=YES;
        self.slider.accessibilityLabel=@"练习倍率";
        self.slider.accessibilityValue=[NSString stringWithFormat:@"%.2f×",self.slider.value];
        [self.slider addTarget:self action:@selector(applyRate:) forControlEvents:UIControlEventValueChanged];
        [self.slider addTarget:self action:@selector(commitRate) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
        [stack addArrangedSubview:self.slider];
        UIStackView *limits=[UIStackView new];
        limits.distribution=UIStackViewDistributionEqualSpacing;
        for (NSString *value in @[@"0.10×",@"2.00×"]) {
            UILabel *label=[UILabel new]; label.text=value; label.font=[UIFont systemFontOfSize:13];
            [limits addArrangedSubview:label];
        }
        [stack addArrangedSubview:limits];
    }
    UIStackView *buttons=[UIStackView new];
    buttons.distribution=UIStackViewDistributionEqualSpacing;
    if (ready) {
        [buttons addArrangedSubview:[self button:@"恢复 1×" action:@selector(reset)]];
        [buttons addArrangedSubview:[self button:@"延迟微调" action:@selector(editDelay)]];
    }
    [buttons addArrangedSubview:[self button:@"完成" action:@selector(close)]];
    [stack addArrangedSubview:buttons];
}
@end

#include "ToolbarSettings.inc"
#include "TrackView.inc"

@interface DTControlsRoot : UIViewController
@property(nonatomic,weak) UIWindow *gameWindow;
@end
@implementation DTControlsRoot
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.gameWindow.rootViewController.supportedInterfaceOrientations ?: UIInterfaceOrientationMaskLandscape;
}
- (BOOL)prefersStatusBarHidden { return self.gameWindow.rootViewController.prefersStatusBarHidden; }
@end

@interface DTControlsWindow : UIWindow
@property(nonatomic,weak) UIView *toolbar;
@end
@implementation DTControlsWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.rootViewController.presentedViewController) {
        UIView *bar=self.toolbar;
        if (!bar || bar.hidden || ![bar pointInside:[bar convertPoint:point fromView:self] withEvent:event]) return nil;
    }
    return [super hitTest:point withEvent:event];
}
@end

@interface DTMenu : NSObject
@property(nonatomic,strong) DTSongTrack *track;
@property(nonatomic,strong) UIButton *holdButton,*regionButton,*settingsButton;
@property(nonatomic,strong) UIView *bar;
@property(nonatomic,strong) DTControlsWindow *controlsWindow;
@property(nonatomic,weak) UIWindow *gameWindow;
@property(nonatomic,strong) CADisplayLink *display;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL attempted;
@end
@implementation DTMenu
- (void)applyTheme {
    const DTPalette &p=palettes[paletteIndex];
    self.bar.backgroundColor=DTColor(p.surface);
    self.bar.layer.borderColor=[DTColor(p.rail) colorWithAlphaComponent:.65].CGColor;
    for (UIButton *b in @[self.button,self.holdButton,self.regionButton,self.settingsButton]) {
        b.backgroundColor=DTColor(p.button);
        b.tintColor=DTColor(p.text);
        [b setTitleColor:b.tintColor forState:UIControlStateNormal];
    }
    self.track.timeLabel.textColor=DTColor(p.text);
    [self.track setNeedsDisplay];
}
- (void)refreshTrack:(CADisplayLink *)sender {
    if (!trainerEnabled) return;
    UIWindow *window=self.track.window;
    if (!window) return;
    BOOL inSong=playing.load();
    BOOL visible=inSong && chartReady && !paused;
    self.track.hidden=!visible;
    self.holdButton.hidden=!visible;
    self.regionButton.hidden=!visible;
    self.track.userInteractionEnabled=historyOK;
    self.regionButton.enabled=(historyOK || region.complete()) && !dragging;
    self.holdButton.enabled=!dragging;
    UIEdgeInsets insets=window.safeAreaInsets;
    CGFloat available=window.bounds.size.width-insets.left-insets.right;
    CGFloat y=insets.top+2;
    self.button.hidden=NO;
    [self.button setTitle:ready?[NSString stringWithFormat:@"♫ %.2f×",selection.load()]:@"♫ 状态" forState:UIControlStateNormal];
    if (!visible) {
        self.bar.frame=CGRectMake(insets.left+8,y,148,52);
        self.button.frame=CGRectMake(4,4,86,44);
        self.settingsButton.frame=CGRectMake(100,4,44,44);
        return;
    }
    CGFloat gap=available>=550?10:4;
    CGFloat rateWidth=available>=550?80:69, actionWidth=44;
    CGFloat total=MIN(860,available-8);
    CGFloat x=5;
    CGFloat rail=total-2*x-rateWidth-3*actionWidth-4*gap;
    self.bar.frame=CGRectMake(insets.left+(available-total)/2,y,total,56);
    self.button.frame=CGRectMake(x,4,rateWidth,48);
    x+=rateWidth+gap;
    self.track.frame=CGRectMake(x,4,rail,48);
    x+=rail+gap;
    self.holdButton.frame=CGRectMake(x,4,actionWidth,48);
    x+=actionWidth+gap;
    self.regionButton.frame=CGRectMake(x,4,actionWidth,48);
    self.settingsButton.frame=CGRectMake(x+actionWidth+gap,4,actionWidth,48);
    [self.holdButton setTitle:toolPaused?@"▶":@"Ⅱ" forState:UIControlStateNormal];
    self.holdButton.accessibilityLabel=toolPaused?@"继续练习":@"暂停练习";
    [self.regionButton setTitle:region.complete()?@"×":region.first<0?@"1":@"2" forState:UIControlStateNormal];
    self.regionButton.accessibilityLabel=region.complete()?@"取消区间":region.first<0?@"标记起点":@"标记终点";
    [self.track refresh];
}
- (void)hold {toggleHold();[self refreshTrack:nil];}
- (void)mark {markRegion();[self refreshTrack:nil];}
- (UIButton *)actionButton:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.layer.cornerRadius=10;
    button.titleLabel.font=[UIFont boldSystemFontOfSize:16];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.hidden=YES;
    return button;
}
- (void)resign:(NSNotification *)note {
    if (dragging||beginRequested) cancelRequested=true;
}
- (void)reloadSettings {
    DTConfig c=DTReadConfig();
    float previous=selection.exchange(c.rate);
    BOOL rateChanged=previous!=c.rate;
    BOOL themeChanged=paletteIndex!=c.theme;
    BOOL sensitivityChanged=scrubSensitivity!=c.sensitivity;
    paletteIndex=c.theme;
    scrubSensitivity=c.sensitivity;
    changeEnabled(c.enabled);
    if (c.enabled && manager && rateChanged) {
        ratePending=true;
        markPractice();
    }
    if (themeChanged) [self applyTheme];
    UIViewController *panel=self.controlsWindow.rootViewController.presentedViewController;
    if (!c.enabled || (rateChanged && [panel isKindOfClass:DTRatePanel.class]) ||
        ((themeChanged || sensitivityChanged) && [panel isKindOfClass:DTSettingsPanel.class])) {
        if ([panel isKindOfClass:DTRatePanel.class]) ((DTRatePanel *)panel).changed=NO;
        [panel dismissViewControllerAnimated:NO completion:nil];
    }
    self.controlsWindow.hidden=!c.enabled;
    self.display.paused=!c.enabled || !playing.load();
    [self check:nil];
}
- (void)becameActive:(NSNotification *)note { [self reloadSettings]; }
- (void)check:(NSTimer *)timer {
    UIApplication *app=UIApplication.sharedApplication;
    if (app.applicationState!=UIApplicationStateActive) return;
    if (!self.attempted) {
        for (uint32_t i=0;i<_dyld_image_count();i++) {
            const char *path=_dyld_get_image_name(i);
            if (!path || !strstr(path,"/UnityFramework.framework/UnityFramework")) continue;
            self.attempted=YES;
            installAll(reinterpret_cast<const mach_header_64 *>(_dyld_get_image_header(i)),path);
            break;
        }
    }
    if (!trainerEnabled) return;
    UIWindow *window=nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.hidden || !w.rootViewController || w.windowLevel!=UIWindowLevelNormal) continue;
            if (!window || w.isKeyWindow) window=w;
            if (w.isKeyWindow) break;
        }
        if (window) break;
    }
    if (!window) {
        for (UIWindow *candidate in app.windows) {
            if (candidate.hidden || !candidate.rootViewController || candidate.windowLevel!=UIWindowLevelNormal) continue;
            window=candidate;
            if (candidate.isKeyWindow) break;
        }
    }
    if (!window || !self.attempted) return;
    if (self.gameWindow!=window || !self.controlsWindow) {
        if (dragging || beginRequested) cancelRequested=true;
        self.controlsWindow.hidden=YES;
        DTControlsWindow *overlay=window.windowScene?[[DTControlsWindow alloc] initWithWindowScene:window.windowScene]:
                                                    [[DTControlsWindow alloc] initWithFrame:window.frame];
        DTControlsRoot *root=[DTControlsRoot new];
        root.gameWindow=window;
        overlay.backgroundColor=UIColor.clearColor;
        overlay.rootViewController=root;
        root.view.backgroundColor=UIColor.clearColor;
        [root.view addSubview:self.bar];
        overlay.toolbar=self.bar;
        overlay.windowLevel=window.windowLevel+1;
        overlay.frame=window.frame;
        self.gameWindow=window;
        self.controlsWindow=overlay;
        overlay.hidden=NO;
    }
    if (!CGRectEqualToRect(self.controlsWindow.frame,window.frame)) self.controlsWindow.frame=window.frame;
    self.display.paused=!playing.load();
    [self refreshTrack:self.display];
}
- (void)presentPanel:(UIViewController *)panel from:(UIButton *)button size:(CGSize)size {
    UIViewController *vc=self.controlsWindow.rootViewController;
    if (!trainerEnabled || !vc || vc.presentedViewController || dragging || beginRequested) return;
    panel.modalPresentationStyle=UIModalPresentationPopover;
    panel.preferredContentSize=size;
    panel.popoverPresentationController.sourceView=button;
    panel.popoverPresentationController.sourceRect=button.bounds;
    [vc presentViewController:panel animated:YES completion:nil];
}
- (void)open {
    DTRatePanel *panel=[DTRatePanel new];
    panel.openedSession=transportID;
    [self presentPanel:panel from:self.button size:CGSizeMake(320,ready?204:120)];
}
- (void)settings {
    DTSettingsPanel *panel=[DTSettingsPanel new];
    __weak DTMenu *menu=self;
    panel.onChange=^{[menu applyTheme];};
    [self presentPanel:panel from:self.settingsButton size:CGSizeMake(315,216)];
}
- (void)start {
    // Upgrade each explicitly saved 0.4.x key only if the companion has not set it.
    NSUserDefaults *legacy=NSUserDefaults.standardUserDefaults;
    NSNumber *rate=[legacy objectForKey:@"DTPracticeRate"];
    if (rate && ![DTStore() objectForKey:DTRate]) DTSet(DTRate,@(tempoTick(rate.doubleValue/100)));
    NSNumber *theme=[legacy objectForKey:@"DTToolbarTheme"], *gain=[legacy objectForKey:@"DTScrubSensitivity"];
    if (theme && ![DTStore() objectForKey:DTTheme]) DTSet(DTTheme,theme);
    if (gain && ![DTStore() objectForKey:DTSensitivity]) DTSet(DTSensitivity,gain);
    int ms=(int)[NSUserDefaults.standardUserDefaults integerForKey:@"DTPracticeOffset"];
    if (ms>=-200 && ms<=200) offsetMs.store(ms);
    self.bar=[UIView new];
    self.bar.layer.cornerRadius=14;
    self.bar.layer.borderWidth=1;
    self.bar.multipleTouchEnabled=YES;
    self.button=[self actionButton:@selector(open)];
    self.button.titleLabel.font=[UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    self.button.accessibilityLabel=@"歌曲倍率";
    self.settingsButton=[self actionButton:@selector(settings)];
    [self.settingsButton setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    self.settingsButton.accessibilityLabel=@"工具栏设置";
    self.settingsButton.hidden=NO;
    self.holdButton=[self actionButton:@selector(hold)];
    self.regionButton=[self actionButton:@selector(mark)];
    self.track=[[DTSongTrack alloc] initWithFrame:CGRectZero];
    self.track.hidden=YES;
    for (UIView *control in @[self.track,self.button,self.holdButton,self.regionButton,self.settingsButton])
        [self.bar addSubview:control];
    [self applyTheme];
    self.display=[CADisplayLink displayLinkWithTarget:self selector:@selector(refreshTrack:)];
    self.display.preferredFramesPerSecond=30;
    self.display.paused=YES;
    [self.display addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resign:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    DTObserve(^{[self reloadSettings];});
    self.timer=[NSTimer timerWithTimeInterval:.5 target:self selector:@selector(check:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];[self reloadSettings];
}
@end

__attribute__((constructor)) static void DTStart(void) {
    @autoreleasepool {
        NSBundle *app=NSBundle.mainBundle;
        if (![app.bundleIdentifier isEqual:@"com.rayark.pluto"] ||
            ![[app objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"5.0.8"] ||
            ![[app objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"1001405"]) return;
        dispatch_async(dispatch_get_main_queue(),^{static DTMenu *menu;menu=[DTMenu new];[menu start];});
    }
}
