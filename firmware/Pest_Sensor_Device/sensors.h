// Debounced PIR / IR / vibration triggers. The debouncer is pure C++ (no Arduino
// headers) so it can be tested on a PC.
#pragma once

#include <stdint.h>

#include "config.h"

enum TriggerSource : uint8_t { SRC_PIR = 0, SRC_IR = 1, SRC_VIB = 2, SRC_COUNT = 3 };

inline const char *triggerName(TriggerSource s) {
  switch (s) {
    case SRC_PIR: return "PIR";
    case SRC_IR: return "IR";
    default: return "Vibration";
  }
}

// One sensor. Fires ONCE when the input has been continuously active for
// DEBOUNCE_MS; then stays quiet for COOLDOWN_MS; and it must go inactive before it
// can fire again (a stuck-high sensor fires once, not every 8 s).
class Debouncer {
 public:
  // `active` = the pin currently reads its active level. Returns true on the
  // sample where a trigger is published.
  bool update(bool active, uint32_t nowMs, uint32_t debounceMs, uint32_t cooldownMs) {
    if (!active) {
      activeSince_ = 0;
      armed_ = true;
      return false;
    }
    if (!armed_) return false;  // still the same activity that already fired
    if (activeSince_ == 0) activeSince_ = nowMs ? nowMs : 1;
    if (nowMs - activeSince_ < debounceMs) return false;
    if (everFired_ && nowMs - lastFire_ < cooldownMs) return false;  // cooling down
    lastFire_ = nowMs;
    everFired_ = true;
    armed_ = false;  // wait for the input to go inactive
    return true;
  }

 private:
  uint32_t activeSince_ = 0;
  uint32_t lastFire_ = 0;
  bool armed_ = true;
  bool everFired_ = false;
};

// Raw levels as read right now (true = the pin is at its ACTIVE level).
struct SensorLevels {
  bool pir, ir, vib;
};

void sensorsBegin();
SensorLevels sensorsRead();
// Raw pin levels (1/0), ignoring polarity, for HARDWARE_TEST_MODE.
void sensorsRawLevels(int &pir, int &ir, int &vib);

// Polls all three sensors. Returns a bitmask of TriggerSource bits that published a
// trigger on this call (usually 0).
uint8_t sensorsPoll(uint32_t nowMs);

// Returns the number of failed checks (0 = good).
int sensorsSelfTest();
