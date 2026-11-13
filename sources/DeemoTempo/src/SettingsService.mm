#import <Foundation/Foundation.h>
#include <notify.h>
#include <cmath>
#include "SettingsWire.hpp"

using namespace settings;
static NSString *const path=@"/var/mobile/Library/Preferences/com.linghe.deemotrainer.sync.plist";
static int output, tokens[Count];
static Snapshot current;

static bool persist(const Snapshot &s) {
    return [@{@"settings":@(s.pack())} writeToFile:path atomically:YES];
}
static void publish() {
    if (notify_set_state(output,current.pack())==NOTIFY_STATUS_OK) notify_post(changed);
}
static void receive(Key key) {
    uint64_t value=0;
    if (notify_get_state(tokens[key],&value)!=NOTIFY_STATUS_OK) return;
    Snapshot next=current;
    if (next.apply(key,value) && next.pack()!=current.pack()) {
        if (!persist(next)) {
            NSLog(@"[DEEMO Trainer] Unable to save settings");
            publish();
            notify_post(failed);
            return;
        }
        current=next;
    }
    publish();
}
int main() {
    @autoreleasepool {
        NSDictionary *saved=[NSDictionary dictionaryWithContentsOfFile:path];
        if (!current.unpack([saved[@"settings"] unsignedLongLongValue])) {
            NSDictionary *old=[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.linghe.deemotempo.settings.plist"];
            NSArray *keys=@[@"Enabled",@"RateTick",@"Theme",@"Sensitivity"];
            for(int i=0;i<4;++i) {
                NSNumber *n=old[keys[i]];
                if (![n isKindOfClass:NSNumber.class]) continue;
                int v=i==Gain?(int)lround(n.doubleValue*100):n.intValue;
                current.apply((Key)i,request(v,true));
            }
            if (!persist(current)) { NSLog(@"[DEEMO Trainer] Settings storage unavailable"); return 1; }
        }
        if (notify_register_check(changed,&output)!=NOTIFY_STATUS_OK) return 1;
        for(int i=0;i<Count;++i) {
            Key key=(Key)i;
            if(notify_register_dispatch(requests[i],&tokens[i],dispatch_get_main_queue(),^(int){receive(key);})!=NOTIFY_STATUS_OK) return 1;
        }
        for(int i=0;i<Count;++i) receive((Key)i);
        publish();
    }
    dispatch_main();
}
