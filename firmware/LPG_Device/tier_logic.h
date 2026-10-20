// Tier classification, hard safety override and debouncing.
// Pure C++ (no Arduino headers) so it can be unit-tested on a PC.
#pragma once

#include <stdint.h>

#include "config.h"

enum Tier : uint8_t {
  TIER_SAFE = 0,
  TIER_WARNING = 1,
  TIER_DANGEROUS = 2,
  TIER_CRITICAL = 3,
};

inline const char *tierName(Tier t) {
  switch (t) {
    case TIER_SAFE: return "Safe";
    case TIER_WARNING: return "Warning";
    case TIER_DANGEROUS: return "Dangerous";
    default: return "Critical";
  }
}

// Same rules as the backend fallback (backend/app/services/inference.py):
// <150 Safe, <300 Warning, <700 Dangerous, else Critical.
inline Tier tierFromPpmRules(float ppm) {
  if (ppm < TIER_WARNING_PPM) return TIER_SAFE;
  if (ppm < TIER_DANGEROUS_PPM) return TIER_WARNING;
  if (ppm < TIER_CRITICAL_PPM) return TIER_DANGEROUS;
  return TIER_CRITICAL;
}

// LIFE-SAFETY OVERRIDE. Whatever the model says, >= 700 ppm is Critical.
inline Tier applySafetyOverride(Tier modelTier, float ppmComp) {
  return ppmComp >= TIER_CRITICAL_PPM ? TIER_CRITICAL : modelTier;
}

// Requires DEBOUNCE_SECONDS consecutive readings at a new tier before it becomes
// the active (actuating) tier. Call update() exactly once per 1 Hz sample.
//
// Exceptions that are NOT debounced:
//   * ppm >= 700 -> Critical immediately (the override).
//   * While Critical, the tier is held until ppm <= OVERRIDE_CLEAR_PPM
//     (hysteresis), then the normal 3 s debounce applies to the way down.
class TierDebouncer {
 public:
  Tier update(Tier rawTier, float ppmComp) {
    changed_ = false;
    if (ppmComp >= TIER_CRITICAL_PPM) {
      setActive(TIER_CRITICAL);
      return active_;
    }
    if (active_ == TIER_CRITICAL && ppmComp > OVERRIDE_CLEAR_PPM) {
      candidate_ = active_;
      count_ = 0;
      return active_;
    }
    if (rawTier == active_) {
      candidate_ = active_;
      count_ = 0;
      return active_;
    }
    if (rawTier == candidate_) {
      count_++;
    } else {
      candidate_ = rawTier;
      count_ = 1;
    }
    if (count_ >= DEBOUNCE_SECONDS) setActive(candidate_);
    return active_;
  }

  Tier active() const { return active_; }
  // True only for the update() call in which the active tier changed.
  bool changed() const { return changed_; }

 private:
  void setActive(Tier t) {
    if (t != active_) changed_ = true;
    active_ = t;
    candidate_ = t;
    count_ = 0;
  }

  Tier active_ = TIER_SAFE;
  Tier candidate_ = TIER_SAFE;
  int count_ = 0;
  bool changed_ = false;
};
