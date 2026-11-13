struct DTPalette {
    unsigned surface,button,text,rail,progress,start,loop;
};
static const DTPalette palettes[]={
    {0xffffff,0xeef1f5,0x192638,0x87919e,0x115bbc,0xb22534,0x127044},
    {0x202631,0x333d4c,0xf5f7fa,0x8994a5,0x84c8ff,0xff8f98,0x74e5a8},
    {0xe6f2ff,0xcfe2f6,0x17304c,0x8394a5,0x164e91,0xac2334,0x09693c}
};
static NSInteger paletteIndex;
static UIColor *DTColor(unsigned rgb) {
    return [UIColor colorWithRed:((rgb>>16)&255)/255. green:((rgb>>8)&255)/255. blue:(rgb&255)/255. alpha:1];
}

@interface DTSettingsPanel : UIViewController
@property(nonatomic,strong) UISegmentedControl *themes;
@property(nonatomic,strong) UISlider *gain;
- (void)refreshControls;
@property(nonatomic,strong) UILabel *sensitivityLabel;
@end

@implementation DTSettingsPanel
- (void)updateLabel {
    self.sensitivityLabel.text=[NSString stringWithFormat:@"进度条拖动灵敏度   %.0f%%",scrubSensitivity*100];
}
- (void)themeChanged:(UISegmentedControl *)sender {
    DTSet(settings::Theme,(int)sender.selectedSegmentIndex);
}
- (void)sensitivityChanged:(UISlider *)sender {
    sender.value=roundf(sender.value);
    DTSet(settings::Gain,(int)sender.value);
    sender.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",sender.value];
    self.sensitivityLabel.text=[NSString stringWithFormat:@"进度条拖动灵敏度   %@",sender.accessibilityValue];
}
- (void)refreshControls {
    self.themes.selectedSegmentIndex=paletteIndex;
    self.gain.value=roundf(scrubSensitivity*100);
    self.gain.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",self.gain.value];
    [self updateLabel];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    UIStackView *stack=[UIStackView new];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.spacing=10;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16]
    ]];
    UILabel *heading=[UILabel new];
    heading.text=@"工具栏配色";
    [stack addArrangedSubview:heading];
    UISegmentedControl *themes=self.themes=[[UISegmentedControl alloc] initWithItems:DTThemeNames()];
    themes.selectedSegmentIndex=paletteIndex;
    themes.accessibilityLabel=heading.text;
    [themes addTarget:self action:@selector(themeChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:themes];
    self.sensitivityLabel=[UILabel new];
    [self updateLabel];
    [stack addArrangedSubview:self.sensitivityLabel];
    UISlider *slider=self.gain=[UISlider new];
    slider.minimumValue=practice::minSensitivity*100;
    slider.maximumValue=practice::maxSensitivity*100;
    slider.value=scrubSensitivity*100;
    slider.accessibilityLabel=@"进度条拖动灵敏度";
    slider.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",slider.value];
    [slider addTarget:self action:@selector(sensitivityChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:slider];
    UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"完成" forState:UIControlStateNormal];
    [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:done];
}
@end
