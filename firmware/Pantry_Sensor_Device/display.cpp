#include "display.h"

#include <Arduino.h>

#include "config.h"

#if ENABLE_OLED

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Wire.h>

static Adafruit_SSD1306 oled(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
static bool ready = false;

// Short label for the top-right corner, derived from the existing netStage() string
// ("ONLINE" | "OFFLINE(mqtt)" | "OFFLINE(wifi)"); no connection logic is duplicated here.
static const char *netLabel(const char *stage) {
  if (strcmp(stage, "ONLINE") == 0) return "ONLINE";
  if (strstr(stage, "wifi")) return "NO WIFI";
  if (strstr(stage, "mqtt")) return "NO MQTT";
  return "OFFLINE";
}

static void header(const char *left, const char *stage) {
  oled.fillRect(0, 0, OLED_WIDTH, 11, SSD1306_WHITE);
  oled.setTextSize(1);
  oled.setTextColor(SSD1306_BLACK);
  oled.setCursor(2, 2);
  oled.print(left);
  const char *r = netLabel(stage);
  oled.setCursor(OLED_WIDTH - 2 - 6 * (int)strlen(r), 2);
  oled.print(r);
  oled.setTextColor(SSD1306_WHITE);
}

// <= 5 characters so it fits a size-2 column (12 px per glyph, 64 px wide).
static void fmtPpm(char *buf, size_t n, float v) {
  if (v < 100.0f) snprintf(buf, n, "%.1f", v);
  else snprintf(buf, n, "%.0f", v);
}

static void value(int x, const char *label, float v) {
  char b[12];
  fmtPpm(b, sizeof b, v);
  oled.setTextSize(1);
  oled.setCursor(x, 15);
  oled.print(label);
  oled.setTextSize(2);
  oled.setCursor(x, 25);
  oled.print(b);
  oled.setTextSize(1);
  oled.setCursor(x, 42);
  oled.print(F("ppm"));
}

void displayBegin() {
  Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
  Wire.setClock(OLED_I2C_HZ);
  if (!oled.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR)) {
    Serial.printf("[OLED] panel not found at 0x%02X (SDA GPIO%d, SCL GPIO%d). Display disabled; "
                  "sensing and publishing are unaffected. Check wiring/VCC 3.3 V, or try 0x3D.\n",
                  OLED_I2C_ADDR, PIN_OLED_SDA, PIN_OLED_SCL);
    return;
  }
  ready = true;
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  oled.setTextSize(2);
  oled.setCursor(10, 8);
  oled.print(F("KitchenGuard"));
  oled.setTextSize(1);
  oled.setCursor(16, 32);
  oled.print(F("Smart Pantry sensors"));
  oled.setCursor(16, 46);
  oled.print(F(DEVICE_ID));
  oled.display();
  Serial.printf("[OLED] SSD1306 %dx%d ready at 0x%02X (SDA GPIO%d, SCL GPIO%d, %lu Hz)\n", OLED_WIDTH,
                OLED_HEIGHT, OLED_I2C_ADDR, PIN_OLED_SDA, PIN_OLED_SCL, (unsigned long)OLED_I2C_HZ);
}

void displayShow(const PantrySample &s, const char *stage, uint32_t warmupLeftS) {
  if (!ready) return;
  oled.clearDisplay();
  char title[20];
  if (warmupLeftS > 0) snprintf(title, sizeof title, "WARM-UP %us", (unsigned)warmupLeftS);
  else snprintf(title, sizeof title, "PANTRY");
  header(title, stage);
  value(2, "MQ-3", s.mq3Ppm);
  value(68, "MQ-135", s.mq135Ppm);
  oled.drawFastVLine(63, 13, 37, SSD1306_WHITE);
  oled.drawFastHLine(0, 51, OLED_WIDTH, SSD1306_WHITE);
  char t[16], h[16];
  snprintf(t, sizeof t, "T %.1f C", s.tempC);
  snprintf(h, sizeof h, "RH %.0f %%", s.rhPct);
  oled.setTextSize(1);
  oled.setCursor(2, 55);
  oled.print(t);
  oled.setCursor(OLED_WIDTH - 2 - 6 * (int)strlen(h), 55);
  oled.print(h);
  oled.display();  // ~25 ms at 400 kHz, once per sensor cycle, on the Arduino loop task only
}

void displayFault(const char *line1, const char *line2, const char *stage) {
  if (!ready) return;
  oled.clearDisplay();
  header("SENSOR FAULT", stage);
  oled.setTextSize(1);
  oled.setCursor(2, 20);
  oled.print(line1);
  oled.setCursor(2, 32);
  oled.print(line2);
  oled.setCursor(2, 54);
  oled.print(F("Nothing published"));
  oled.display();
}

#else

void displayBegin() {}
void displayShow(const PantrySample &, const char *, uint32_t) {}
void displayFault(const char *, const char *, const char *) {}

#endif
