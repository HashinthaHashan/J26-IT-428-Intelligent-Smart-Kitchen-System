// On-device classifier.
//
//  * If you put the micromlgen export "lpg_rf_esp32.h" in this sketch folder, it
//    is detected automatically (__has_include) and the trained Random Forest is
//    used. The class must be Eloquent::ML::Port::RandomForest with
//    int predict(float *x) returning 0/1/2/3 = Safe/Warning/Dangerous/Critical.
//  * If the file is absent, the same rule fallback as the backend is used
//    (ppm_comp <150 Safe, <300 Warning, <700 Dangerous, else Critical) and a
//    warning is printed at boot. The firmware still works standalone.
//
// NEITHER path can lower the hard safety override: apply it AFTER modelPredict().
#pragma once

#include "features.h"
#include "tier_logic.h"

#if defined(__has_include)
#if __has_include("lpg_rf_esp32.h")
#include "lpg_rf_esp32.h"
#define KG_MODEL_TRAINED 1
#endif
#endif
#ifndef KG_MODEL_TRAINED
#define KG_MODEL_TRAINED 0
#endif

inline bool modelIsTrained() { return KG_MODEL_TRAINED == 1; }

inline const char *modelDescription() {
  return KG_MODEL_TRAINED
             ? "trained Random Forest (lpg_rf_esp32.h)"
             : "RULE FALLBACK (lpg_rf_esp32.h not found - not the trained model)";
}

inline Tier modelPredict(const FeatureVector &f) {
#if KG_MODEL_TRAINED
  static Eloquent::ML::Port::RandomForest classifier;
  float x[FEATURE_COUNT];
  f.toArray(x);
  int label = classifier.predict(x);
  if (label < 0) label = 0;
  if (label > 3) label = 3;
  return (Tier)label;
#else
  return tierFromPpmRules(f.ppm_comp);
#endif
}

// Returns the number of failed checks (0 = good).
inline int tierLogicSelfTest() {
  int fails = 0;
  // rules
  fails += tierFromPpmRules(149.9f) != TIER_SAFE;
  fails += tierFromPpmRules(150.0f) != TIER_WARNING;
  fails += tierFromPpmRules(299.9f) != TIER_WARNING;
  fails += tierFromPpmRules(300.0f) != TIER_DANGEROUS;
  fails += tierFromPpmRules(699.9f) != TIER_DANGEROUS;
  fails += tierFromPpmRules(700.0f) != TIER_CRITICAL;
  // override beats a model that says Safe
  fails += applySafetyOverride(TIER_SAFE, 700.0f) != TIER_CRITICAL;
  fails += applySafetyOverride(TIER_SAFE, 699.0f) != TIER_SAFE;

  // debounce: 2 readings are not enough, the 3rd flips the tier
  TierDebouncer d;
  fails += d.update(TIER_DANGEROUS, 400) != TIER_SAFE;
  fails += d.update(TIER_DANGEROUS, 400) != TIER_SAFE;
  fails += d.update(TIER_DANGEROUS, 400) != TIER_DANGEROUS;
  fails += !d.changed();
  // a single noisy Safe reading must not flip it back
  fails += d.update(TIER_SAFE, 100) != TIER_DANGEROUS;
  fails += d.update(TIER_DANGEROUS, 400) != TIER_DANGEROUS;
  // the override is instant (no debounce)
  fails += d.update(TIER_CRITICAL, 750) != TIER_CRITICAL;
  fails += !d.changed();
  // hysteresis: 650 ppm is below 700 but above 630, so Critical is held
  fails += d.update(TIER_DANGEROUS, 650) != TIER_CRITICAL;
  fails += d.update(TIER_DANGEROUS, 650) != TIER_CRITICAL;
  fails += d.update(TIER_DANGEROUS, 650) != TIER_CRITICAL;
  // once <= 630, three consecutive readings are needed to drop
  fails += d.update(TIER_DANGEROUS, 600) != TIER_CRITICAL;
  fails += d.update(TIER_DANGEROUS, 600) != TIER_CRITICAL;
  fails += d.update(TIER_DANGEROUS, 600) != TIER_DANGEROUS;
  return fails;
}
