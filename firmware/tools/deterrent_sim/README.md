# Deterrent timing simulation (no hardware needed)

Compiles the REAL `firmware/Pest_Sensor_Device/deterrent.cpp` to WebAssembly against a fake
Arduino layer (a simulated clock and a recorder of every pin write), runs one trial per
condition, and checks the motor/LED/buzzer timing: for example that the buzzer (tone()/noTone(), never digitalWrite) sounds for
exactly `ACTIVATION_S` and is off afterwards, and that it is latched OFF at boot.

Needs a clang with the `wasm32` target (the Android NDK's clang has it) and Node.js:

```bash
CLANG=/c/Android/ndk/27.1.12297006/toolchains/llvm/prebuilt/windows-x86_64/bin/clang++.exe
cd firmware/tools/deterrent_sim
$CLANG --target=wasm32 -O1 -std=c++17 -nostdlib -ffreestanding -fno-exceptions -fno-rtti \
  -I stub -I ../../Pest_Sensor_Device -Wl,--no-entry -Wl,--export-all \
  -o deterrent_sim.wasm harness.cpp ../../Pest_Sensor_Device/deterrent.cpp
node run.js
```

It exercises the logic only; it cannot tell you whether the buzzer is wired or its polarity is
right (use `HARDWARE_TEST_MODE` for that). Re-run it after changing `config.h` timings or the
buzzer mapping: `run.js` expects the default `BUZZER_ON_CONDITIONS 12` (led_only + vibration_led).
