/**
 * @file ota_update.h
 * @brief HTTP OTA firmware update endpoint for ESP32-S3 CSI Node.
 *
 * Provides an HTTP server endpoint that accepts firmware binaries
 * for over-the-air updates without physical access to the device.
 */

#ifndef OTA_UPDATE_H
#define OTA_UPDATE_H

#include "esp_err.h"

/**
 * Initialize the OTA update HTTP server.
 * Starts a lightweight HTTP server on port 8032 that accepts
 * POST /ota with a firmware binary payload.
 *
 * @return ESP_OK on success.
 */
esp_err_t ota_update_init(void);

/**
 * Initialize the OTA update HTTP server and return the handle.
 * Same as ota_update_init() but exposes the httpd_handle_t so
 * other modules (e.g. WASM upload) can register additional endpoints.
 *
 * @param out_server  Output: HTTP server handle (may be NULL on failure).
 * @return ESP_OK on success.
 */
esp_err_t ota_update_init_ex(void **out_server);


/** 0.8.7: main.c calls this on Got IP (marks new firmware valid, keeps OTA settings). */
void ota_boot_wifi_ok(void);
/** 0.8.7: main.c calls this when Wi-Fi gives up the boot wait (restores old settings / rolls back). */
void ota_boot_wifi_failed(void);

#endif /* OTA_UPDATE_H */
