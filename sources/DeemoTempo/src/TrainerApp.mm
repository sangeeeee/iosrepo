#import "Settings.h"

@interface DTTrainerSettings : UITableViewController
@property(nonatomic,strong) UISwitch *enabledSwitch;
@property(nonatomic,strong) UISegmentedControl *themes;
@property(nonatomic,strong) UISlider *speed,*gain;
@property(nonatomic,strong) UILabel *speedLabel,*gainLabel;
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
    self.speedLabel=[UILabel new];
    self.gainLabel=[UILabel new];
    [self refresh];
    __weak DTTrainerSettings *weakSelf=self;
    DTObserve(^{[weakSelf refresh];});
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)active:(NSNotification *)note { [self refresh]; }
- (void)refresh {
    DTConfig c=DTReadConfig();
    self.enabledSwitch.on=c.enabled;
    self.enabledSwitch.enabled=DTStore()!=nil;
    self.themes.selectedSegmentIndex=c.theme;
    if (!self.speed.tracking) self.speed.value=tempoTick(c.rate);
    if (!self.gain.tracking) self.gain.value=roundf(c.sensitivity*100);
    self.speed.enabled=self.gain.enabled=self.themes.enabled=DTStore()!=nil;
    [self updateLabels];
}
- (void)updateLabels {
    self.speed.accessibilityValue=[NSString stringWithFormat:@"%.2f×",roundf(self.speed.value)/20];
    self.gain.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",self.gain.value];
    self.speedLabel.text=[NSString stringWithFormat:@"乐曲速度    %@",self.speed.accessibilityValue];
    self.gainLabel.text=[NSString stringWithFormat:@"拖动灵敏度    %@",self.gain.accessibilityValue];
}
- (void)toggle:(UISwitch *)sender { DTSet(DTEnabled,@(sender.on)); }
- (void)theme:(UISegmentedControl *)sender { DTSet(DTTheme,@(sender.selectedSegmentIndex)); }
- (void)speedChanged:(UISlider *)sender {
    int tick=(int)lroundf(sender.value);
    sender.value=tick;
    [self updateLabels];
    if ([[DTStore() objectForKey:DTRate] integerValue]!=tick) DTSet(DTRate,@(tick));
}
- (void)gainChanged:(UISlider *)sender {
    sender.value=roundf(sender.value);
    [self updateLabels];
    DTSet(DTSensitivity,@(sender.value/100));
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section==0?1:3; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return path.section==0?56:86;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (!DTStore() && section==0) return @"请在 Sileo 安装 Cephei Tweak Support 后重新打开。";
    return section==0?@"切换后，正在运行的 DEEMO 也会应用此设置。":nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (path.section==0) {
        cell.textLabel.text=@"启用练习器";
        cell.accessoryView=self.enabledSwitch;
        return cell;
    }
    UILabel *label=path.row==0?self.speedLabel:path.row==2?self.gainLabel:[UILabel new];
    UIView *control=path.row==0?(UIView *)self.speed:path.row==1?(UIView *)self.themes:self.gain;
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
