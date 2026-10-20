#include "features.h"

#include <math.h>

void FeatureWindow::reset() {
  head_ = 0;
  count_ = 0;
}

void FeatureWindow::push(float ppm, float rhPct) {
  ppm_[head_] = ppm;
  rh_[head_] = rhPct;
  head_ = (head_ + 1) % FEATURE_BUFFER_LEN;
  if (count_ < FEATURE_BUFFER_LEN) count_++;
}

FeatureVector FeatureWindow::compute(float tempC) const {
  FeatureVector f;
  if (count_ == 0) return f;

  const float last = ppmAgo(0);
  // TODO(compensation): the backend does not yet apply MQ-2 temperature/RH
  // compensation either (see lpg_features.py), so ppm_comp == ppm. Keep both
  // sides identical when compensation is added.
  f.ppm_comp = last;
  f.d_ppm_5s = count_ >= 6 ? (last - ppmAgo(5)) / 5.0f : 0.0f;
  f.slope_30s = count_ >= 31 ? (last - ppmAgo(30)) / 30.0f : 0.0f;

  const int n10 = count_ < 10 ? count_ : 10;
  const int n30 = count_ < 30 ? count_ : 30;
  float s10 = 0, s30 = 0;
  for (int k = 0; k < n30; k++) {
    const float v = ppmAgo(k);
    s30 += v;
    if (k < n10) s10 += v;
  }
  f.ma10 = s10 / n10;
  f.ma30 = s30 / n30;

  f.temp_c = tempC;
  f.rh_pct = rhAgo(0);
  f.d_rh_10s = count_ >= 11 ? (rhAgo(0) - rhAgo(10)) / 10.0f : 0.0f;

  if (f.slope_30s > 0.05f) {
    float t = (700.0f - last) / fmaxf(f.slope_30s, 0.05f);
    if (t < 0) t = 0;
    if (t > 3600) t = 3600;
    f.tt700_s = t;
  } else {
    f.tt700_s = 3600.0f;
  }
  return f;
}

// ---------------------------------------------------------------------------
// Self test. Expected values come from backend compute_features().
// ---------------------------------------------------------------------------
static int checks(const char *name, const FeatureVector &f, float ppm_comp,
                  float d5, float slope, float ma10, float ma30, float dRh,
                  float tt700) {
  (void)name;
  auto bad = [](float a, float b) { return fabsf(a - b) > 1e-3f; };
  int fails = 0;
  fails += bad(f.ppm_comp, ppm_comp);
  fails += bad(f.d_ppm_5s, d5);
  fails += bad(f.slope_30s, slope);
  fails += bad(f.ma10, ma10);
  fails += bad(f.ma30, ma30);
  fails += bad(f.d_rh_10s, dRh);
  fails += bad(f.tt700_s, tt700);
  return fails;
}

int featuresSelfTest() {
  int fails = 0;
  FeatureWindow w;

  // ramp: ppm = 100 + 2i, rh = 50 + 0.1i, 31 samples
  for (int i = 0; i < 31; i++) w.push(100.0f + 2.0f * i, 50.0f + 0.1f * i);
  fails += checks("ramp", w.compute(25), 160, 2.0f, 2.0f, 151, 131, 0.1f, 270);

  // flat 100 ppm: slope 0 -> tt700 = 3600
  w.reset();
  for (int i = 0; i < 31; i++) w.push(100.0f, 60.0f);
  fails += checks("flat", w.compute(25), 100, 0, 0, 100, 100, 0, 3600);

  // only 3 samples: deltas 0, averages over what exists
  w.reset();
  w.push(100, 50);
  w.push(110, 50);
  w.push(120, 50);
  fails += checks("short3", w.compute(25), 120, 0, 0, 110, 110, 0, 3600);

  // already past 700 ppm and rising: tt700 clips to 0
  w.reset();
  for (int i = 0; i < 31; i++) w.push(500.0f + 10.0f * i, 50.0f);
  fails += checks("over700", w.compute(25), 800, 10, 10, 755, 655, 0, 0);

  // 20 samples: d_ppm_5s and d_rh_10s exist, slope_30s does not yet
  w.reset();
  for (int i = 0; i < 20; i++) w.push(100.0f + 2.0f * i, 50.0f + 0.1f * i);
  fails += checks("ramp20", w.compute(25), 138, 2.0f, 0, 129, 119, 0.1f, 3600);

  // buffer wrap-around: 70 pushes must give the same answer as the last 31
  w.reset();
  for (int i = 0; i < 70; i++) w.push(100.0f + 2.0f * i, 50.0f + 0.1f * i);
  fails += checks("wrap", w.compute(25), 238, 2.0f, 2.0f, 229, 209, 0.1f, 231);

  // feature order
  FeatureVector f;
  f.ppm_comp = 1; f.d_ppm_5s = 2; f.slope_30s = 3; f.ma10 = 4; f.ma30 = 5;
  f.temp_c = 6; f.rh_pct = 7; f.d_rh_10s = 8; f.tt700_s = 9;
  float a[FEATURE_COUNT];
  f.toArray(a);
  for (int i = 0; i < FEATURE_COUNT; i++) fails += (a[i] != (float)(i + 1));
  return fails;
}
