/**
 * @file engine.cpp
 * @brief Planter Pressure - Optimized Native Python Engine
 *
 * OPTIMIZATIONS:
 * - Minimal memory allocations
 * - Proper GIL handling for thread safety
 * - Clean error propagation
 * - No data copying - path-only communication
 */

#define PY_SSIZE_T_CLEAN
#include <Python.h>

#include <string>
#include <mutex>
#include <cstring>
#include <cstdlib>
#include <cstdio>

#ifdef _WIN32
#include <windows.h>
#endif

#include "engine.h"

static const char* ENGINE_VERSION = "2.0.0-optimized";

// =============================================================================
// Global State (Thread-Safe)
// =============================================================================

namespace {

    struct EngineState {
        bool initialized = false;
        PyObject* py_module = nullptr;
        PyObject* py_process_func = nullptr;
        std::string last_error;
        std::mutex mutex;
    };

    EngineState g_state;

    void set_error(const std::string& error) {
        g_state.last_error = error;
    }

    std::string get_python_error() {
        if (!PyErr_Occurred()) {
            return "Unknown Python error";
        }

        PyObject *type, *value, *traceback;
        PyErr_Fetch(&type, &value, &traceback);
        PyErr_NormalizeException(&type, &value, &traceback);

        std::string error_msg = "Python error";

        if (value) {
            PyObject* str_obj = PyObject_Str(value);
            if (str_obj) {
                const char* str = PyUnicode_AsUTF8(str_obj);
                if (str) {
                    error_msg = str;
                }
                Py_DECREF(str_obj);
            }
        }

        Py_XDECREF(type);
        Py_XDECREF(value);
        Py_XDECREF(traceback);
        PyErr_Clear();

        return error_msg;
    }

// Allocate string that caller must free
    char* alloc_string(const std::string& str) {
        size_t len = str.length() + 1;
        char* result = static_cast<char*>(malloc(len));
        if (result) {
            memcpy(result, str.c_str(), len);
        }
        return result;
    }

    std::string make_error_json(const std::string& error) {
        std::string escaped;
        escaped.reserve(error.size() + 20);
        for (char c : error) {
            switch (c) {
                case '"': escaped += "\\\""; break;
                case '\\': escaped += "\\\\"; break;
                case '\n': escaped += "\\n"; break;
                case '\r': escaped += "\\r"; break;
                case '\t': escaped += "\\t"; break;
                default: escaped += c;
            }
        }
        return "{\"status\":\"error\",\"error\":\"" + escaped + "\"}";
    }

    bool load_python_from_zip(const char* zip_path) {
        // Add zip path to sys.path
        PyObject* sys_path = PySys_GetObject("path");
        if (sys_path) {
            PyObject* zip_str = PyUnicode_FromString(zip_path);
            if (zip_str) {
                // Insert at beginning to take precedence
                PyList_Insert(sys_path, 0, zip_str);
                Py_DECREF(zip_str);
            }
        }

        // Import the module (compiled inside the zip)
        // The module name matches the .pyc filename inside the zip (image_processor.pyc -> image_processor)
        g_state.py_module = PyImport_ImportModule("image_processor");

        if (!g_state.py_module) {
            set_error("Module import error: " + get_python_error());
            return false;
        }

        g_state.py_process_func = PyObject_GetAttrString(g_state.py_module, "process_image_json");

        if (!g_state.py_process_func || !PyCallable_Check(g_state.py_process_func)) {
            set_error("Missing 'process_image_json' function in module");
            Py_XDECREF(g_state.py_process_func);
            g_state.py_process_func = nullptr;
            return false;
        }

        return true;
    }

} // anonymous namespace

// =============================================================================
// Public API
// =============================================================================

extern "C" {

ENGINE_API int engine_init(const char* python_home, const char* assets_path) {
    std::lock_guard<std::mutex> lock(g_state.mutex);

    if (g_state.initialized) {
        set_error("Already initialized");
        return 1;
    }

    if (!assets_path) {
        set_error("Assets path required");
        return 3;
    }

    // Set Python home
    static std::wstring wide_home;
    if (python_home && python_home[0] != '\0') {
#ifdef _WIN32
        int len = MultiByteToWideChar(CP_UTF8, 0, python_home, -1, nullptr, 0);
        wide_home.resize(len);
        MultiByteToWideChar(CP_UTF8, 0, python_home, -1, &wide_home[0], len);
        Py_SetPythonHome(&wide_home[0]);
#endif
    }

    // Initialize Python
    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    config.isolated = 0;
    config.site_import = 1;
    config.write_bytecode = 0; // Disable writing .pyc files to disk

    PyStatus status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);

    if (PyStatus_Exception(status) || !Py_IsInitialized()) {
        set_error("Python init failed");
        return 2;
    }

    // Construct path to app_modules.zip
    std::string zip_path = std::string(assets_path) + "/app_modules.zip";

    if (!load_python_from_zip(zip_path.c_str())) {
        Py_FinalizeEx();
        return 3;
    }

    g_state.initialized = true;
    return 0;
}

ENGINE_API int engine_is_initialized(void) {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    return g_state.initialized ? 1 : 0;
}

ENGINE_API const char* process_image(const char* input_json) {
    std::lock_guard<std::mutex> lock(g_state.mutex);

    if (!g_state.initialized) {
        return alloc_string(make_error_json("Engine not initialized"));
    }

    if (!input_json) {
        return alloc_string(make_error_json("Null input"));
    }

    if (!g_state.py_process_func) {
        return alloc_string(make_error_json("No process function"));
    }

    // Acquire GIL for thread safety
    PyGILState_STATE gstate = PyGILState_Ensure();

    PyObject* py_input = PyUnicode_FromString(input_json);
    if (!py_input) {
        std::string err = get_python_error();
        PyGILState_Release(gstate);
        return alloc_string(make_error_json(err));
    }

    PyObject* py_result = PyObject_CallFunctionObjArgs(
            g_state.py_process_func, py_input, nullptr
    );
    Py_DECREF(py_input);

    if (!py_result) {
        std::string err = get_python_error();
        PyGILState_Release(gstate);
        return alloc_string(make_error_json(err));
    }

    const char* result_str = PyUnicode_AsUTF8(py_result);
    char* result_copy = nullptr;

    if (result_str) {
        result_copy = alloc_string(result_str);
    } else {
        result_copy = alloc_string(make_error_json("Result conversion failed"));
    }

    Py_DECREF(py_result);
    PyGILState_Release(gstate);

    return result_copy;
}

ENGINE_API void free_string(const char* str) {
    if (str) {
        free(const_cast<char*>(str));
    }
}

ENGINE_API void engine_shutdown(void) {
    std::lock_guard<std::mutex> lock(g_state.mutex);

    if (!g_state.initialized) return;

    Py_XDECREF(g_state.py_process_func);
    Py_XDECREF(g_state.py_module);
    g_state.py_process_func = nullptr;
    g_state.py_module = nullptr;

    if (Py_IsInitialized()) {
        Py_FinalizeEx();
    }

    g_state.initialized = false;
}

ENGINE_API const char* engine_get_last_error(void) {
    return g_state.last_error.c_str();
}

ENGINE_API const char* engine_get_version(void) {
    return ENGINE_VERSION;
}

} // extern "C"

#ifdef _WIN32
BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
    } else if (reason == DLL_PROCESS_DETACH && lpReserved == nullptr) {
        engine_shutdown();
    }
    return TRUE;
}
#endif
