cmake_minimum_required(VERSION 3.16)
project(edgemind_core VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# =============================================================================
# Options
# =============================================================================

option(MNN_AVAILABLE "Build with MNN library support" ON)
option(BUILD_SHARED_LIBS "Build shared library" ON)
option(EDGEMIND_ENABLE_ZVEC "Build with Zvec native vector DB" OFF)

if(ANDROID AND NOT "${ANDROID_ABI}" STREQUAL "arm64-v8a")
    message(STATUS "Disabling MNN features for Android ABI ${ANDROID_ABI}; bundled native AI binaries are arm64-v8a only")
    set(MNN_AVAILABLE OFF)
    if(EDGEMIND_ENABLE_ZVEC)
        message(STATUS "Disabling Zvec for Android ABI ${ANDROID_ABI}; bundled zvec binaries are arm64-v8a only")
        set(EDGEMIND_ENABLE_ZVEC OFF)
    endif()
endif()

set(MNN_BUNDLED_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/mnn/source")
set(MNN_UPSTREAM_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/mnn/source-upstream")
set(MNN_ANDROID_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/mnn/android-install/arm64-v8a")
if(EXISTS "${MNN_UPSTREAM_SOURCE_DIR}/cmake/macros.cmake")
    set(MNN_SOURCE_DIR "${MNN_UPSTREAM_SOURCE_DIR}")
else()
    set(MNN_SOURCE_DIR "${MNN_BUNDLED_SOURCE_DIR}")
endif()

# =============================================================================
# Find MNN (if available)
# =============================================================================

if(MNN_AVAILABLE)
    if(ANDROID)
        # We manually downloaded MNN for Android
        set(MNN_INCLUDE_DIR "${MNN_SOURCE_DIR}/include")
        set(MNN_ALIGNED_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/mnn/android-install/arm64-v8a/lib")
        if(EXISTS "${MNN_ALIGNED_LIB_DIR}/libMNN.so")
            set(MNN_LIB_DIR "${MNN_ALIGNED_LIB_DIR}")
            message(STATUS "Using source-built 16 KB-compatible MNN for Android")
        else()
            set(MNN_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/mnn/mnn_3.4.1_android_armv7_armv8_cpu_opencl_vulkan/arm64-v8a")
            message(WARNING "Using legacy prebuilt MNN for Android; release builds should rebuild MNN for 16 KB page support")
        endif()
        set(MNN_LIBRARY MNN MNN_Express mnncore llm)
        set(MNN_FOUND TRUE)
    else()
        find_package(MNN QUIET)
        if(NOT MNN_FOUND)
            # Try to find MNN in common locations
            find_path(MNN_INCLUDE_DIR
                NAMES MNN/Interpreter.hpp MNN/MNNDefine.h
                HINTS
                    ${MNN_ROOT}/include
                    $ENV{MNN_ROOT}/include
                    /usr/local/include
                    /usr/include
            )
            
            find_library(MNN_LIBRARY
                NAMES MNN libMNN
                HINTS
                    ${MNN_ROOT}/lib
                    $ENV{MNN_ROOT}/lib
                    /usr/local/lib
                    /usr/lib
            )
            
            if(MNN_INCLUDE_DIR AND MNN_LIBRARY)
                set(MNN_FOUND TRUE)
                message(STATUS "Found MNN: ${MNN_LIBRARY}")
                message(STATUS "MNN include: ${MNN_INCLUDE_DIR}")
            else()
                message(WARNING "MNN not found, building stub version")
                set(MNN_AVAILABLE OFF)
            endif()
        endif()
    endif()
endif()

# =============================================================================
# Library Target
# =============================================================================

add_library(edgemind_core SHARED
    src/asr_recognizer.cpp
    src/mnn_wrapper.cpp
    src/edgemind_core.cpp
)

if(EDGEMIND_ENABLE_ZVEC)
    set(ZVEC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/zvec/zvec-android-arm64")
    if(EXISTS "${ZVEC_DIR}/lib")
        target_sources(edgemind_core PRIVATE src/zvec_c.cpp)
        include_directories(${ZVEC_DIR}/include/include)
        target_link_directories(edgemind_core PRIVATE ${ZVEC_DIR}/lib)
        target_compile_definitions(edgemind_core PRIVATE ZVEC_AVAILABLE)
        message(STATUS "Building edgemind_core with Zvec vector DB")
    else()
        target_sources(edgemind_core PRIVATE src/zvec_c_stub.cpp)
        message(WARNING "Zvec libraries not found; using stub")
    endif()
else()
    target_sources(edgemind_core PRIVATE src/zvec_c_stub.cpp)
    message(STATUS "Zvec disabled by option (using Dart in-memory vector store)")
endif()

set_source_files_properties(
    src/mnn_wrapper.cpp
    src/edgemind_core.cpp
    PROPERTIES
        COMPILE_FLAGS "-frtti -fexceptions"
)

target_include_directories(edgemind_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${MNN_SOURCE_DIR}/3rd_party
)

# These translation units use RTTI and/or C++ exceptions, while the vendored
# MNN tree disables both globally for some Android configurations.
target_compile_options(edgemind_core PRIVATE -frtti -fexceptions)

if(MNN_AVAILABLE AND MNN_FOUND)
    target_compile_definitions(edgemind_core PRIVATE MNN_AVAILABLE MNN_BUILD_LLM MNN_LLM_SUPPORT)
    target_include_directories(edgemind_core PRIVATE
        ${MNN_INCLUDE_DIR}
        ${MNN_ANDROID_INSTALL_DIR}/include
        ${MNN_SOURCE_DIR}/transformers/llm/engine/include
        ${MNN_SOURCE_DIR}/tools/cv/include
        ${MNN_SOURCE_DIR}/tools/audio/include
    )
    
    if(ANDROID)
        target_link_directories(edgemind_core PRIVATE ${MNN_LIB_DIR})
    endif()
    
    target_link_libraries(edgemind_core PRIVATE ${MNN_LIBRARY})
    message(STATUS "Building edgemind_core with MNN support")
else()
    message(STATUS "Building edgemind_core in stub mode")
endif()

# =============================================================================
# Sherpa MNN (Streaming ASR)
# =============================================================================

option(EDGEMIND_ENABLE_SHERPA_MNN_ASR "Build with ASR via sherpa-mnn" ON)

if(EDGEMIND_ENABLE_SHERPA_MNN_ASR AND MNN_AVAILABLE AND MNN_FOUND)
    set(EDGEMIND_SHERPA_MNN_DIR "${MNN_SOURCE_DIR}/apps/frameworks/sherpa-mnn")
    if(EXISTS "${EDGEMIND_SHERPA_MNN_DIR}/CMakeLists.txt")
        if(ANDROID)
            set(EDGEMIND_SHERPA_MNN_ROOT "${MNN_ANDROID_INSTALL_DIR}")
        else()
            get_filename_component(EDGEMIND_MNN_LIBRARY_DIR "${MNN_LIBRARY}" DIRECTORY)
            get_filename_component(EDGEMIND_SHERPA_MNN_ROOT "${EDGEMIND_MNN_LIBRARY_DIR}" DIRECTORY)
        endif()

        set(EDGEMIND_BUILD_SHARED_LIBS_SAVED ${BUILD_SHARED_LIBS})
        set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
        set(MNN_LIB_DIR "${EDGEMIND_SHERPA_MNN_ROOT}" CACHE PATH "" FORCE)
        set(SHERPA_MNN_ENABLE_PYTHON OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_CHECK OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_PORTAUDIO OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_JNI OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_C_API ON CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_WEBSOCKET OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_BINARY OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_TTS OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_ENABLE_SPEAKER_DIARIZATION OFF CACHE BOOL "" FORCE)
        set(SHERPA_MNN_BUILD_C_API_EXAMPLES OFF CACHE BOOL "" FORCE)

        include_directories(${EDGEMIND_SHERPA_MNN_DIR})
        add_subdirectory(
            ${EDGEMIND_SHERPA_MNN_DIR}
            ${CMAKE_CURRENT_BINARY_DIR}/sherpa-mnn
            EXCLUDE_FROM_ALL
        )
        set(BUILD_SHARED_LIBS ${EDGEMIND_BUILD_SHARED_LIBS_SAVED} CACHE BOOL "" FORCE)

        target_sources(edgemind_core PRIVATE
            src/sherpa_mnn_asr.cpp
        )
        target_include_directories(edgemind_core PRIVATE
            ${EDGEMIND_SHERPA_MNN_DIR}
        )
        target_compile_definitions(edgemind_core PRIVATE EDGEMIND_SHERPA_MNN_ASR_AVAILABLE)
        target_link_libraries(edgemind_core PRIVATE
            sherpa-mnn-cxx-api
            sherpa-mnn-c-api
            sherpa-mnn-core
        )

        message(STATUS "Building edgemind_core with ASR (sherpa-mnn)")
    else()
        message(WARNING "sherpa-mnn source tree not found; skipping sherpa-mnn ASR")
    endif()
elseif(EDGEMIND_ENABLE_SHERPA_MNN_ASR)
    message(STATUS "sherpa-mnn ASR disabled: MNN not available")
else()
    message(STATUS "sherpa-mnn ASR disabled by option")
endif()

# =============================================================================
# RNNoise (ASR preprocessing)
# =============================================================================

option(EDGEMIND_ENABLE_RNNOISE_ASR_DENOISE "Build with RNNoise preprocessing before ASR" ON)

if(EDGEMIND_ENABLE_RNNOISE_ASR_DENOISE)
    set(EDGEMIND_RNNOISE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/rnnoise")
    if(EXISTS "${EDGEMIND_RNNOISE_DIR}/include/rnnoise.h")
        target_sources(edgemind_core PRIVATE
            ${EDGEMIND_RNNOISE_DIR}/src/denoise.c
            ${EDGEMIND_RNNOISE_DIR}/src/rnn.c
            ${EDGEMIND_RNNOISE_DIR}/src/nnet.c
            ${EDGEMIND_RNNOISE_DIR}/src/nnet_default.c
            ${EDGEMIND_RNNOISE_DIR}/src/rnnoise_tables.c
            ${EDGEMIND_RNNOISE_DIR}/src/rnnoise_data.c
            ${EDGEMIND_RNNOISE_DIR}/src/parse_lpcnet_weights.c
            ${EDGEMIND_RNNOISE_DIR}/src/pitch.c
            ${EDGEMIND_RNNOISE_DIR}/src/kiss_fft.c
            ${EDGEMIND_RNNOISE_DIR}/src/celt_lpc.c
        )
        target_include_directories(edgemind_core PRIVATE
            ${EDGEMIND_RNNOISE_DIR}/include
            ${EDGEMIND_RNNOISE_DIR}/src
        )
        target_compile_definitions(edgemind_core PRIVATE
            RNNOISE_BUILD
            EDGEMIND_RNNOISE_AVAILABLE
        )

        find_library(EDGEMIND_MATH_LIBRARY m)
        if(EDGEMIND_MATH_LIBRARY)
            target_link_libraries(edgemind_core PRIVATE ${EDGEMIND_MATH_LIBRARY})
        endif()

        message(STATUS "Building edgemind_core with RNNoise ASR denoising")
    else()
        message(WARNING "RNNoise source tree not found; skipping ASR denoising")
    endif()
else()
    message(STATUS "RNNoise ASR denoising disabled by option")
endif()

# =============================================================================
# Supertonic TTS (MNN)
# =============================================================================

option(EDGEMIND_ENABLE_TTS "Build with Supertonic TTS via MNN" ON)

if(EDGEMIND_ENABLE_TTS AND MNN_AVAILABLE AND MNN_FOUND)
    target_sources(edgemind_core PRIVATE
        src/supertonic/supertonic_tts.cpp
    )
    target_compile_definitions(edgemind_core PRIVATE SUPERTONIC_AVAILABLE)
    # MNN include dirs and libraries already linked above
    message(STATUS "Building edgemind_core with TTS (supertonic-mnn)")
else()
    if(EDGEMIND_ENABLE_TTS)
        message(STATUS "TTS disabled: MNN not available")
    else()
        message(STATUS "TTS disabled by option")
    endif()
endif()

# =============================================================================
# Platform-specific settings
# =============================================================================

if(ANDROID)
    # Android-specific settings
    target_compile_definitions(edgemind_core PRIVATE ANDROID)
    target_link_options(edgemind_core PRIVATE "-Wl,-z,max-page-size=16384")
    
    # Link Android libraries
    find_library(LOG_LIB log)
    target_link_libraries(edgemind_core PRIVATE ${LOG_LIB})

    if(EDGEMIND_ENABLE_ZVEC AND EXISTS "${ZVEC_DIR}/lib")
        target_link_libraries(edgemind_core PRIVATE 
            zvec_db zvec_sqlengine zvec_index zvec_proto zvec_common zvec_ailego
            core_framework core_interface
            -Wl,--whole-archive
            core_knn_flat core_knn_hnsw core_metric core_quantizer core_utility core_mix_reducer
            -Wl,--no-whole-archive
            arrow arrow_dataset arrow_acero arrow_compute arrow_bundled_dependencies parquet
            roaring protobuf rocksdb lz4 antlr4-runtime glog gflags_nothreads re2 thrift utf8proc z
            boost_locale boost_thread boost_charconv boost_container boost_chrono boost_atomic boost_date_time)
    endif()
    
elseif(APPLE)
    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        target_compile_definitions(edgemind_core PRIVATE IOS)
    else()
        target_compile_definitions(edgemind_core PRIVATE MACOS)
    endif()
    
    # Metal framework for Apple platforms
    find_library(METAL_FRAMEWORK Metal)
    find_library(FOUNDATION_FRAMEWORK Foundation)
    if(METAL_FRAMEWORK)
        target_link_libraries(edgemind_core PRIVATE ${METAL_FRAMEWORK} ${FOUNDATION_FRAMEWORK})
    endif()
endif()

# =============================================================================
# Install
# =============================================================================

if(NOT ANDROID)
    include(GNUInstallDirs)

    install(TARGETS edgemind_core
        EXPORT edgemind_core-targets
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    )

    install(DIRECTORY include/
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )

    install(EXPORT edgemind_core-targets
        FILE edgemind_core-targets.cmake
        NAMESPACE EdgeMind::
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/edgemind_core
    )
endif()

# =============================================================================
# Tests
# =============================================================================

option(BUILD_TESTS "Build tests" OFF)

if(BUILD_TESTS)
    enable_testing()
    
    add_executable(edgemind_core_test
        tests/test_wrapper.cpp
    )
    
    target_link_libraries(edgemind_core_test PRIVATE edgemind_core)
    
    add_test(NAME edgemind_core_test COMMAND edgemind_core_test)
endif()
