// ==============================================================================
// Planter Pressure - OPTIMIZED Native Engine Bindings
// ==============================================================================
//
// KEY OPTIMIZATIONS:
// 1. Runs ALL FFI calls in a separate Isolate (non-blocking UI)
// 2. Proper memory cleanup with free_string
// 3. Path-only communication (no Base64, no raw bytes)
// 4. Thread-safe design
// ==============================================================================

import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

// ==============================================================================
// FFI Type Definitions
// ==============================================================================

typedef _EngineInitC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _EngineInitDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _EngineIsInitializedC = Int32 Function();
typedef _EngineIsInitializedDart = int Function();

typedef _ProcessImageC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ProcessImageDart = Pointer<Utf8> Function(Pointer<Utf8>);

typedef _FreeStringC = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

typedef _EngineShutdownC = Void Function();
typedef _EngineShutdownDart = void Function();

typedef _GetLastErrorC = Pointer<Utf8> Function();
typedef _GetLastErrorDart = Pointer<Utf8> Function();

typedef _GetVersionC = Pointer<Utf8> Function();
typedef _GetVersionDart = Pointer<Utf8> Function();

// ==============================================================================
// Low-Level Bindings (Used inside Isolate)
// ==============================================================================

class _RawBindings {
  final DynamicLibrary _lib;

  late final _EngineInitDart engineInit;
  late final _EngineIsInitializedDart isInitialized;
  late final _ProcessImageDart processImage;
  late final _FreeStringDart freeString;
  late final _EngineShutdownDart shutdown;
  late final _GetLastErrorDart getLastError;
  late final _GetVersionDart getVersion;

  _RawBindings(String libraryPath) : _lib = DynamicLibrary.open(libraryPath) {
    engineInit = _lib.lookup<NativeFunction<_EngineInitC>>('engine_init').asFunction();
    isInitialized = _lib.lookup<NativeFunction<_EngineIsInitializedC>>('engine_is_initialized').asFunction();
    processImage = _lib.lookup<NativeFunction<_ProcessImageC>>('process_image').asFunction();
    freeString = _lib.lookup<NativeFunction<_FreeStringC>>('free_string').asFunction();
    shutdown = _lib.lookup<NativeFunction<_EngineShutdownC>>('engine_shutdown').asFunction();
    getLastError = _lib.lookup<NativeFunction<_GetLastErrorC>>('engine_get_last_error').asFunction();
    getVersion = _lib.lookup<NativeFunction<_GetVersionC>>('engine_get_version').asFunction();
  }
}

// ==============================================================================
// Isolate Messages
// ==============================================================================

sealed class _IsolateMessage {}

class _InitMessage extends _IsolateMessage {
  final SendPort replyPort;
  final String libraryPath;
  final String? pythonHome;
  final String scriptPath;

  _InitMessage(this.replyPort, this.libraryPath, this.pythonHome, this.scriptPath);
}

class _ProcessMessage extends _IsolateMessage {
  final SendPort replyPort;
  final String inputJson;

  _ProcessMessage(this.replyPort, this.inputJson);
}

class _ShutdownMessage extends _IsolateMessage {
  final SendPort replyPort;
  _ShutdownMessage(this.replyPort);
}

class _GetVersionMessage extends _IsolateMessage {
  final SendPort replyPort;
  _GetVersionMessage(this.replyPort);
}

// ==============================================================================
// Isolate Worker
// ==============================================================================

