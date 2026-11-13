#pragma once
#include <cmath>
#include <algorithm>

inline int tempoTick(double rate) {
    if (!std::isfinite(rate)) return 20;
    return static_cast<int>(std::lround(std::clamp(rate,0.1,2.0)*20));
}
inline float steppedTempo(double rate) { return tempoTick(rate)/20.f; }

// A source consumes original samples at 'rate'. Its local effect cancels that
// pitch change. Chart time stays in ORIGINAL song seconds, including after seeks.
struct Tempo {
    float rate = 1;
    float pitchCorrection() const { return 1.0f / rate; }
    float chartDelta(float realSeconds) const { return realSeconds * rate; }
    float wallDuration(float songSeconds) const { return songSeconds / rate; }
    float audibleSampleDelay(float seconds, float clipHz) const { return seconds * rate * clipHz; }
};

// The host supplies a source-local bus. Effects are never attached to the master.
struct PitchBackend {
    int (*create)(void *system, int type, void **effect);
    int (*parameter)(void *effect, int parameter, float value);
    int (*attach)(void *bus, void *effect, void **connection);
    int (*remove)(void *effect);
    int (*release)(void *effect);
};
class PitchSession {
    static constexpr int maxStages = 4; // 2^4 covers the 10x correction at 0.1x.
    void *effects_[maxStages]{};
    int count_ = 0;
    int window_ = 512;
public:
    float latencySeconds(int outputHz) const {
        return count_ * window_ * .75f / outputHz;
    }
    int start(const PitchBackend &api, void *system, void *bus, int pitchType, Tempo tempo) {
        if (count_ || !system || !bus || !(tempo.rate >= .1f && tempo.rate <= 2)) return -1;
        float factors[maxStages];
        float remaining = tempo.pitchCorrection();
        int needed = 0;
        while (remaining > 2) {
            factors[needed++] = 2;
            remaining *= .5f;
        }
        factors[needed++] = remaining;
        window_ = needed > 1 ? 4096 : 512;
        // addDSP inserts at the head. Insert in reverse playback order.
        while (needed) {
            void *node = nullptr;
            int rc = api.create(system, pitchType, &node);
            if (rc || !node) { stop(api); return rc ? rc : -2; }
            rc = api.parameter(node, 1, window_);
            if (!rc) rc = api.parameter(node, 0, factors[--needed]);
            if (!rc) rc = api.attach(bus, node, nullptr);
            if (rc) {
                api.release(node);
                stop(api);
                return rc;
            }
            effects_[count_++] = node;
        }
        return 0;
    }
    void stop(const PitchBackend &api) {
        while (count_) {
            void *node = effects_[--count_];
            api.remove(node);
            api.release(node);
            effects_[count_] = nullptr;
        }
    }
};
