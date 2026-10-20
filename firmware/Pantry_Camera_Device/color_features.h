// Colour features from an RGB565 frame. Pure C++ (no Arduino headers) so it can be
// tested on a PC.
//
// Per region of interest it returns:
//   hue_mean   circular mean hue (0-360 degrees) of the "item" pixels
//   brown_pct  % of item pixels that look brown
//   green_pct  % of item pixels that look green
//   coverage   % of the region that are item pixels (used to say "nothing there")
//
// "Item pixels" are the coloured ones: saturation and brightness above a floor, which
// removes a white/grey table and black shadows. This assumes a plain neutral
// background and steady lighting (the sensor board keeps the LED on for this).
#pragma once

#include <math.h>
#include <stdint.h>

#include "config.h"

struct ColorFeatures {
  bool valid;        // false = too few item pixels, nothing measured
  float hueMean;     // degrees 0-360
  float brownPct;    // 0-100
  float greenPct;    // 0-100
  float coveragePct; // 0-100
};

struct RegionPx {
  int x, y, w, h;  // pixel rectangle inside the frame
};

inline RegionPx regionFromFractions(float fx, float fy, float fw, float fh, int frameW, int frameH) {
  RegionPx r;
  r.x = (int)(fx * frameW);
  r.y = (int)(fy * frameH);
  r.w = (int)(fw * frameW);
  r.h = (int)(fh * frameH);
  if (r.x < 0) r.x = 0;
  if (r.y < 0) r.y = 0;
  if (r.x + r.w > frameW) r.w = frameW - r.x;
  if (r.y + r.h > frameH) r.h = frameH - r.y;
  return r;
}

// Decodes one RGB565 pixel (2 bytes) to 0-255 channels.
inline void rgb565ToRgb(const uint8_t *p, bool bigEndian, int &r, int &g, int &b) {
  const uint16_t v = bigEndian ? (uint16_t)((p[0] << 8) | p[1]) : (uint16_t)((p[1] << 8) | p[0]);
  r = ((v >> 11) & 0x1F) * 255 / 31;
  g = ((v >> 5) & 0x3F) * 255 / 63;
  b = (v & 0x1F) * 255 / 31;
}

// RGB 0-255 -> hue degrees (0-360), saturation 0-1, value 0-1.
inline void rgbToHsv(int r, int g, int b, float &h, float &s, float &v) {
  const float rf = r / 255.0f, gf = g / 255.0f, bf = b / 255.0f;
  const float mx = fmaxf(rf, fmaxf(gf, bf));
  const float mn = fminf(rf, fminf(gf, bf));
  const float d = mx - mn;
  v = mx;
  s = mx <= 0.0f ? 0.0f : d / mx;
  if (d <= 1e-6f) {
    h = 0.0f;
    return;
  }
  if (mx == rf) {
    h = 60.0f * fmodf((gf - bf) / d, 6.0f);
  } else if (mx == gf) {
    h = 60.0f * (((bf - rf) / d) + 2.0f);
  } else {
    h = 60.0f * (((rf - gf) / d) + 4.0f);
  }
  if (h < 0.0f) h += 360.0f;
}

