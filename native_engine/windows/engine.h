/**
 * @file engine.h
 * @brief Planter Pressure - Optimized Native Python Engine
 *
 * OPTIMIZATIONS:
 * - Path-only communication (no Base64, no raw bytes)
 * - Proper memory management with free_string
 * - Thread-safe design for Isolate usage
 */

#ifndef PLANTER_PRESSURE_ENGINE_H
#define PLANTER_PRESSURE_ENGINE_H

#ifdef _WIN32
#ifdef ENGINE_EXPORTS
        #define ENGINE_API __declspec(dllexport)
    #else
        #define ENGINE_API __declspec(dllimport)
    #endif
#else
#define ENGINE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initialize the Python engine.
 * MUST be called once before any processing.
 *
 * @param python_home Path to Python installation (NULL for system Python)
 * @param script_path Path to process.py script
 * @return 0 on success, non-zero on failure
 */
ENGINE_API int engine_init(const char* python_home, const char* script_path);

/**
 * Check if engine is initialized.
 * @return 1 if initialized, 0 otherwise
 */
ENGINE_API int engine_is_initialized(void);

/**
 * Process an image file.
 *
 * Input JSON: {"input_image_path": "C:/path/input.png"}
 * Output JSON: {"status": "success", "output_image_path": "C:/path/output.png"}
 *
 * @param input_json JSON string with input parameters
 * @return JSON string (MUST be freed with free_string!)
 */
ENGINE_API const char* process_image(const char* input_json);

/**
 * FREE THE RETURNED STRING!
 * Every string returned by process_image MUST be freed.
 *
 * @param str String to free (safe to pass NULL)
 */
ENGINE_API void free_string(const char* str);

/**
 * Shutdown and cleanup.
 * Releases Python interpreter and all resources.
 */
ENGINE_API void engine_shutdown(void);

/**
 * Get last error message.
 * @return Error string (do NOT free)
 */
ENGINE_API const char* engine_get_last_error(void);

/**
 * Get engine version.
 * @return Version string (do NOT free)
 */
ENGINE_API const char* engine_get_version(void);

#ifdef __cplusplus
}
#endif

#endif
