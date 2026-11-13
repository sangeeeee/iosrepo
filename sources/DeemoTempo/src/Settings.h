#pragma once
#import <UIKit/UIKit.h>
#include <notify.h>
#include "Tempo.hpp"
#include "SettingsWire.hpp"

struct DTConfig {
    bool enabled;
    float rate;
    NSInteger theme;
    float sensitivity;
    int delay;
};
static int DTToken(settings::Key key) {
    static int tokens[settings::Count];
    static dispatch_once_t once;
    dispatch_once(&once,^{
        for(int i=0;i<settings::Count;++i)
            if (notify_register_check(settings::requests[i],&tokens[i])!=NOTIFY_STATUS_OK) tokens[i]=-1;
    });
    return tokens[key];
}
static bool DTReadSnapshot(settings::Snapshot &out) {
    static int token=-1;
    static dispatch_once_t once;
    dispatch_once(&once,^{notify_register_check(settings::changed,&token);});
    uint64_t value=0;
    return token>=0 && notify_get_state(token,&value)==NOTIFY_STATUS_OK && out.unpack(value);
}
static DTConfig DTDecode(const settings::Snapshot &snapshot) {
    const int *v=snapshot.values;
    return {bool(v[settings::Enabled]),v[settings::Rate]/20.f,v[settings::Theme],v[settings::Gain]/100.f,v[settings::Delay]-200};
}
static inline bool DTReadConfig(DTConfig &config) {
    settings::Snapshot snapshot;
    if (!DTReadSnapshot(snapshot)) return false;
    config=DTDecode(snapshot);
    return true;
}
static bool DTSet(settings::Key key,int value,bool migrate=false) {
    if (value<settings::minimum[key] || value>settings::maximum[key]) return false;
    int token=DTToken(key);
    return token>=0 && notify_set_state(token,settings::request(value,migrate))==NOTIFY_STATUS_OK &&
           notify_post(settings::requests[key])==NOTIFY_STATUS_OK;
}
static void DTObserve(void (^handler)(void),void (^onFailure)(void)) {
    int token=-1;
    notify_register_dispatch(settings::changed,&token,dispatch_get_main_queue(),^(int){handler();});
    notify_register_dispatch(settings::failed,&token,dispatch_get_main_queue(),^(int){onFailure();});
}
static inline NSArray<NSString *> *DTThemeNames() { return @[@"白色",@"深色",@"浅蓝"]; }
