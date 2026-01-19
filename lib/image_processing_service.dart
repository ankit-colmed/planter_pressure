// ==============================================================================
// Planter Pressure - OPTIMIZED Image Processing Service
// ==============================================================================
//
// KEY OPTIMIZATIONS:
// 1. All heavy work runs in Isolate (non-blocking)
// 2. Progress streaming for responsive UI
// 3. Proper cleanup and disposal
// 4. Async file operations
// ==============================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'native_engine_bindings.dart';

// ==============================================================================
// Processing State
// ==============================================================================

enum ProcessingState {
  idle,
  initializing,
  ready,
  processing,
  completed,
  error,
}

// ==============================================================================
// Progress Updates
// ==============================================================================

class ProcessingProgress {
  final double progress;
  final String message;
  final ProcessingState state;

  ProcessingProgress(this.progress, this.message, this.state);
}

// ==============================================================================
// Service
// ==============================================================================

class ImageProcessingService {
  NativeEngine? _engine;
  ProcessingState _state = ProcessingState.idle;
  String? _lastError;

  final _progressController = StreamController<ProcessingProgress>.broadcast();
  Stream<ProcessingProgress> get progressStream => _progressController.stream;

  ProcessingState get state => _state;
  bool get isReady => _state == ProcessingState.ready;
  bool get isProcessing => _state == ProcessingState.processing;
  String? get lastError => _lastError;
  String get engineVersion => _engine?.version ?? 'not initialized';

  void _emit(double progress, String message, ProcessingState state) {
    _state = state;
    if (!_progressController.isClosed) {
      _progressController.add(ProcessingProgress(progress, message, state));
    }
  }

  /// Initialize the service.
  /// Runs in background - does NOT block UI.
  Future<void> initialize({String? pythonHome}) async {
    if (_state != ProcessingState.idle) {
      throw ImageProcessingException('Already initialized');
    }

    _emit(0.0, 'Starting initialization...', ProcessingState.initializing);

    try {
      _emit(0.4, 'Locating native library...', ProcessingState.initializing);
      final libraryPath = await _locateLibrary();

      // The native engine now expects the directory containing app_modules.zip
      // which we place next to the DLL.
      final assetsPath = p.dirname(libraryPath);

      _emit(0.6, 'Starting Python engine...', ProcessingState.initializing);
      _engine = NativeEngine();
      await _engine!.initialize(
        libraryPath: libraryPath,
        pythonHome: pythonHome,
        scriptPath: assetsPath, // Passing directory, engine appends app_modules.zip
      );

      _emit(1.0, 'Ready', ProcessingState.ready);
    } catch (e) {
      _lastError = e.toString();
      _emit(0.0, 'Init failed: $e', ProcessingState.error);
      rethrow;
    }
  }

  // _prepareScript removed as we no longer use raw .py files

  Future<String> _locateLibrary() async {
    const name = 'image_processor_engine.dll';
    final execDir = p.dirname(Platform.resolvedExecutable);

    final paths = [
      p.join(execDir, name),
      p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', name),
      p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', name),
      name,
    ];

    for (final path in paths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    return name;
  }

  /// Process an image.
  /// Runs in background isolate - does NOT block UI!
  Future<ProcessingResult> processImage({
    required String inputPath,
    String? outputDir,
  }) async {
    if (!isReady) {
      throw ImageProcessingException('Not ready');
    }

    if (!await File(inputPath).exists()) {
      throw ImageProcessingException('File not found: $inputPath');
    }

    _lastError = null;
    _emit(0.0, 'Starting...', ProcessingState.processing);

    try {
      _emit(0.3, 'Processing image...', ProcessingState.processing);

      // This runs in a separate Isolate - UI stays responsive!
      final result = await _engine!.processImage(inputPath, outputDir: outputDir);

      if (result.success) {
        _emit(1.0, 'Complete!', ProcessingState.completed);
      } else {
        _lastError = result.error;
        _emit(0.0, 'Failed: ${result.error}', ProcessingState.error);
      }

      // Reset to ready after short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_state == ProcessingState.completed || _state == ProcessingState.error) {
          _emit(0.0, 'Ready', ProcessingState.ready);
        }
      });

      return result;
    } catch (e) {
      _lastError = e.toString();
      _emit(0.0, 'Error: $e', ProcessingState.error);
      rethrow;
    }
  }

  /// Cleanup and dispose.
  Future<void> dispose() async {
    await _engine?.shutdown();
    _engine = null;
    _progressController.close();
    _state = ProcessingState.idle;
  }
}

class ImageProcessingException implements Exception {
  final String message;
  ImageProcessingException(this.message);

  @override
  String toString() => 'ImageProcessingException: $message';
}
