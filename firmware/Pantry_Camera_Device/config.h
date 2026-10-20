// =============================================================================
// KitchenGuard - Component 02 (Smart Pantry) - BOARD 2: ESP32-CAM (camera only)
// Everything you are expected to edit lives in this file.
// =============================================================================
#pragma once

// -----------------------------------------------------------------------------
// NETWORK  (TODO: fill in)
// -----------------------------------------------------------------------------
// The ESP32 radio is 2.4 GHz ONLY. A network named "...5G..." will not be seen.
#define WIFI_SSID "YOUR_WIFI_SSID"          // TODO
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"  // TODO

// LAN IPv4 of the laptop running the backend/broker (from `ipconfig`).
#define MQTT_HOST "192.168.1.100"  // TODO
#define MQTT_PORT 1883
#define MQTT_USER ""
#define MQTT_PASS ""

// -----------------------------------------------------------------------------
// IDENTITY / TOPICS
// This board is the CAMERA half of the logical device "pantry01". It is a
// separate physical device with its own WiFi/MQTT connection, so its MQTT client id
// and status topic are distinct from the sensor board's.
// -----------------------------------------------------------------------------
#define DEVICE_ID "pantry01"
#define TOPIC_CAMERA "kitchenguard/pantry/" DEVICE_ID "/camera"
// Retained online/offline for THIS board (the sensor board owns .../status).
#define TOPIC_STATUS "kitchenguard/pantry/" DEVICE_ID "/camera_status"
#define SCHEMA_VERSION 1

// -----------------------------------------------------------------------------
// CAPTURE
// -----------------------------------------------------------------------------
#define CAPTURE_INTERVAL_S 300  // one photo every 5 minutes
// Frames discarded before the one that is measured (auto-exposure/white balance
// need a few frames to settle after the LED/lighting is on).
#define WARMUP_FRAMES 3
#define FIRST_CAPTURE_DELAY_S 20  // after boot, before the first capture

// -----------------------------------------------------------------------------
// SENSOR VARIANT  (OV2640 vs RHYX-M21-45)  - the one setting to change if the
// camera misbehaves
// -----------------------------------------------------------------------------
// Suppliers substitute the RHYX-M21-45 for the OV2640 without notice. They look
// alike but the RHYX variant fails on JPEG at larger sizes ("Camera capture
// failed", garbage, or out-of-memory).
//   false (default)  OV2640: capture JPEG, decode on the chip.
//   true             RHYX-M21-45: capture RGB565 directly (no JPEG).
// If you see "camera init failed" or empty/garbled JPEG frames, set this to true.
#define CAMERA_USE_RGB565 false

// QVGA 320x240 keeps memory low on both variants. Do not raise it for the RHYX.
#define CAMERA_FRAMESIZE FRAMESIZE_QVGA
#define CAMERA_FRAME_W 320
#define CAMERA_FRAME_H 240
#define CAMERA_JPEG_QUALITY 12  // 10 = best, 63 = worst (OV2640 JPEG path only)

// RGB565 byte order of the decoded/captured frame. Both camera paths deliver
// big-endian. If colours look swapped (yellow shows as blue/purple), flip this.
#define CAMERA_RGB565_BIG_ENDIAN true

// -----------------------------------------------------------------------------
// ITEM REGIONS (OPEN DESIGN DECISION - see README "Banana vs potato")
// -----------------------------------------------------------------------------
// The camera sees both items in one frame. true = measure two fixed regions, the
// banana on the LEFT and the potato on the RIGHT (you must place them there).
// false = one combined measurement for the whole frame, reported for both items.
#define ROI_SPLIT true

// Regions as fractions of the frame (x, y, width, height), 0.0 to 1.0.
// Check them on the setup page (http://<board-ip>/) and adjust.
#define ROI_BANANA_X 0.03f
#define ROI_BANANA_Y 0.10f
#define ROI_BANANA_W 0.44f
#define ROI_BANANA_H 0.80f
#define ROI_POTATO_X 0.53f
#define ROI_POTATO_Y 0.10f
#define ROI_POTATO_W 0.44f
#define ROI_POTATO_H 0.80f

// Setup page: live view with the regions drawn on it. LAN only, no password.
// Set false to switch the web server off once the camera is aimed.
#define ENABLE_SETUP_WEB true

// -----------------------------------------------------------------------------
// COLOUR CLASSIFICATION (UNTUNED PLACEHOLDERS - tune with the setup page)
// -----------------------------------------------------------------------------
// "Item pixels" are the coloured ones: not white/grey table, not black shadow.
#define ITEM_MIN_SATURATION 0.25f
#define ITEM_MIN_VALUE 0.18f
// Need at least this share of a region to be item pixels, else "nothing there".
#define ITEM_MIN_COVERAGE_PCT 4.0f
// Brown (bruises/rot): orange-brown hue, dark and fairly saturated.
#define BROWN_HUE_MIN 8.0f
#define BROWN_HUE_MAX 45.0f
#define BROWN_MIN_SATURATION 0.30f
#define BROWN_MAX_VALUE 0.62f
// Green (unripe banana peel, sprouts): green hue.
#define GREEN_HUE_MIN 65.0f
#define GREEN_HUE_MAX 170.0f
#define GREEN_MIN_SATURATION 0.25f

// -----------------------------------------------------------------------------
// NETWORK QUEUES / RETRY
// -----------------------------------------------------------------------------
#define QUEUE_LEN 12  // 1 hour of 5-minute captures kept while offline
#define WIFI_RETRY_MS 10000
#define MQTT_RETRY_MS 5000

#define RUN_SELFTEST true
