// Local status display: 0.96" I2C SSD1306 128x64 OLED. PURELY informational (demos, viva,
// debugging at the bench). It only draws values the sketch already computed; it never reads
// a sensor, never touches the network and never changes what is published.
// All calls are no-ops when ENABLE_OLED is false or the panel was not found at boot.
#pragma once

#include "mqtt_client.h"  // PantrySample

void displayBegin();  // I2C + panel init + boot splash (call once in setup())
// Redraw with the values just read. `netStage` is netStage(); `warmupLeftS` is the seconds
// of per-boot warm-up still to go (0 once publishing has started).
void displayShow(const PantrySample &s, const char *netStage, uint32_t warmupLeftS);
void displayFault(const char *line1, const char *line2, const char *netStage);