void _isolateEntry(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  _RawBindings? bindings;

  receivePort.listen((message) {
    if (message is _InitMessage) {
      try {
        bindings = _RawBindings(message.libraryPath);

        final pythonHomePtr = message.pythonHome?.toNativeUtf8() ?? nullptr;
        final scriptPathPtr = message.scriptPath.toNativeUtf8();

        final result = bindings!.engineInit(pythonHomePtr, scriptPathPtr);

        // Free allocated strings
        if (pythonHomePtr != nullptr) calloc.free(pythonHomePtr);
        calloc.free(scriptPathPtr);

        if (result != 0) {
          final errorPtr = bindings!.getLastError();
          final error = errorPtr != nullptr ? errorPtr.toDartString() : 'Unknown error';
          message.replyPort.send({'success': false, 'error': error, 'code': result});
        } else {
          final versionPtr = bindings!.getVersion();
          final version = versionPtr != nullptr ? versionPtr.toDartString() : 'unknown';
          message.replyPort.send({'success': true, 'version': version});
        }
      } catch (e) {
        message.replyPort.send({'success': false, 'error': e.toString()});
      }
    } else if (message is _ProcessMessage) {
      if (bindings == null) {
        message.replyPort.send({'success': false, 'error': 'Not initialized'});
        return;
      }

      final inputPtr = message.inputJson.toNativeUtf8();
      Pointer<Utf8>? resultPtr;

      try {
        resultPtr = bindings!.processImage(inputPtr);

        if (resultPtr == nullptr) {
          message.replyPort.send({'success': false, 'error': 'Null result'});
        } else {
          final result = resultPtr.toDartString();
          message.replyPort.send({'success': true, 'result': result});
        }
      } finally {
        // CRITICAL: Free allocated memory!
        calloc.free(inputPtr);
        if (resultPtr != null && resultPtr != nullptr) {
          bindings!.freeString(resultPtr);
        }
      }
    } else if (message is _ShutdownMessage) {
      bindings?.shutdown();
      bindings = null;
      message.replyPort.send({'success': true});
      receivePort.close();
    } else if (message is _GetVersionMessage) {
      if (bindings != null) {
        final ptr = bindings!.getVersion();
        message.replyPort.send(ptr != nullptr ? ptr.toDartString() : 'unknown');
      } else {
        message.replyPort.send('not loaded');
      }
    }
  });
}

// ==============================================================================
// Exception
// ==============================================================================

class NativeEngineException implements Exception {
  final String message;
  final int? code;

  NativeEngineException(this.message, {this.code});

  @override
  String toString() => 'NativeEngineException: $message${code != null ? ' (code: $code)' : ''}';
}

// ==============================================================================
// Processing Result
// ==============================================================================

class ProcessingResult {
  final bool success;
  final String? outputPath;
  final String? error;
  final Map<String, dynamic>? metadata;

  ProcessingResult({
    required this.success,
    this.outputPath,
    this.error,
    this.metadata,
  });

  factory ProcessingResult.fromJson(Map<String, dynamic> json) {
    return ProcessingResult(
      success: json['status'] == 'success',
      outputPath: json['output_image_path'],
      error: json['error'],
      metadata: json['metadata'],
    );
  }
}

// ==============================================================================
// Native Engine (High-Level, Isolate-Based)
// ==============================================================================

class NativeEngine {
  Isolate? _isolate;
  SendPort? _sendPort;
  bool _initialized = false;
  String _version = 'unknown';

  bool get isInitialized => _initialized;
  String get version => _version;

  /// Initialize engine in background isolate.
  /// Does NOT block UI thread.
  Future<void> initialize({
    required String libraryPath,
    String? pythonHome,
    required String scriptPath,
  }) async {
    if (_initialized) {
      throw NativeEngineException('Already initialized');
    }

    // Spawn isolate
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);
    _sendPort = await receivePort.first as SendPort;

    // Initialize engine in isolate
    final responsePort = ReceivePort();
    _sendPort!.send(_InitMessage(
      responsePort.sendPort,
      libraryPath,
      pythonHome,
      scriptPath,
    ));

    final response = await responsePort.first as Map<String, dynamic>;
    responsePort.close();

    if (response['success'] != true) {
      await shutdown();
      throw NativeEngineException(
        response['error'] ?? 'Init failed',
        code: response['code'],
      );
    }

    _version = response['version'] ?? 'unknown';
    _initialized = true;
  }

  /// Process image in background isolate.
  /// Does NOT block UI thread.
  Future<ProcessingResult> processImage(String inputPath, {String? outputDir}) async {
    if (!_initialized || _sendPort == null) {
      throw NativeEngineException('Not initialized');
    }

    final inputJson = jsonEncode({
      'input_image_path': inputPath,
      if (outputDir != null) 'output_dir': outputDir,
    });

    final responsePort = ReceivePort();
    _sendPort!.send(_ProcessMessage(responsePort.sendPort, inputJson));

    final response = await responsePort.first as Map<String, dynamic>;
    responsePort.close();

    if (response['success'] != true) {
      throw NativeEngineException(response['error'] ?? 'Process failed');
    }

    final resultJson = response['result'] as String;
    final resultMap = jsonDecode(resultJson) as Map<String, dynamic>;
    return ProcessingResult.fromJson(resultMap);
  }

  /// Shutdown engine and kill isolate.
  Future<void> shutdown() async {
    if (_sendPort != null) {
      final responsePort = ReceivePort();
      _sendPort!.send(_ShutdownMessage(responsePort.sendPort));
      await responsePort.first;
      responsePort.close();
    }

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _initialized = false;
  }
}
