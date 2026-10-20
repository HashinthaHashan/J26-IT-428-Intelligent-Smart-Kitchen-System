// =============================================================================
// KitchenGuard - Component 03 (Pest detection) - BOARD 2: ESP32-CAM
// Reacts to photo requests only; it has no sensors of its own.
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
// NOT 127.0.0.1. Re-check it whenever the laptop reconnects (DHCP can change it).
#define MQTT_HOST "192.168.1.100"  // TODO
#define MQTT_PORT 1883
#define MQTT_USER ""
#define MQTT_PASS ""

// Photos go to the backend over HTTP (an image is far too large for a clean MQTT
// message). Same laptop as the broker. Needs inbound TCP 8000 allowed in Windows
// Firewall and the API bound to 0.0.0.0 (scripts/dev_stack.ps1 checks both).
#define API_HOST MQTT_HOST
#define API_PORT 8000
#define API_TOKEN "dev-token"  // the backend's DEV_API_TOKEN
#define HTTP_TIMEOUT_MS 6000

// -----------------------------------------------------------------------------
// IDENTITY / TOPICS
// This board is the CAMERA half of the logical device "pest-kitchen01". It has its
// own MQTT client id and its own retained status topic (the sensor board owns
// .../status), and it never talks to the sensor board directly: the backend relays
// capture requests to it.
// -----------------------------------------------------------------------------
#define DEVICE_ID "pest-kitchen01"
#define TOPIC_CAPTURE "kitchenguard/pest/" DEVICE_ID "/capture"            // backend -> this board
#define TOPIC_CAPTURE_DONE "kitchenguard/pest/" DEVICE_ID "/capture_done"  // this board -> backend
#define TOPIC_STATUS "kitchenguard/pest/" DEVICE_ID "/camera_status"       // retained + Last Will
#define API_PHOTO_PATH "/api/pest/" DEVICE_ID "/photo"
#define SCHEMA_VERSION 1

// -----------------------------------------------------------------------------
// SENSOR VARIANT  (OV2640 vs RHYX-M21-45)  - the one setting to change if the
// camera misbehaves
// -----------------------------------------------------------------------------
// Suppliers substitute the RHYX-M21-45 for the OV2640 without notice. The RHYX
// fails on JPEG at larger sizes (init failure, empty/garbled frames, out of memory).
//   false (default)  OV2640: capture JPEG at VGA 640x480, upload the JPEG.
//   true             RHYX-M21-45: capture RGB565 at QVGA 320x240 and upload it
//                    UNCOMPRESSED (153,600 bytes); the upload carries
//                    X-Image-Format: rgb565 so the backend can size-check it.
// If boot shows "camera init FAILED" or "not a valid JPEG", set this to true.
#define CAMERA_USE_RGB565 false

#if CAMERA_USE_RGB565
#define CAMERA_FRAMESIZE FRAMESIZE_QVGA
#else
#define CAMERA_FRAMESIZE FRAMESIZE_VGA
#endif
#define CAMERA_JPEG_QUALITY 12  // 10 = best, 63 = worst (OV2640 JPEG path only)

// Frames thrown away before the one that is sent. 1 keeps the answer fast; raise to
// 2 or 3 if photos come out too dark/bright after a long idle.
#define WARMUP_FRAMES 1

// Never take two photos closer together than this (a burst of triggers).
#define MIN_CAPTURE_GAP_MS 1500
// A capture order older than this is dropped: the trial it belonged to is long over
// by the time a photo this late would be classified.
#define MAX_ORDER_AGE_MS 5000

// The AI-Thinker's built-in white flash LED (GPIO4). OFF by default: a pest
// photo normally uses the room light, and a sudden flash may scare the animal.
// Set true to light the scene for each photo (the LED is on only while capturing).
#define USE_FLASH_LED false
#define PIN_FLASH_LED 4

// -----------------------------------------------------------------------------
// RETRY
// -----------------------------------------------------------------------------
#define WIFI_RETRY_MS 10000
#define MQTT_RETRY_MS 5000
