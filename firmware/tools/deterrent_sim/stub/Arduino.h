#pragma once
#include <stdint.h>
typedef unsigned long size_t;
#define HIGH 1
#define LOW 0
#define OUTPUT 1
#define INPUT 0
#define F(x) x
#define RTC_DATA_ATTR
void pinMode(int pin, int mode);
void digitalWrite(int pin, int level);
int digitalRead(int pin);
unsigned long millis();
void tone(uint8_t pin, unsigned int frequency, unsigned long duration = 0);
void noTone(uint8_t pin);
struct SerialStub {
  void printf(const char *, ...) {}
  void println(const char *) {}
};
extern SerialStub Serial;
uint32_t esp_random();
