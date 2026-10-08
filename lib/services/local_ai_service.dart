import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

class LocalAiService {
  static final LocalAiService instance = LocalAiService._internal();

  LocalAiService._internal();

  static const String modelUrl =
      'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf';
  static const String modelFileName = 'gemma-3-1b-it-Q4_K_M.gguf';
  static const int _minimumModelBytes = 100 * 1024 * 1024;
  static const int _contextSize = 2048;

  // Keep one controller/model for the lifetime of the app engine. The page can
  // be opened and closed without disposing a native handle that another page
  // may still be using.
  LlamaController? _controller;

  LlamaController get controller => _controller ??= LlamaController();

  bool _initialized = false;
  bool _downloading = false;
  bool _generationActive = false;
  Future<void>? _initializationFuture;
  Future<String>? _knowledgeFuture;

  bool get isInitialized => _initialized;
  bool get isDownloading => _downloading;

  Future<Directory> _getModelDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final modelDirectory = Directory('${directory.path}/models');
    if (!await modelDirectory.exists()) {
      await modelDirectory.create(recursive: true);
    }
    return modelDirectory;
  }

  Future<String> get modelPath async {
    final modelDirectory = await _getModelDirectory();
    return '${modelDirectory.path}/$modelFileName';
  }

  Future<bool> _isValidModelFile(File file) async {
    if (!await file.exists() || await file.length() < _minimumModelBytes) {
      return false;
    }

    final handle = await file.open();
    try {
      final header = await handle.read(4);
      return header.length == 4 &&
          header[0] == 0x47 && // G
          header[1] == 0x47 && // G
          header[2] == 0x55 && // U
          header[3] == 0x46; // F
    } finally {
      await handle.close();
    }
  }

  Future<bool> isModelDownloaded() async {
    final path = await modelPath;
    return _isValidModelFile(File(path));
  }

  Future<void> downloadModel({
    void Function(double progress)? onProgress,
  }) async {
    if (_downloading) {
      throw StateError('Model download is already in progress.');
    }

    _downloading = true;
    File? temporaryFile;
    try {
      final modelDirectory = await _getModelDirectory();
      final finalFile = File('${modelDirectory.path}/$modelFileName');
      if (await _isValidModelFile(finalFile)) {
        onProgress?.call(1.0);
        return;
      }

      temporaryFile = File('${modelDirectory.path}/$modelFileName.part');
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }

      developer.log('Local AI model download started.', name: 'LocalAi');
      final request = http.Request('GET', Uri.parse(modelUrl));
      final response = await request.send().timeout(
        const Duration(seconds: 45),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          'Model download failed with HTTP ${response.statusCode}.',
        );
      }

      final totalBytes = response.contentLength ?? 0;
      var downloadedBytes = 0;
      final sink = temporaryFile.openWrite();
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (totalBytes > 0) {
            onProgress?.call(downloadedBytes / totalBytes);
          }
        }
      } finally {
        await sink.close();
      }

      if (totalBytes > 0 && downloadedBytes != totalBytes) {
        throw const FormatException('The model download was incomplete.');
      }
      if (!await _isValidModelFile(temporaryFile)) {
        throw const FormatException(
          'The downloaded file is incomplete or is not a GGUF model.',
        );
      }

      // Only replace an old file after the new download passed its checks.
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await temporaryFile.rename(finalFile.path);
      developer.log(
        'Local AI GGUF model verified (${await finalFile.length()} bytes).',
        name: 'LocalAi',
      );
      onProgress?.call(1.0);
    } finally {
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      _downloading = false;
    }
  }

  /// Concurrent callers share one operation rather than treating an in-flight
  /// load as if it were already complete.
  Future<void> initialize({
    void Function(double progress)? onDownloadProgress,
  }) async {
    if (_initialized) return;
    final current = _initializationFuture;
    if (current != null) return current;

    final operation = _initializeModel(onDownloadProgress);
    _initializationFuture = operation;
    try {
      await operation;
    } finally {
      if (identical(_initializationFuture, operation)) {
        _initializationFuture = null;
      }
    }
  }

  Future<void> _initializeModel(
    void Function(double progress)? onDownloadProgress,
  ) async {
    developer.log('Local AI initialization started.', name: 'LocalAi');
    try {
      if (!Platform.isAndroid) {
        throw const LocalAiException(
          'Local AI is currently supported on Android devices only.',
        );
      }

      if (!await isModelDownloaded()) {
        await downloadModel(onProgress: onDownloadProgress);
      }

      final path = await modelPath;
      final modelFile = File(path);
      if (!await _isValidModelFile(modelFile)) {
        throw const LocalAiException(
          'The offline model file could not be verified. Please retry the download.',
        );
      }

      // llama_flutter_android 0.2.6 packages an arm64-v8a native library and
      // compiles llama.cpp with GGML_VULKAN=OFF. Vulkan detection in the plugin
      // reports device capability, not whether this packaged inference backend
      // can offload layers. CPU-only loading is therefore the supported,
      // predictable path on both MediaTek and Snapdragon.
      final threads = Platform.numberOfProcessors.clamp(1, 4).toInt();
      developer.log(
        'Model path verified; backend=CPU; context=$_contextSize; threads=$threads; plugin ABI=arm64-v8a.',
        name: 'LocalAi',
      );

      await controller.loadModel(
        modelPath: path,
        threads: threads,
        contextSize: _contextSize,
        gpuLayers: 0,
      );

      _initialized = true;
      developer.log('Local AI model loaded successfully.', name: 'LocalAi');
    } catch (error, stackTrace) {
      developer.log(
        'Local AI initialization failed.',
        name: 'LocalAi',
        error: error,
        stackTrace: stackTrace,
      );
      if (error is LocalAiException) rethrow;
      throw LocalAiException(_userFriendlyLoadError(error));
    }
  }

  String _userFriendlyLoadError(Object error) {
    final description = error.toString().toLowerCase();
    if (description.contains('memory') ||
        description.contains('allocate') ||
        description.contains('outofmemory')) {
      return 'Local AI could not start because this device does not have enough free memory. Close other apps and try again.';
    }
    if (description.contains('not supported') ||
        description.contains('unsatisfiedlinkerror')) {
      return 'This Android device does not provide the required 64-bit ARM runtime for Local AI.';
    }
    return 'Local AI could not start. Check that the offline model is complete, free some device memory, and try again.';
  }

  Future<String> _loadKnowledge() {
    return _knowledgeFuture ??= rootBundle
        .loadString('assets/ai/detectco_knowledge.txt')
        .catchError((Object error) {
          developer.log(
            'DETECT-CO knowledge file could not be loaded.',
            name: 'LocalAi',
            error: error,
          );
          return '';
        });
  }

  Stream<String> ask(String question, {List<ChatMessage>? conversation}) {
    return _generateAnswer(question, conversation);
  }

  Stream<String> _generateAnswer(
    String question,
    List<ChatMessage>? conversation,
  ) async* {
    if (!_initialized) {
      throw StateError('Local AI model is not initialized.');
    }
    if (_generationActive) {
      throw StateError('Local AI is already generating a response.');
    }

    _generationActive = true;
    var completed = false;
    try {
      final knowledge = await _loadKnowledge();
      final systemContent = StringBuffer('''
You are the DETECT-CO local AI assistant.

DETECT-CO is a community-based flood risk detection and early warning system.

Your responsibilities:
- Explain how to use DETECT-CO.
- Explain flood preparedness and safety.
- Explain warning indicators and system information.
- Help users understand information provided by the application.
- Give clear and simple answers.

Important rules:
- Do not invent sensor readings.
- Do not invent weather conditions.
- Do not invent evacuation-center availability.
- Do not claim an emergency condition unless the application provides the relevant data.
- Do not replace official emergency authorities or emergency instructions.
- If information is unavailable, clearly say that it is unavailable.
- Keep answers concise and easy to understand.

You are running locally on the user's Android device.
''');
      if (knowledge.trim().isNotEmpty) {
        systemContent
          ..writeln()
          ..writeln('DETECT-CO reference information:')
          ..writeln(knowledge.trim());
      }

      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemContent.toString()),
        if (conversation != null) ...conversation,
        ChatMessage(role: 'user', content: question),
      ];

      await for (final token in controller.generateChat(
        messages: messages,
        maxTokens: 300,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        repeatPenalty: 1.1,
      )) {
        yield token;
      }
      completed = true;
    } finally {
      // Leaving the chat screen cancels its stream subscription. Stop native
      // decoding in that case so a later screen cannot race the old request.
      if (!completed && controller.isGenerating) {
        try {
          await controller.stop();
        } catch (error, stackTrace) {
          developer.log(
            'Could not stop Local AI generation cleanly.',
            name: 'LocalAi',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      _generationActive = false;
    }
  }

  Future<void> dispose() async {
    final initialization = _initializationFuture;
    if (initialization != null) {
      try {
        await initialization;
      } catch (_) {
        // A failed load has no active model to release.
      }
    }
    if (_generationActive && controller.isGenerating) {
      await controller.stop();
    }
    final currentController = _controller;
    if (currentController != null) {
      await currentController.dispose();
      _controller = null;
    }
    _initialized = false;
  }
}

class LocalAiException implements Exception {
  const LocalAiException(this.message);

  final String message;

  @override
  String toString() => message;
}
