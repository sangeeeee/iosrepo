#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_set>
#include <vector>

namespace practice {
// On wide iPads the rail grows more slowly, leaving room for the game UI.
inline double toolbarWidth(double available) {
    return std::min(.94*available,702.+.10*available);
}

struct RailTouch {
    enum Phase { idle, tap, scrub, ignored };
    Phase phase=idle;
    double startX=0, startY=0;
    bool nearHead=false;
    void begin(double x,double y,double head) {
        startX=x; startY=y;
        nearHead=std::abs(x-head)<=24;
        phase=tap;
    }
    void move(double x,double y) {
        if (phase!=tap) return;
        double dx=std::abs(x-startX),dy=std::abs(y-startY);
        if (std::max(dx,dy)<8) return;
        phase=nearHead && dx>=dy?scrub:ignored;
    }
};
struct Note {
    uintptr_t id;
    float time;
    bool scored;
};
struct Decision {
    uintptr_t id;
    float time;
    float ratio;
};

// A seek branches the current run. Repeated forward/backward drags cannot
// duplicate a chord, resurrect a discarded future, or turn backing notes into misses.
struct Journal {
    std::vector<Decision> decisions;
    std::unordered_set<uintptr_t> done;
    bool record(uintptr_t id,float time,float ratio) {
        if (!id || !std::isfinite(time) || !std::isfinite(ratio) || !done.insert(id).second) return false;
        decisions.push_back({id,time,ratio});
        return true;
    }
    void move(float from,float to,const std::vector<Note>& notes) {
        if (to<from) {
            decisions.erase(std::remove_if(decisions.begin(),decisions.end(),
                [&](const Decision& e){return e.time>to;}),decisions.end());
            done.clear();
            for (auto e:decisions) done.insert(e.id);
        } else if (to>from) {
            for (const auto& n:notes) {
                if (n.time>=to) break;
                // An overdue, still-unjudged note in the original timing window
                // is also passed when skipping. Previously recorded hits win.
                if (n.scored) record(n.id,std::nextafter(std::max(n.time,from),to),0);
            }
        }
    }
};

struct NoteWindow { size_t first, end; };
inline NoteWindow visibleNotes(const std::vector<Note>& notes, float time, float horizon) {
    const auto first=std::lower_bound(notes.begin(),notes.end(),time,
        [](const Note& note,float t){return note.time<t;});
    const auto end=std::upper_bound(first,notes.end(),horizon,
        [](float t,const Note& note){return t<note.time;});
    return {static_cast<size_t>(first-notes.begin()),static_cast<size_t>(end-notes.begin())};
}

struct LoopRange {
    float first=-1, second=-1;
    bool complete() const {return second>first && first>=0;}
    void mark(float t) {
        if (complete()) {*this={};return;}
        if (first<0 || t<=first) first=t;
        else second=t;
    }
    float constrain(float t) const {return complete()?std::clamp(t,first,second):t;}
};
// Compare the game's scaled and unscaled frame clocks during active play.
// Discard isolated frame stalls (Unity caps scaled delta after a stall).
struct RateObservation {
    float elapsed=0;
    bool changed(float scaled,float unscaled) {
        if (!std::isfinite(scaled) || !(unscaled>0 && unscaled<.1f) ||
            std::fabs(scaled-unscaled)<=.001f*unscaled+.00001f) {
            elapsed=0;
            return false;
        }
        elapsed+=unscaled;
        return elapsed>=.5f;
    }
};
constexpr double minSensitivity=.25, maxSensitivity=2.5;
inline double follow(double current,double target,double length,double dt,double sensitivity=1) {
    if (!(length>0 && std::isfinite(target) && std::isfinite(dt) && dt>0)) return current;
    const double goal=std::clamp(target,0.,length);
    const double gap=goal-current;
    constexpr double topSpeed=36; // original song seconds per real second
    const bool endpoint=target<=0 || target>=length;
    const double speed=endpoint ? topSpeed : std::min(topSpeed,(.7+3.8*std::abs(gap))/2.5);
    const double gain=std::isfinite(sensitivity)?std::clamp(sensitivity,minSensitivity,maxSensitivity):1.;
    const double step=speed*gain*std::min(dt,.05);
    if (std::abs(gap)<=step) return goal;
    return current+std::copysign(step,gap);
}
}
