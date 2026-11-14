#include "../src/Transport.hpp"
#include <cassert>
#include <cstdio>
using namespace practice;
int main(){
    RailTouch finger;
    for(double y : {0.,28.,55.}) for(double x : {10.,85.,100.,180.}) {
        finger.begin(x,y,100);
        finger.move(x+2,y-2);
        assert(finger.phase==RailTouch::tap);
    }
    finger.begin(76,3,100);finger.move(68,4);assert(finger.phase==RailTouch::scrub);
    finger.move(12,63);assert(finger.phase==RailTouch::scrub);
    finger.begin(125,53,100);finger.move(100,53);assert(finger.phase==RailTouch::ignored);
    finger.move(125,53);assert(finger.phase==RailTouch::ignored);
    finger.begin(100,28,100);finger.move(102,40);assert(finger.phase==RailTouch::ignored);
    double last=0;
    for(double w : {320.,375.,667.,768.,1024.,1133.,1194.,1366.}) {
        double bar=toolbarWidth(w);
        assert(bar>last && bar+8<w && bar<std::min(860.,w-8));
        last=bar;
    }
    assert(std::abs(860-toolbarWidth(1133)-44)<2);
    puts("PASS: tap hit area, near-thumb drag, off-thumb and vertical swipe rejection, responsive toolbar widths");
    // An early hit, a late miss and a chord. Decision time, not nominal
    // beat time, determines what survives a rewind.
    std::vector<Note> chart={{1,1,0},{2,2,0},{3,2,0},{4,2.4f,4},{5,3,0},{6,4,0}};
    Journal j;
    j.record(1,1.05f,1);j.record(2,1.95f,.8f);j.record(3,2.15f,0);
    j.move(2.3f,2.05f,chart);
    assert(j.done.count(2) && !j.done.count(3) && j.decisions.size()==2);
    j.move(2.05f,3,chart);
    assert(j.done.count(3) && !j.done.count(4) && !j.done.count(5));
    j.move(3,2.05f,chart);assert(!j.done.count(3)); // Undo even the overdue synthetic miss.
    j.move(2.05f,3,chart);
    j.move(3,3.5f,chart);
    assert(j.decisions.size()==4 && j.decisions.back().id==5);
    j.move(3.5f,1.96f,chart);
    assert(j.decisions.size()==2 && j.done.count(2));
    j.move(1.96f,0,chart);assert(j.decisions.empty());
    j.move(0,5,chart);assert(j.decisions.size()==5);
    j.move(5,5,chart);assert(j.decisions.size()==5);
    assert(!j.record(1,5,1));
    for(double hz : {15.,30.,60.,120.}){
        double near=follow(10,12,180,1/hz)-10;
        double far=follow(10,150,180,1/hz)-10;
        assert(far>near && near>0 && far<=36/hz+.00001);
        assert(std::abs(near-(.7+3.8*2)/2.5*std::min(.05,1/hz))<1e-10);
        assert(follow(150,10,180,1/hz)<150);
        assert(follow(1,1,180,1/hz)==1);
        double position=1;
        for(int i=0;i<3600;++i) {position=follow(position,2,180,1/hz);assert(position<=2);}
        assert(position==2);
    }
    assert(follow(0,999,10,50)<=10 && follow(1,0,10,50)>=0);
    for (double gain : {.25,.75,1.,1.5,2.5}) {
        double dt=1./60;
        double defaultStep=follow(40,45,180,dt)-40;
        assert(std::abs(follow(40,45,180,dt,gain)-40-defaultStep*gain)<1e-10);
        assert(std::abs(40-follow(40,35,180,dt,gain)-defaultStep*gain)<1e-10);
        assert(std::abs(follow(40,180,180,dt,gain)-40-36*dt*gain)<1e-10);
        assert(follow(.001,0,10,dt,gain)==0 && follow(9.999,10,10,dt,gain)==10);
    }
    for(double length : {15.,180.,600.}) for(double fps : {30.,60.,120.}) {
        double dt=1/fps;
        double a=follow(7.0,-50,length,dt);
        double b=follow(length-7,length+50,length,dt);
        assert(std::abs((7-a)-(b-(length-7)))<1e-10);
        assert(std::abs((7-a)-36*dt)<1e-10);
        assert(follow(.15,0,length,dt)==0 && follow(length-.15,length,length,dt)==length);
    }
    LoopRange loop;
    RateObservation observation;
    for(int i=0;i<240;i++) assert(!observation.changed(1.f/60,1.f/60));
    for(int i=0;i<120;i++) assert(!observation.changed(.333f,1.f)); // capped frames
    for(float rate : {0.f,.5f,1.5f,2.f}) {
        observation={};
        for(int i=0;i<20;i++) assert(!observation.changed(rate/60,1.f/60));
        for(int i=0;i<20;i++) observation.changed(rate/60,1.f/60);
        assert(observation.changed(rate/60,1.f/60));
        assert(!observation.changed(1.f/60,1.f/60));
    }
    assert(!loop.complete() && loop.constrain(2)==2);
    loop.mark(10);loop.mark(10);
    assert(loop.first==10 && !loop.complete() && loop.constrain(0)==0);
    loop.mark(4);assert(loop.first==4 && !loop.complete());
    loop.mark(10);assert(loop.complete() && loop.constrain(1)==4 && loop.constrain(8)==8 && loop.constrain(12)==10);
    loop.mark(7);assert(loop.first<0 && loop.second<0);
    loop.mark(0);loop.mark(4);
    for (int i=0;i<8;++i) {
        j.move(loop.second,loop.first,chart);assert(j.decisions.empty());
        j.move(loop.first,loop.second,chart);assert(j.decisions.size()==4);
    }
    auto window=visibleNotes(chart,2,3);
    assert(window.first==1 && window.end==5); // include both halves of chord
    window=visibleNotes(chart,3.1f,3.8f);
    assert(window.first==window.end); // genuinely empty section
    window=visibleNotes(chart,1.99f,2.01f);
    assert(window.first==1 && window.end==3); // chord returns on backwards motion
    // Adjacent timestamps from Entrance Hard and Magnolia Hard. Exercise a
    // seek between them with a background note, a chord and a late judgement.
    for (auto pair : {std::pair<float,float>{56.671875f,56.66796875f},
                      std::pair<float,float>{89.4453125f,89.4375f}}) {
        const float later=pair.first, earlier=pair.second, target=(earlier+later)/2;
        std::vector<Note> native={{1,earlier-1,-3},{2,later,2},{3,earlier,-2},
                                  {4,earlier,4},{5,earlier,0}};
        const auto ordered=chronologicalNotes(native);
        assert(native[1].id==2 && ordered[4].id==2);
        auto visible=visibleNotes(ordered,earlier,target);
        assert(visible.first==1 && visible.end==4);
        assert(ordered[1].id==3 && ordered[2].id==4 && ordered[3].id==5);
        Journal history;
        history.move(0,target,ordered);
        assert(history.decisions.size()==2 && history.done.count(3) && history.done.count(5));
        auto consumed=history.done;
        consumed.insert(4);
        assert(resumeIndex(native,target,consumed)==1); // future note precedes consumed entries
        history.move(target,earlier-.1f,ordered);
        assert(history.done.empty());
        history.move(earlier-.1f,later+1,ordered);
        assert(history.decisions.size()==3);
        consumed.insert(2);
        assert(resumeIndex(native,later+1,consumed)==native.size());
        consumed.erase(3);
        assert(resumeIndex(native,later+1,consumed)==2); // overdue and still unjudged
    }
    puts("PASS: out-of-order Hard charts, stable chords, preview, seek judgements and native restart index");
    puts("PASS: 2.5x slower follow, endpoint speed, marker replacement/cancel, loop limits and repeated judgement rollback");
}
