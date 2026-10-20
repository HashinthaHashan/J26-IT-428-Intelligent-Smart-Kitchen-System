#include <Arduino.h>
#include <string.h>
#include "deterrent.h"
#include "sensors.h"

extern "C" {
int strcmp(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return (unsigned char)*a - (unsigned char)*b; }
size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
void *memset(void *p, int c, size_t n) { unsigned char *d = (unsigned char *)p; while (n--) *d++ = (unsigned char)c; return p; }
void *memcpy(void *d, const void *s, size_t n) { unsigned char *a = (unsigned char *)d; const unsigned char *b = (const unsigned char *)s; while (n--) *a++ = *b++; return d; }
size_t strlcpy(char *dst, const char *src, size_t n) { size_t i = 0; if (n) { for (; i + 1 < n && src[i]; i++) dst[i] = src[i]; dst[i] = 0; } return strlen(src); }
int snprintf(char *b, unsigned long n, const char *, ...) { if (n) { b[0] = 't'; if (n > 1) b[1] = 0; } return 1; }
}

SerialStub Serial;
static unsigned long g_now = 0;
static int g_level[40];
static int g_writes[40][8];  // first writes per pin
static int g_nwrites[40];
static int g_outputAtWrite[40];  // how many writes had happened when the pin became an OUTPUT
void pinMode(int pin, int) { g_outputAtWrite[pin] = g_nwrites[pin]; }
void digitalWrite(int pin, int level) {
  g_level[pin] = level;
  if (g_nwrites[pin] < 8) g_writes[pin][g_nwrites[pin]] = level;
  g_nwrites[pin]++;
}
unsigned long millis() { return g_now; }
static int g_raw[40];  // simulated raw sensor pin levels
int digitalRead(int pin) { return g_raw[pin]; }
// tone()/noTone() recorder: the buzzer is "sounding" while a tone with frequency > 0 is active.
static unsigned g_toneHz[40];
static int g_toneCalls, g_noToneCalls, g_noToneWhileSilent;
void tone(uint8_t pin, unsigned int frequency, unsigned long) { g_toneHz[pin] = frequency; g_toneCalls++; }
void noTone(uint8_t pin) {
  g_noToneCalls++;
  if (g_toneHz[pin] == 0) g_noToneWhileSilent++;  // noTone() with nothing running is wasteful/noisy
  g_toneHz[pin] = 0;
}
uint32_t esp_random() { return 0x1234; }

static const int MOT_ON = MOTOR_ACTIVE_HIGH ? HIGH : LOW;

static long buzFirstOn, buzLastOn, buzTotal, motTotal, ledEdges;
static int buzOnAtStart;

