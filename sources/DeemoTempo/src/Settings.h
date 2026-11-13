#pragma once
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <notify.h>
#include "Tempo.hpp"

// Only the public Cephei selectors used by this app. The rootless package owns the framework.
@protocol DTPreferenceStore
- (instancetype)initWithIdentifier:(NSString *)name;
- (id)objectForKey:(NSString *)key;
- (NSDictionary *)dictionaryRepresentation;
- (void)setObject:(id)value forKey:(NSString *)key;
@end
static inline id<DTPreferenceStore> DTStore() {
    static id<DTPreferenceStore> store;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        dlopen("/var/jb/Library/Frameworks/Cephei.framework/Cephei",RTLD_NOW|RTLD_LOCAL);
        Class cls=NSClassFromString(@"HBPreferences");
        store=[(id<DTPreferenceStore>)[cls alloc] initWithIdentifier:@"com.linghe.deemotempo.settings"];
    });
    return store;
}
static NSString *const DTEnabled=@"Enabled", *const DTRate=@"RateTick", *const DTTheme=@"Theme",
                *const DTSensitivity=@"Sensitivity";
static constexpr char DTSettingsChanged[]="com.linghe.deemotempo.settingsChanged";
struct DTConfig {
    bool enabled;
    float rate;
    NSInteger theme;
    float sensitivity;
};
static inline DTConfig DTReadConfig() {
    id<DTPreferenceStore> store=DTStore();
    NSDictionary *values=[store dictionaryRepresentation];
    NSNumber *enabled=values[DTEnabled], *rate=values[DTRate];
    NSInteger theme=[values[DTTheme] integerValue];
    float sensitivity=[values[DTSensitivity] floatValue];
    return {store && (!enabled || enabled.boolValue),
            rate?steppedTempo(rate.doubleValue/20):1.f, theme>=0 && theme<=2?theme:0,
            sensitivity>=.25f && sensitivity<=2.5f?sensitivity:1.f};
}
static inline void DTSet(NSString *key,NSNumber *value) {
    [DTStore() setObject:value forKey:key];
    notify_post(DTSettingsChanged);
}
static inline void DTObserve(void (^handler)(void)) {
    int token=0;
    notify_register_dispatch(DTSettingsChanged,&token,dispatch_get_main_queue(),^(int){handler();});
}
static inline NSArray<NSString *> *DTThemeNames() { return @[@"白色",@"深色",@"浅蓝"]; }
