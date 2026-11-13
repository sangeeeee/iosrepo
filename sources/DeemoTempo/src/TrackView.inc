@interface DTSongTrack : UIView {
    practice::RailTouch _gesture;
}
@property(nonatomic,strong) UILabel *timeLabel;
@property(nonatomic) unsigned session;
@end

@implementation DTSongTrack
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.opaque=NO;
        self.backgroundColor=UIColor.clearColor;
        self.layer.cornerRadius=14;
        self.multipleTouchEnabled=NO;
        self.timeLabel=[UILabel new];
        self.timeLabel.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
        self.timeLabel.textAlignment=NSTextAlignmentCenter;
        [self addSubview:self.timeLabel];
        self.isAccessibilityElement=YES;
        self.accessibilityLabel=@"歌曲进度";
        self.accessibilityHint=@"轻点跳转，拖动播放头可缓慢定位";
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=CGRectGetWidth(self.bounds);
    self.timeLabel.hidden=w<185;
    self.timeLabel.frame=CGRectMake(MAX(0,w-85),0,82,CGRectGetHeight(self.bounds));
    [self setNeedsDisplay];
}
- (CGFloat)travel {
    CGFloat width=CGRectGetWidth(self.bounds);
    return MAX(1,width-(width<185?20:100));
}
- (void)drawRect:(CGRect)rect {
    if (!(durationSec>0)) return;
    CGFloat y=CGRectGetMidY(self.bounds),travel=[self travel];
    CGFloat x=10+travel*std::clamp((dragging?positionSec:progressSec)/durationSec,0.f,1.f);
    const DTPalette &p=palettes[paletteIndex];
    CGFloat left=10+travel*region.first/durationSec;
    CGFloat right=10+travel*region.second/durationSec;
    if (region.complete()) {
        [[DTColor(p.loop) colorWithAlphaComponent:.18] setFill];
        [[UIBezierPath bezierPathWithRect:CGRectMake(left,3,right-left,2*y-6)] fill];
    }
    [DTColor(p.rail) setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(10,y-2.5,travel,5) cornerRadius:2.5] fill];
    [DTColor(p.progress) setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(10,y-2.5,x-10,5) cornerRadius:2.5] fill];
    if (region.first>=0) {
        const BOOL pair=region.complete();
        UIColor *color=DTColor(pair?p.loop:p.start);
        NSDictionary *attrs=@{NSForegroundColorAttributeName:color,NSFontAttributeName:[UIFont boldSystemFontOfSize:10]};
        [color setFill]; UIRectFill(CGRectMake(left-1,7,2,2*y-14));
        [@"1" drawAtPoint:CGPointMake(left-8,0) withAttributes:attrs];
        if (pair) {
            UIRectFill(CGRectMake(right-1,7,2,2*y-14));
            [@"2" drawAtPoint:CGPointMake(right+2,0) withAttributes:attrs];
        }
    }
    if (dragging) {
        CGFloat goal=10+travel*aimSec/durationSec;
        [[DTColor(p.text) colorWithAlphaComponent:.65] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(goal-3,y-3,6,6)] fill];
    }
    [DTColor(p.text) setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x-6,y-6,12,12)] fill];
}
- (void)refresh {
    int pos=MAX(0,(int)(dragging?positionSec:progressSec)),end=MAX(0,(int)durationSec);
    self.timeLabel.text=[NSString stringWithFormat:@"%d:%02d / %d:%02d",pos/60,pos%60,end/60,end%60];
    self.accessibilityValue=self.timeLabel.text;
    [self setNeedsDisplay];
}
- (void)aim:(UITouch *)touch {
    CGFloat travel=[self travel];
    CGFloat x=[touch locationInView:self].x-10;
    // A thumb centered on the physical end of the rail should select it reliably.
    if (x<=3) aimSec=0;
    else if (x>=travel-3) aimSec=durationSec;
    else aimSec=durationSec*x/travel;
    aimSec=region.constrain(aimSec);
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _gesture.phase=practice::RailTouch::idle;
    CGPoint point=[touches.anyObject locationInView:self];
    CGFloat travel=[self travel];
    if (!trainerEnabled || !playing.load() || !chartReady || !historyOK || paused ||
        beginRequested || dragging || !(durationSec>0) || point.x>travel+20) return;
    self.session=transportID;
    CGFloat head=10+travel*std::clamp(progressSec/durationSec,0.f,1.f);
    _gesture.begin(point.x,point.y,head);
}
- (void)trackMotion:(UITouch *)touch {
    if (_gesture.phase==practice::RailTouch::idle || self.session!=transportID) return;
    CGPoint point=[touch locationInView:self];
    auto previous=_gesture.phase;
    _gesture.move(point.x,point.y);
    if (_gesture.phase!=practice::RailTouch::scrub) return;
    [self aim:touch];
    if (previous==practice::RailTouch::tap) {
        beginRequested=true;
        finishRequested=cancelRequested=jumpRequested=false;
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self trackMotion:touches.anyObject];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch=touches.anyObject;
    [self trackMotion:touch];
    if (self.session==transportID && trainerEnabled && !paused && historyOK) {
        if (_gesture.phase==practice::RailTouch::tap) {
            [self aim:touch];
            beginRequested=jumpRequested=true;
            finishRequested=cancelRequested=false;
        } else if (_gesture.phase==practice::RailTouch::scrub) {
            finishRequested=true;
        }
    } else if (self.session==transportID && (dragging || beginRequested)) {
        cancelRequested=true;
    }
    _gesture.phase=practice::RailTouch::idle;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_gesture.phase==practice::RailTouch::scrub && self.session==transportID)
        cancelRequested=true;
    _gesture.phase=practice::RailTouch::idle;
}
@end
