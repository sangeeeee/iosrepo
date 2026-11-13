#import "Settings.h"

@interface DTTrainerSettings : UITableViewController
@property(nonatomic,strong) UISwitch *enabledSwitch;
@property(nonatomic,strong) UISegmentedControl *themes;
@property(nonatomic,strong) UISlider *speed,*gain,*delay;
@property(nonatomic,strong) UILabel *speedLabel,*gainLabel,*delayLabel;
@end

@implementation DTTrainerSettings
- (UISlider *)sliderFrom:(float)minimum to:(float)maximum action:(SEL)action label:(NSString *)label {
    UISlider *slider=[UISlider new];
    slider.minimumValue=minimum;
    slider.maximumValue=maximum;
    slider.accessibilityLabel=label;
    [slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return slider;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"DEEMO Trainer";
    self.navigationController.navigationBar.prefersLargeTitles=YES;
    self.tableView.allowsSelection=NO;
    self.enabledSwitch=[UISwitch new];
    self.enabledSwitch.accessibilityLabel=@"启用练习器";
    [self.enabledSwitch addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    self.themes=[[UISegmentedControl alloc] initWithItems:DTThemeNames()];
    self.themes.accessibilityLabel=@"工具栏配色";
    [self.themes addTarget:self action:@selector(theme:) forControlEvents:UIControlEventValueChanged];
    self.speed=[self sliderFrom:2 to:40 action:@selector(speedChanged:) label:@"乐曲速度"];
    self.gain=[self sliderFrom:25 to:250 action:@selector(gainChanged:) label:@"拖动灵敏度"];
    self.delay=[self sliderFrom:-200 to:200 action:@selector(delayChanged:) label:@"声音延迟微调"];
    self.speedLabel=[UILabel new];
    self.gainLabel=[UILabel new];
    self.delayLabel=[UILabel new];
    [self refresh];
    __weak DTTrainerSettings *weakSelf=self;
    DTObserve(^{[weakSelf refresh];},^{
        [weakSelf refresh];
        if (!weakSelf.view.window || weakSelf.presentedViewController) return;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"设置保存失败" message:@"请检查设备存储空间后重试。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    });
    [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer *timer){
        if (!weakSelf) { [timer invalidate]; return; }
        if (UIApplication.sharedApplication.applicationState==UIApplicationStateActive) [weakSelf refresh];
    }];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)active:(NSNotification *)note { [self refresh]; }
- (void)refresh {
    DTConfig c;
    BOOL available=DTReadConfig(c);
    self.enabledSwitch.enabled=self.speed.enabled=self.gain.enabled=self.delay.enabled=self.themes.enabled=available;
    if (!available) return;
    self.enabledSwitch.on=c.enabled;
    self.themes.selectedSegmentIndex=c.theme;
    if (!self.speed.tracking) self.speed.value=tempoTick(c.rate);
    if (!self.gain.tracking) self.gain.value=roundf(c.sensitivity*100);
    if (!self.delay.tracking) self.delay.value=c.delay;
    [self updateLabels];
}
- (void)updateLabels {
    self.speed.accessibilityValue=[NSString stringWithFormat:@"%.2f×",roundf(self.speed.value)/20];
    self.gain.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",self.gain.value];
    self.speedLabel.text=[NSString stringWithFormat:@"乐曲速度    %@",self.speed.accessibilityValue];
    self.gainLabel.text=[NSString stringWithFormat:@"拖动灵敏度    %@",self.gain.accessibilityValue];
    self.delay.accessibilityValue=[NSString stringWithFormat:@"%.0f ms",self.delay.value];
    self.delayLabel.text=[NSString stringWithFormat:@"声音延迟微调    %@",self.delay.accessibilityValue];
}
- (void)delayChanged:(UISlider *)sender {
    sender.value=roundf(sender.value);
    [self updateLabels];
    DTSet(settings::Delay,(int)sender.value+200);
}
- (void)toggle:(UISwitch *)sender { DTSet(settings::Enabled,sender.on); }
- (void)theme:(UISegmentedControl *)sender { DTSet(settings::Theme,(int)sender.selectedSegmentIndex); }
- (void)speedChanged:(UISlider *)sender {
    int tick=(int)lroundf(sender.value);
    sender.value=tick;
    [self updateLabels];
    DTSet(settings::Rate,tick);
}
- (void)gainChanged:(UISlider *)sender {
    sender.value=roundf(sender.value);
    [self updateLabels];
    DTSet(settings::Gain,(int)sender.value);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section==0?1:4; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return path.section==0?56:86;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    DTConfig current;
    if (section==0 && !DTReadConfig(current)) return @"正在等待设置服务。";
    return section==0?@"切换后，正在运行的 DEEMO 也会应用此设置。":nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (path.section==0) {
        cell.textLabel.text=@"启用练习器";
        cell.accessoryView=self.enabledSwitch;
        return cell;
    }
    UILabel *label=path.row==0?self.speedLabel:path.row==2?self.gainLabel:path.row==3?self.delayLabel:[UILabel new];
    UIView *control=path.row==0?(UIView *)self.speed:path.row==1?(UIView *)self.themes:path.row==2?self.gain:self.delay;
    if (path.row==1) label.text=@"工具栏配色";
    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[label,control]];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.spacing=6;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [cell.contentView addSubview:stack];
    UILayoutGuide *margin=cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:margin.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:margin.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
    ]];
    return cell;
}
@end

@interface DTTrainerDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation DTTrainerDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    DTTrainerSettings *settings=[[DTTrainerSettings alloc] initWithStyle:UITableViewStyleInsetGrouped];
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:settings];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool {return UIApplicationMain(argc,argv,nil,NSStringFromClass(DTTrainerDelegate.class));}
}
