import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

class LocalAiService {
  static final LocalAiService instance = LocalAiService._internal();

  LocalAiService._internal();

  static const String modelUrl =
      'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf';

  static const String modelFileName = 'gemma-3-1b-it-Q4_K_M.gguf';

  final LlamaController controller = LlamaController();

  bool _initialized = false;
  bool _initializing = false;
  bool _downloading = false;

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

  Future<bool> isModelDownloaded() async {
    final path = await modelPath;
    final file = File(path);

    if (!await file.exists()) {
      return false;
    }

    final size = await file.length();

    // The model should be hundreds of megabytes.
    // This prevents an interrupted/empty download from being
    // considered a valid model.
    return size > 100 * 1024 * 1024;
  }

  Future<void> downloadModel({
    void Function(double progress)? onProgress,
  }) async {
    if (_downloading) {
      throw StateError('Model download is already in progress.');
    }

    if (await isModelDownloaded()) {
      onProgress?.call(1.0);
      return;
    }

    _downloading = true;

    try {
      final modelDirectory = await _getModelDirectory();

      final finalFile = File('${modelDirectory.path}/$modelFileName');

      final temporaryFile = File('${modelDirectory.path}/$modelFileName.part');

      // Remove an old incomplete download.
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }

      final request = http.Request('GET', Uri.parse(modelUrl));

      final response = await request.send();

      if (response.statusCode != 200) {
        throw HttpException(
          'Model download failed with HTTP ${response.statusCode}.',
        );
      }

      final totalBytes = response.contentLength ?? 0;
      var downloadedBytes = 0;

      final sink = temporaryFile.openWrite();

      try {
        await for (final chunk in response.stream) {
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
        throw Exception(
          'Model download was incomplete. '
          'Downloaded $downloadedBytes of $totalBytes bytes.',
        );
      }

      if (!await temporaryFile.exists()) {
        throw Exception('Downloaded model file was not created.');
      }

      final downloadedSize = await temporaryFile.length();

      if (downloadedSize < 100 * 1024 * 1024) {
        throw Exception(
          'Downloaded model file is unexpectedly small '
          '($downloadedSize bytes).',
        );
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }

      await temporaryFile.rename(finalFile.path);

      onProgress?.call(1.0);
    } finally {
      _downloading = false;
    }
  }

  Future<void> initialize({
    void Function(double progress)? onDownloadProgress,
  }) async {
    if (_initialized || _initializing) {
      return;
    }

    _initializing = true;

    try {
      if (!await isModelDownloaded()) {
        await downloadModel(onProgress: onDownloadProgress);
      }

      final path = await modelPath;

      final gpu = await controller.detectGpu();

      int gpuLayers = 0;

      if (gpu.vulkanSupported) {
        gpuLayers = gpu.recommendedGpuLayers;
      }

      await controller.loadModel(
        modelPath: path,
        threads: 4,
        contextSize: 2048,
        gpuLayers: gpuLayers,
      );

      _initialized = true;
    } finally {
      _initializing = false;
    }
  }

  Stream<String> ask(String question, {List<ChatMessage>? conversation}) {
    if (!_initialized) {
      throw StateError('Local AI model is not initialized.');
    }

    final messages = <ChatMessage>[
      ChatMessage(
        role: 'system',
        content: '''
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
''',
      ),
    ];

    if (conversation != null) {
      messages.addAll(conversation);
    }

    messages.add(ChatMessage(role: 'user', content: question));

    return controller.generateChat(
      messages: messages,
      maxTokens: 300,
      temperature: 0.7,
      topP: 0.9,
      topK: 40,
      repeatPenalty: 1.1,
    );
  }

  Future<void> dispose() async {
    if (_initialized) {
      await controller.dispose();
      _initialized = false;
    }
  }
}
