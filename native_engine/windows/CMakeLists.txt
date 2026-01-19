# ==============================================================================
# Planter Pressure - Optimized Native Engine Build
# ==============================================================================

cmake_minimum_required(VERSION 3.16)
project(PlanterPressureEngine VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# Find Python
set(PYTHON_PATHS
        "C:/Users/adit/AppData/Local/Programs/Python/Python312"
        "C:/Python312"
        "C:/Python311"
)

foreach(PYTHON_PATH ${PYTHON_PATHS})
    if(EXISTS "${PYTHON_PATH}/python.exe")
        set(Python3_ROOT_DIR "${PYTHON_PATH}")
        break()
    endif()
endforeach()

find_package(Python3 3.10 REQUIRED COMPONENTS Interpreter Development)

message(STATUS "Python: ${Python3_VERSION} at ${Python3_EXECUTABLE}")

# Build DLL
add_library(image_processor_engine SHARED engine.cpp engine.h)

target_compile_definitions(image_processor_engine PRIVATE
        ENGINE_EXPORTS
        NOMINMAX
        WIN32_LEAN_AND_MEAN
)

target_include_directories(image_processor_engine PRIVATE
        ${Python3_INCLUDE_DIRS}
)

target_link_libraries(image_processor_engine PRIVATE
        ${Python3_LIBRARIES}
)

if(MSVC)
    target_compile_options(image_processor_engine PRIVATE /W3 /utf-8 /EHsc /O2)
endif()

# Build Python Assets (Compile & Zip)
find_package(Python3 3.10 REQUIRED COMPONENTS Interpreter)

# Path to build_assets.py
set(BUILD_ASSETS_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../build_assets.py")
set(PYTHON_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../../python/process.py")
set(ASSETS_OUTPUT_DIR "${CMAKE_BINARY_DIR}/assets")

add_custom_command(
    OUTPUT "${ASSETS_OUTPUT_DIR}/app_modules.zip"
    COMMAND ${Python3_EXECUTABLE} "${BUILD_ASSETS_SCRIPT}" "${PYTHON_SOURCE}" "${ASSETS_OUTPUT_DIR}"
    DEPENDS "${PYTHON_SOURCE}" "${BUILD_ASSETS_SCRIPT}"
    COMMENT "Compiling and zipping Python assets..."
)

add_custom_target(build_python_assets ALL DEPENDS "${ASSETS_OUTPUT_DIR}/app_modules.zip")
add_dependencies(image_processor_engine build_python_assets)

# Copy Python DLLs and Assets
if(WIN32)
    get_filename_component(PYTHON_ROOT "${Python3_EXECUTABLE}" DIRECTORY)
    file(GLOB PYTHON_DLLS "${PYTHON_ROOT}/python3*.dll")
    foreach(DLL ${PYTHON_DLLS})
        add_custom_command(TARGET image_processor_engine POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different "${DLL}" "$<TARGET_FILE_DIR:image_processor_engine>"
        )
    endforeach()
    
    # Copy app_modules.zip to output directory
    add_custom_command(TARGET image_processor_engine POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different "${ASSETS_OUTPUT_DIR}/app_modules.zip" "$<TARGET_FILE_DIR:image_processor_engine>"
    )
endif()
