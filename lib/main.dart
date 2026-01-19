// ==============================================================================
// Planter Pressure - OPTIMIZED Main Application
// ==============================================================================
//
// KEY OPTIMIZATIONS:
// 1. ResizeImage for memory-efficient display (NOT full resolution!)
// 2. StreamBuilder for real-time progress (responsive UI)
// 3. Proper image cache management
// 4. No UI freezing - all heavy work in Isolate
// ==============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'image_processing_service.dart';
import 'native_engine_bindings.dart';

void main() {
  runApp(const PlanterPressureApp());
}

class PlanterPressureApp extends StatelessWidget {
  const PlanterPressureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planter Pressure',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C3AED)),
        useMaterial3: true,
      ),
      home: const ImageProcessorScreen(),
    );
  }
}

class ImageProcessorScreen extends StatefulWidget {
  const ImageProcessorScreen({super.key});

  @override
  State<ImageProcessorScreen> createState() => _ImageProcessorScreenState();
}

class _ImageProcessorScreenState extends State<ImageProcessorScreen> {
  final ImageProcessingService _service = ImageProcessingService();

  String? _originalPath;
  String? _processedPath;
  final List<String> _logs = [];
  bool _isInitialized = false;

  // Force image reload on path change
  Key _originalKey = UniqueKey();
  Key _processedKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _service.dispose();
    // Clear Flutter's image cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    super.dispose();
  }

  Future<void> _init() async {
    _log('🚀 Initializing...');
    try {
      await _service.initialize();
      _log('✓ Engine v${_service.engineVersion} ready');
      setState(() => _isInitialized = true);
    } catch (e) {
      _log('❌ Init failed: $e');
    }
  }

  void _log(String msg) {
    setState(() {
      _logs.add(msg);
      if (_logs.length > 50) _logs.removeAt(0); // Limit logs
    });
  }

  void _clearLogs() => setState(() => _logs.clear());

  void _evictImage(String path) {
    FileImage(File(path)).evict();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp'],
    );

    if (result?.files.first.path != null) {
      final path = result!.files.first.path!;

      // Evict old images from cache
      if (_originalPath != null) _evictImage(_originalPath!);
      if (_processedPath != null) _evictImage(_processedPath!);

      setState(() {
        _originalPath = path;
        _processedPath = null;
        _originalKey = UniqueKey();
        _processedKey = UniqueKey();
      });

      _clearLogs();
      _log('📁 Selected: ${p.basename(path)}');

      // Log file size
      final size = await File(path).length();
      _log('   Size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
    }
  }

  Future<void> _process() async {
    if (_originalPath == null || !_isInitialized) return;

    _clearLogs();
    _log('⏳ Processing...');

    try {
      final result = await _service.processImage(inputPath: _originalPath!);

      if (result.success) {
        // Evict old processed image
        if (_processedPath != null) _evictImage(_processedPath!);

        setState(() {
          _processedPath = result.outputPath;
          _processedKey = UniqueKey();
        });

        _log('✅ Success!');
        if (result.metadata != null) {
          final m = result.metadata!;
          if (m['original_size'] != null) {
            final s = m['original_size'] as List;
            _log('   Dimensions: ${s[0]}x${s[1]}');
          }
          if (m['output_size_bytes'] != null) {
            _log('   Output: ${(m['output_size_bytes'] / 1024 / 1024).toStringAsFixed(2)} MB');
          }
        }
      } else {
        _log('❌ ${result.error}');
      }
    } catch (e) {
      _log('❌ Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildButtons(),
            const SizedBox(height: 16),
            _buildProgress(),
            const SizedBox(height: 16),
            Expanded(child: _buildImages()),
            const SizedBox(height: 16),
            _buildLogs(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDDD6FE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Planter Pressure - Optimized',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF7C3AED),
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return StreamBuilder<ProcessingProgress>(
      stream: _service.progressStream,
      builder: (context, _) {
        final processing = _service.isProcessing;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: processing ? null : _pickImage,
              icon: const Icon(Icons.folder_open),
              label: const Text('Select Image'),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: (_originalPath != null && _isInitialized && !processing)
                  ? _process
                  : null,
              icon: processing
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.auto_fix_high),
              label: Text(processing ? 'Processing...' : 'Process'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProgress() {
    return StreamBuilder<ProcessingProgress>(
      stream: _service.progressStream,
      builder: (context, snapshot) {
        final p = snapshot.data;

        Color bg, fg;
        IconData icon;
        String msg;
        double progress = 0;

        if (p == null) {
          bg = const Color(0xFFEFF6FF);
          fg = const Color(0xFF1E40AF);
          icon = Icons.info_outline;
          msg = _isInitialized ? 'Select an image' : 'Initializing...';
        } else {
          progress = p.progress;
          msg = p.message;

          switch (p.state) {
            case ProcessingState.idle:
            case ProcessingState.ready:
              bg = const Color(0xFFEFF6FF);
              fg = const Color(0xFF1E40AF);
              icon = Icons.info_outline;
            case ProcessingState.initializing:
            case ProcessingState.processing:
              bg = const Color(0xFFFEF3C7);
              fg = const Color(0xFF92400E);
              icon = Icons.hourglass_empty;
            case ProcessingState.completed:
              bg = const Color(0xFFECFDF5);
              fg = const Color(0xFF065F46);
              icon = Icons.check_circle_outline;
            case ProcessingState.error:
              bg = const Color(0xFFFEF2F2);
              fg = const Color(0xFF991B1B);
              icon = Icons.error_outline;
          }
        }

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(msg, style: TextStyle(color: fg))),
                  if (progress > 0 && progress < 1)
                    Text('${(progress * 100).toInt()}%',
                        style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (progress > 0 && progress < 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: progress),
              ),
          ],
        );
      },
    );
  }

  Widget _buildImages() {
    return Row(
      children: [
        Expanded(child: _imageBox('Original', _originalPath, _originalKey, const Color(0xFFF3F4F6))),
        const SizedBox(width: 16),
        Expanded(child: _imageBox('Processed', _processedPath, _processedKey, const Color(0xFFECFDF5))),
      ],
    );
  }

  Widget _imageBox(String title, String? path, Key key, Color bg) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Center(
              child: path != null ? _optimizedImage(path, key) : _placeholder(),
            ),
          ),
        ],
      ),
    );
  }

  /// OPTIMIZED IMAGE WIDGET
  /// Uses ResizeImage to decode at display size, NOT full resolution!
  /// This is the KEY to reducing memory usage.
  Widget _optimizedImage(String path, Key key) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate target size for display
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final targetW = (constraints.maxWidth * dpr).toInt().clamp(100, 800);
        final targetH = (constraints.maxHeight * dpr).toInt().clamp(100, 600);

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Image(
            key: key,
            // CRITICAL: ResizeImage decodes at target size, not full resolution!
            image: ResizeImage(
              FileImage(File(path)),
              width: targetW,
              height: targetH,
              policy: ResizeImagePolicy.fit,
            ),
            fit: BoxFit.contain,
            frameBuilder: (ctx, child, frame, sync) {
              if (sync) return child;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: frame != null
                    ? child
                    : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _placeholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text('No image', style: TextStyle(color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildLogs() {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(8),
      ),
      child: _logs.isEmpty
          ? Center(
        child: Text('Logs appear here...', style: TextStyle(color: Colors.grey[500])),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _logs.length,
        itemBuilder: (_, i) => Text(
          _logs[i],
          style: const TextStyle(
            color: Color(0xFF34D399),
            fontFamily: 'Consolas',
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}