inline ColorFeatures computeFeatures(const uint8_t *rgb565, int frameW, int frameH, const RegionPx &roi,
                                     bool bigEndian) {
  ColorFeatures out = {false, 0, 0, 0, 0};
  const int total = roi.w * roi.h;
  if (total <= 0) return out;

  long items = 0, brown = 0, green = 0;
  double sumSin = 0, sumCos = 0;
  for (int y = roi.y; y < roi.y + roi.h; y++) {
    const uint8_t *row = rgb565 + ((size_t)y * frameW + roi.x) * 2;
    for (int x = 0; x < roi.w; x++) {
      int r, g, b;
      rgb565ToRgb(row + x * 2, bigEndian, r, g, b);
      float h, s, v;
      rgbToHsv(r, g, b, h, s, v);
      if (s < ITEM_MIN_SATURATION || v < ITEM_MIN_VALUE) continue;  // table / shadow
      items++;
      const float rad = h * 0.01745329252f;
      sumSin += sinf(rad);
      sumCos += cosf(rad);
      if (h >= BROWN_HUE_MIN && h <= BROWN_HUE_MAX && s >= BROWN_MIN_SATURATION && v <= BROWN_MAX_VALUE) {
        brown++;
      } else if (h >= GREEN_HUE_MIN && h <= GREEN_HUE_MAX && s >= GREEN_MIN_SATURATION) {
        green++;
      }
    }
  }
  out.coveragePct = 100.0f * items / total;
  if (out.coveragePct < ITEM_MIN_COVERAGE_PCT) return out;  // nothing measurable here
  float mean = atan2f((float)sumSin, (float)sumCos) * 57.2957795131f;
  if (mean < 0) mean += 360.0f;
  out.valid = true;
  out.hueMean = mean;
  out.brownPct = 100.0f * brown / items;
  out.greenPct = 100.0f * green / items;
  return out;
}

// ---------------------------------------------------------------------------
// Self-test on synthetic frames. Returns the number of failed checks (0 = good).
// ---------------------------------------------------------------------------
inline void putRgb565(uint8_t *buf, int idx, int r, int g, int b, bool bigEndian) {
  const uint16_t v = (uint16_t)(((r * 31 / 255) << 11) | ((g * 63 / 255) << 5) | (b * 31 / 255));
  if (bigEndian) {
    buf[idx * 2] = v >> 8;
    buf[idx * 2 + 1] = v & 0xFF;
  } else {
    buf[idx * 2] = v & 0xFF;
    buf[idx * 2 + 1] = v >> 8;
  }
}

inline int colorFeaturesSelfTest() {
  enum { W = 16, H = 8 };
  static uint8_t frame[W * H * 2];
  const RegionPx all = {0, 0, W, H};
  int fails = 0;

  for (int endian = 0; endian < 2; endian++) {
    const bool be = endian == 0;
    // All yellow (banana): hue ~60, no brown, no green.
    for (int i = 0; i < W * H; i++) putRgb565(frame, i, 240, 220, 40, be);
    ColorFeatures f = computeFeatures(frame, W, H, all, be);
    fails += !f.valid || fabsf(f.hueMean - 53.0f) > 12.0f || f.brownPct > 1.0f || f.greenPct > 1.0f;

    // All green.
    for (int i = 0; i < W * H; i++) putRgb565(frame, i, 40, 200, 40, be);
    f = computeFeatures(frame, W, H, all, be);
    fails += !f.valid || f.greenPct < 99.0f || f.brownPct > 1.0f;

    // All brown (139, 69, 19).
    for (int i = 0; i < W * H; i++) putRgb565(frame, i, 139, 69, 19, be);
    f = computeFeatures(frame, W, H, all, be);
    fails += !f.valid || f.brownPct < 99.0f || f.greenPct > 1.0f;

    // Grey table only: nothing to measure.
    for (int i = 0; i < W * H; i++) putRgb565(frame, i, 128, 128, 128, be);
    f = computeFeatures(frame, W, H, all, be);
    fails += f.valid;

    // Half brown, half grey table: brown_pct counts item pixels only (100 %),
    // coverage is ~50 %.
    for (int i = 0; i < W * H; i++) {
      if ((i % W) < W / 2) putRgb565(frame, i, 139, 69, 19, be);
      else putRgb565(frame, i, 128, 128, 128, be);
    }
    f = computeFeatures(frame, W, H, all, be);
    fails += !f.valid || f.brownPct < 99.0f || fabsf(f.coveragePct - 50.0f) > 3.0f;

    // Left half yellow / right half green; the left ROI must not see the green.
    for (int i = 0; i < W * H; i++) {
      if ((i % W) < W / 2) putRgb565(frame, i, 240, 220, 40, be);
      else putRgb565(frame, i, 40, 200, 40, be);
    }
    const RegionPx left = {0, 0, W / 2, H};
    f = computeFeatures(frame, W, H, left, be);
    fails += !f.valid || f.greenPct > 1.0f;
  }
  return fails;
}
