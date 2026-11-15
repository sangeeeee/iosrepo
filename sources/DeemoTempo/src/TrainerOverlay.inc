@interface DTRatePanel : UIViewController
@property(nonatomic,strong) UILabel *readout;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic) unsigned openedSession;
@end
@implementation DTRatePanel
- (void)displayRate:(float)rate {
    self.slider.value=rate;
    self.readout.text=[NSString stringWithFormat:@"练习倍率   %.2f×",rate];
    self.slider.accessibilityValue=[NSString stringWithFormat:@"%.2f×",rate];
}
- (void)applyRate:(UISlider *)slider {
    if (!trainerEnabled || self.openedSession!=transportID) return;
    float value=steppedTempo(slider.value);
    [self displayRate:value];
    DTSet(settings::Rate,tempoTick(value));
}
- (void)reset {
    self.slider.value=1;
    [self applyRate:self.slider];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)editDelay {
    UIAlertController *edit=[UIAlertController alertControllerWithTitle:@"声音延迟微调（毫秒）" message:@"正值将判定线向后移。对当前设备保存，默认 0。" preferredStyle:UIAlertControllerStyleAlert];
    [edit addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=[NSString stringWithFormat:@"%d",offsetMs.load()];f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;}];
    [edit addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [edit addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSScanner *scan=[NSScanner scannerWithString:edit.textFields.firstObject.text?:@""];
        NSInteger ms=0;if ([scan scanInteger:&ms] && scan.isAtEnd && ms>=-200 && ms<=200) {
            DTSet(settings::Delay,(int)ms+200);
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
    status.text=practiceSession()?@"本局练习 · 结算 0%":statusText;
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
@property(nonatomic) uint64_t lastSnapshot;
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
    CGFloat total=practice::toolbarWidth(available);
    CGFloat x=5;
    CGFloat rail=total-2*x-rateWidth-3*actionWidth-4*gap;
    self.bar.frame=CGRectMake(insets.left+8,y,total,56);
    self.button.frame=CGRectMake(x,4,rateWidth,48);
    x+=rateWidth+gap;
    self.track.frame=CGRectMake(x,0,rail,56);
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
    settings::Snapshot snapshot;
    if (!DTReadSnapshot(snapshot) || self.lastSnapshot==snapshot.pack()) return;
    self.lastSnapshot=snapshot.pack();
    DTConfig c=DTDecode(snapshot);
    int oldDelay=offsetMs.exchange(c.delay);
    updateDelay(oldDelay,c.delay);
    float previous=selection.exchange(c.rate);
    BOOL rateChanged=previous!=c.rate;
    BOOL themeChanged=paletteIndex!=c.theme;
    BOOL sensitivityChanged=scrubSensitivity!=c.sensitivity;
    paletteIndex=c.theme;
    scrubSensitivity=c.sensitivity;
    changeEnabled(c.enabled);
    if (c.enabled && manager && rateChanged) {
        ratePending=true;
        rateAfter=CACurrentMediaTime()+.12;
        markPractice();
    }
    if (themeChanged) [self applyTheme];
    UIViewController *panel=self.controlsWindow.rootViewController.presentedViewController;
    if (!c.enabled) {
        [panel dismissViewControllerAnimated:NO completion:nil];
        if (self.controlsWindow.isKeyWindow) [self.gameWindow makeKeyWindow];
    } else if (rateChanged && [panel isKindOfClass:DTRatePanel.class]) {
        [(DTRatePanel *)panel displayRate:c.rate];
        if (manager) ((DTRatePanel *)panel).statusLabel.text=@"本局练习 · 结算 0%";
    } else if ((themeChanged || sensitivityChanged) && [panel isKindOfClass:DTSettingsPanel.class]) {
        [(DTSettingsPanel *)panel refreshControls];
    }
    self.controlsWindow.hidden=!c.enabled;
    self.display.paused=!c.enabled || !playing.load();
}
- (void)becameActive:(NSNotification *)note { [self reloadSettings]; }
- (void)check:(NSTimer *)timer {
    UIApplication *app=UIApplication.sharedApplication;
    if (app.applicationState!=UIApplicationStateActive) return;
    [self reloadSettings];
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
    if (self.controlsWindow.isKeyWindow && !self.controlsWindow.rootViewController.presentedViewController)
        [self.gameWindow makeKeyWindow];
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
    [self.controlsWindow makeKeyWindow];
    [vc presentViewController:panel animated:YES completion:nil];
}
- (void)open {
    DTRatePanel *panel=[DTRatePanel new];
    panel.openedSession=transportID;
    [self presentPanel:panel from:self.button size:CGSizeMake(320,ready?204:120)];
}
- (void)settings {
    DTSettingsPanel *panel=[DTSettingsPanel new];
    [self presentPanel:panel from:self.settingsButton size:CGSizeMake(315,216)];
}
- (void)start {
    // Upgrade each explicitly saved 0.4.x key only if the companion has not set it.
    NSUserDefaults *legacy=NSUserDefaults.standardUserDefaults;
    NSNumber *rate=[legacy objectForKey:@"DTPracticeRate"];
    settings::Snapshot saved;
    if (DTReadSnapshot(saved)) {
        if (rate && !(saved.present&(1u<<settings::Rate))) DTSet(settings::Rate,tempoTick(rate.doubleValue/100),true);
        NSNumber *theme=[legacy objectForKey:@"DTToolbarTheme"], *gain=[legacy objectForKey:@"DTScrubSensitivity"];
        if (theme && !(saved.present&(1u<<settings::Theme))) DTSet(settings::Theme,theme.intValue,true);
        if (gain && !(saved.present&(1u<<settings::Gain))) DTSet(settings::Gain,lroundf(gain.floatValue*100),true);
        NSNumber *delay=[legacy objectForKey:@"DTPracticeOffset"];
        if (delay && !(saved.present&(1u<<settings::Delay))) DTSet(settings::Delay,delay.intValue+200,true);
    }
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
    DTObserve(^{[self reloadSettings];[self check:nil];},^{
        self.lastSnapshot=0;
        [self reloadSettings];
        UIViewController *panel=self.controlsWindow.rootViewController.presentedViewController;
        if ([panel isKindOfClass:DTRatePanel.class]) {
            [(DTRatePanel *)panel displayRate:selection.load()];
            ((DTRatePanel *)panel).statusLabel.text=@"设置保存失败，请重试";
        } else if ([panel isKindOfClass:DTSettingsPanel.class]) {
            [(DTSettingsPanel *)panel refreshControls];
            ((DTSettingsPanel *)panel).sensitivityLabel.text=@"设置保存失败，请重试";
        }
    });
    self.timer=[NSTimer timerWithTimeInterval:.5 target:self selector:@selector(check:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];[self reloadSettings];[self check:nil];
}
@end

__attribute__((constructor)) static void DTStart(void) {
    @autoreleasepool {
        NSBundle *app=NSBundle.mainBundle;
        if (![app.bundleIdentifier isEqual:gameBundle] ||
            ![[app objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:gameVersion] ||
            ![[app objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:gameBuild]) return;
        dispatch_async(dispatch_get_main_queue(),^{static DTMenu *menu;menu=[DTMenu new];[menu start];});
    }
}
