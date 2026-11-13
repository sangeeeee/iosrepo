#include "../src/SettingsWire.hpp"
#include <cassert>
#include <cstdio>
using namespace settings;
int main() {
    Snapshot store,app,game;
    assert(!game.unpack(0));
    for(int k=0;k<Count;++k) for(int v=minimum[k];v<=maximum[k];++v) {
        assert(store.apply((Key)k,request(v)));
        assert(app.unpack(store.pack()) && game.unpack(store.pack()));
        assert(app.values[k]==v && game.values[k]==v);
    }
    // Two writers change different keys before a coalesced delivery.
    assert(store.apply(Rate,request(15)) && store.apply(Theme,request(1)));
    assert(!store.apply(Rate,request(20,true)));
    assert(store.apply(Rate,request(24)));
    auto saved=store.pack();
    assert(!store.apply(Rate,request(41)) && !store.unpack(saved|(1ULL<<63)));
    assert(store.pack()==saved && game.unpack(saved) && app.unpack(saved));
    assert(game.values[Rate]==24 && app.values[Theme]==1 && game.present==31);
    puts("PASS: two readers, coalesced updates, all five ranges, last edit, migration and snapshot recovery");
}