extern "C" {
// Boot: the buzzer pin must be latched OFF before it becomes an output.
int boot_buzzer_is_silent_and_never_digitalwritten() {
  for (int i = 0; i < 40; i++) { g_nwrites[i] = 0; g_level[i] = -1; g_toneHz[i] = 0; }
  g_toneCalls = g_noToneCalls = g_noToneWhileSilent = 0;
  deterrentBegin();
  return g_toneHz[PIN_BUZZER] == 0 && g_nwrites[PIN_BUZZER] == 0 && g_toneCalls == 0 && g_noToneCalls == 0;
}
// Runs one manual trial of condition c on a simulated clock (5 ms ticks) for 60 s.
void run_condition(int c) {
  for (int i = 0; i < 40; i++) { g_nwrites[i] = 0; g_level[i] = -1; g_toneHz[i] = 0; }
  g_toneCalls = g_noToneCalls = g_noToneWhileSilent = 0;
  deterrentBegin();
  buzFirstOn = -1; buzLastOn = -1; buzTotal = 0; motTotal = 0; ledEdges = 0;
  const unsigned long t0 = 1000;
  g_now = t0;
  deterrentManual(t0, (Condition)c, "Sink", 1);
  int lastLed = -1;
  for (unsigned long t = t0; t <= t0 + 60000; t += 5) {
    g_now = t;
    deterrentUpdate(t, true);
    if (g_toneHz[PIN_BUZZER] > 0) {
      if (buzFirstOn < 0) buzFirstOn = (long)(t - t0);
      buzLastOn = (long)(t - t0);
      buzTotal += 5;
    }
    if (g_level[PIN_MOTOR] == MOT_ON) motTotal += 5;
    if (g_level[PIN_LED] != lastLed) { lastLed = g_level[PIN_LED]; ledEdges++; }
  }
}
long get_buz_first() { return buzFirstOn; }
long get_buz_last() { return buzLastOn; }
long get_buz_total() { return buzTotal; }
long get_motor_total() { return motTotal; }
int get_buzzer_level_at_end() { return g_toneHz[PIN_BUZZER] > 0; }
int get_buzzer_digitalwrites() { return g_nwrites[PIN_BUZZER]; }
int get_tone_calls() { return g_toneCalls; }
int get_notone_calls() { return g_noToneCalls; }
int get_notone_while_silent() { return g_noToneWhileSilent; }
unsigned get_tone_hz_used() { return BUZZER_TONE_HZ; }
int uses_buzzer(int c) { return conditionUsesBuzzer((Condition)c); }
int selftest() { return deterrentSelfTest(); }

// ---- trigger -> trial, through the REAL sensor debounce code -------------------------------
static long trigDelayMs, trigMotorOnAt, trigBuzzerOnAt, trigLedAt;
static int trigStarted, trigCondition, trigSecondStartRefused;
static TrialRecord trigFinished;
static int trigHaveFinished, trigAttachDuring, trigAttachAfter, trigAttachNonPest, trigAttachWrongId;

static void setRaw(int pin, bool active, bool activeHigh) { g_raw[pin] = (active == activeHigh) ? HIGH : LOW; }
static void idleAll() {
  setRaw(PIN_PIR, false, PIR_ACTIVE_HIGH);
  setRaw(PIN_IR, false, IR_ACTIVE_HIGH);
  setRaw(PIN_VIB, false, VIB_ACTIVE_HIGH);
}
static unsigned long g_base = 100000;  // past the PIR warm-up

// Raises ONE sensor at a simulated moment; the real Debouncer decides when it fires; the
// firmware's reaction (deterrentStart) is then timed. src: 0 PIR, 1 IR, 2 Vibration.
void run_trigger(int src, int attachSpeciesMidTrial) {
  { TrialRecord stale; while (deterrentTakeFinished(stale)) {} }  // collect any trial left by an earlier scenario
  for (int i = 0; i < 40; i++) { g_nwrites[i] = 0; g_level[i] = -1; g_toneHz[i] = 0; }
  idleAll();
  trigDelayMs = -1; trigMotorOnAt = -1; trigBuzzerOnAt = -1; trigLedAt = -1;
  trigStarted = 0; trigSecondStartRefused = 0; trigHaveFinished = 0;
  trigAttachDuring = trigAttachAfter = trigAttachNonPest = trigAttachWrongId = -1;
  const unsigned long tAct = g_base;  // the moment the sensor pin goes active
  const int pin = src == 0 ? PIN_PIR : (src == 1 ? PIN_IR : PIN_VIB);
  const bool hi = src == 0 ? PIR_ACTIVE_HIGH : (src == 1 ? IR_ACTIVE_HIGH : VIB_ACTIVE_HIGH);
  unsigned long tStart = 0;
  for (unsigned long t = tAct - 100; t <= tAct + 60000; t += 5) {
    g_now = t;
    if (t == tAct) setRaw(pin, true, hi);
    if (t == tAct + 2000) setRaw(pin, false, hi);
    const unsigned fired = sensorsPoll(t);
    if (fired & (1u << src) && !trigStarted) {
      // exactly what handleTrigger() does first: start the trial NOW
      trigStarted = deterrentStart(t, "Sink", "pk-1", 1);
      tStart = t;
      trigDelayMs = (long)(t - tAct);
      trigCondition = -1;
    }
    deterrentUpdate(t, true);
    if (trigStarted && tStart) {
      const long rel = (long)(t - tAct);
      if (trigMotorOnAt < 0 && g_level[PIN_MOTOR] == (MOTOR_ACTIVE_HIGH ? HIGH : LOW)) trigMotorOnAt = rel;
      if (trigBuzzerOnAt < 0 && g_toneHz[PIN_BUZZER] > 0) trigBuzzerOnAt = rel;
      if (trigLedAt < 0 && g_level[PIN_LED] == HIGH && deterrentState() == DS_ACTIVATION) trigLedAt = rel;
      // a second trigger while the trial runs must be refused
      if (t == tStart + 3000) trigSecondStartRefused = !deterrentStart(t, "Sink", "pk-2", 1);
      if (t == tStart + 5000 && attachSpeciesMidTrial) {
        trigAttachWrongId = deterrentAttachSpecies("pk-OTHER", "cockroach");
        trigAttachNonPest = deterrentAttachSpecies("pk-1", "non_pest");
        trigAttachDuring = deterrentAttachSpecies("pk-1", "cockroach");
      }
    }
    TrialRecord rec;
    if (deterrentTakeFinished(rec)) { trigFinished = rec; trigHaveFinished = 1; trigAttachAfter = deterrentAttachSpecies("pk-1", "rat"); break; }
  }
  g_base += 120000;  // next run: well past the cooldown and the previous trial
}
long trig_delay_ms() { return trigDelayMs; }
long trig_motor_at() { return trigMotorOnAt; }
long trig_buzzer_at() { return trigBuzzerOnAt; }
long trig_led_at() { return trigLedAt; }
int trig_started() { return trigStarted; }
int trig_second_refused() { return trigSecondStartRefused; }
int trig_have_finished() { return trigHaveFinished; }
int trig_attach_during() { return trigAttachDuring; }
int trig_attach_after() { return trigAttachAfter; }
int trig_attach_nonpest() { return trigAttachNonPest; }
int trig_attach_wrong_id() { return trigAttachWrongId; }
int trig_finished_species_is_cockroach() { return strcmp(trigFinished.species, "cockroach") == 0; }
int trig_finished_species_empty() { return trigFinished.species[0] == 0; }
int trig_finished_condition() {
  for (int i = 0; i < COND_COUNT; i++) if (strcmp(trigFinished.condition, conditionName((Condition)i)) == 0) return i;
  return -1;
}
}
