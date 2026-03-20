import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_manager.dart';
import 'native_bridge.dart';

/// Voice service managing the full pipeline: Record → ASR → TTS playback
class TtsVoiceOption {
  const TtsVoiceOption({
    required this.id,
    required this.label,
    required this.subtitle,
  });

  final String id;
  final String label;
  final String subtitle;
}

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  static const String _ttsGainPreferenceKey = 'voice_service_tts_gain';
  static const String _playbackVolumePreferenceKey = 'voice_service_playback_volume';
  static const String _ttsVoicePreferenceKey = 'voice_service_tts_voice';
  static const String _defaultTtsVoiceId = 'F1';
  static const double _defaultTtsGain = 1.8;
  static const double _defaultPlaybackVolume = 1.0;
  static const double _minTtsGain = 1.0;
  static const double _maxTtsGain = 2.5;
  static const double _minPlaybackVolume = 0.6;
  static const double _maxPlaybackVolume = 1.0;
  static const List<TtsVoiceOption> _supportedTtsVoices = <TtsVoiceOption>[
    TtsVoiceOption(
      id: 'F1',
      label: 'Female 1',
      subtitle: 'Clear, balanced, default voice',
    ),
    TtsVoiceOption(
      id: 'F2',
      label: 'Female 2',
      subtitle: 'Alternative female voice style',
    ),
    TtsVoiceOption(
      id: 'M1',
      label: 'Male 1',
      subtitle: 'Deeper male voice style',
    ),
    TtsVoiceOption(
      id: 'M2',
      label: 'Male 2',
      subtitle: 'Alternative male voice style',
    ),
  ];

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;
  bool _asrReady = false;
  bool _ttsReady = false;
  bool _stopPlaybackRequested = false;
  double _ttsGain = _defaultTtsGain;
  double _playbackVolume = _defaultPlaybackVolume;
  String _ttsVoiceId = _defaultTtsVoiceId;

  bool get isRecording => _isRecording;
  bool get asrReady => _asrReady;
  bool get ttsReady => _ttsReady;
  double get ttsGain => _ttsGain;
  double get playbackVolume => _playbackVolume;
  String get ttsVoiceId => _ttsVoiceId;
  List<TtsVoiceOption> get supportedTtsVoices =>
      List<TtsVoiceOption>.unmodifiable(_supportedTtsVoices);

  final _playbackStateController = StreamController<bool>.broadcast();
  Stream<bool> get isPlaying => _playbackStateController.stream;

  Future<void> initializeAudioSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _ttsGain = _clampTtsGain(
      prefs.getDouble(_ttsGainPreferenceKey) ?? _defaultTtsGain,
    );
    _playbackVolume = _clampPlaybackVolume(
      prefs.getDouble(_playbackVolumePreferenceKey) ?? _defaultPlaybackVolume,
    );
    _ttsVoiceId = _normalizeVoiceId(
      prefs.getString(_ttsVoicePreferenceKey) ?? _defaultTtsVoiceId,
    );
    await _player.setVolume(_playbackVolume);

    if (_ttsReady && NativeBridge.instance.isAvailable) {
      NativeBridge.instance.ttsSetGain(_ttsGain);
    }
  }

  Future<void> setAudioBoost({
    required double ttsGain,
    required double playbackVolume,
  }) async {
    _ttsGain = _clampTtsGain(ttsGain);
    _playbackVolume = _clampPlaybackVolume(playbackVolume);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ttsGainPreferenceKey, _ttsGain);
    await prefs.setDouble(_playbackVolumePreferenceKey, _playbackVolume);

    await _player.setVolume(_playbackVolume);

    if (_ttsReady && NativeBridge.instance.isAvailable) {
      NativeBridge.instance.ttsSetGain(_ttsGain);
    }
  }

  Future<List<TtsVoiceOption>> listAvailableTtsVoices() async {
    await initializeAudioSettings();
    await ModelManager.instance.initialize();

    final voiceDir = Directory('${ModelManager.instance.modelPath(ModelType.tts)}/voice_styles');
    if (!await voiceDir.exists()) {
      return const <TtsVoiceOption>[
        TtsVoiceOption(
          id: 'F1',
          label: 'Female 1',
          subtitle: 'Clear, balanced, default voice',
        ),
      ];
    }

    final availableIds = <String>{};
    await for (final entity in voiceDir.list()) {
      if (entity is! File) {
        continue;
      }

      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (!name.endsWith('.json')) {
        continue;
      }

      final id = name.substring(0, name.length - 5);
      if (id.isNotEmpty) {
        availableIds.add(id);
      }
    }

    final available = _supportedTtsVoices
        .where((voice) => availableIds.contains(voice.id))
        .toList(growable: false);
    if (available.isNotEmpty) {
      return available;
    }

    return const <TtsVoiceOption>[
      TtsVoiceOption(
        id: 'F1',
        label: 'Female 1',
        subtitle: 'Clear, balanced, default voice',
      ),
    ];
  }

  Future<void> setTtsVoice(String voiceId) async {
    final normalizedVoiceId = _normalizeVoiceId(voiceId);
    if (_ttsVoiceId == normalizedVoiceId) {
      return;
    }

    _ttsVoiceId = normalizedVoiceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ttsVoicePreferenceKey, _ttsVoiceId);

    if (!_ttsReady || !NativeBridge.instance.isAvailable) {
      return;
    }

    await stopPlayback();
    _ttsReady = false;
    await initTts();
  }

  /// Initialize ASR model
  Future<bool> initAsr() async {
    await initializeAudioSettings();

    if (_asrReady) return true;
    if (!NativeBridge.instance.isAvailable) return false;

    try {
      await ModelManager.instance.initialize();
      final isDownloaded =
          await ModelManager.instance.isModelDownloaded(ModelType.asr);
      if (!isDownloaded) {
        debugPrint('VoiceService: ASR model not downloaded');
        return false;
      }

      final modelDir = ModelManager.instance.modelPath(ModelType.asr);
      if (modelDir.isEmpty) {
        debugPrint('VoiceService: ASR model directory is empty');
        return false;
      }

      final initialized = await Isolate.run<bool>(() {
        final result = NativeBridge.instance.initWhisper(modelDir);
        return result.isSuccess;
      });
      _asrReady = initialized;
      debugPrint(
        'VoiceService: ASR init ${_asrReady ? "OK" : "FAILED"}'
        '${_asrReady ? "" : ": Could not load ASR model"}',
      );
      return _asrReady;
    } catch (e) {
      debugPrint('VoiceService: ASR init error: $e');
      return false;
    }
  }

  /// Initialize TTS model
  Future<bool> initTts() async {
    await initializeAudioSettings();

    if (_ttsReady) return true;
    if (!NativeBridge.instance.isAvailable) return false;

    try {
      await ModelManager.instance.initialize();
      final isDownloaded =
          await ModelManager.instance.isModelDownloaded(ModelType.tts);
      if (!isDownloaded) {
        debugPrint('VoiceService: TTS model not downloaded');
        return false;
      }

      final modelDir = ModelManager.instance.modelPath(ModelType.tts);
      if (modelDir.isEmpty) {
        debugPrint('VoiceService: TTS model directory is empty');
        return false;
      }

      final initResult = NativeBridge.instance.ttsInit(modelDir, _ttsVoiceId);

      _ttsReady = initResult.isSuccess;
      if (_ttsReady) {
        NativeBridge.instance.ttsSetGain(_ttsGain);
      }
      debugPrint(
        'VoiceService: TTS init ${_ttsReady ? "OK" : "FAILED"}'
        '${_ttsReady ? "" : " (code=${initResult.errorCode})"}',
      );
      return _ttsReady;
    } catch (e) {
      debugPrint('VoiceService: TTS init error: $e');
      return false;
    }
  }

  /// Start recording audio from microphone
  Future<String?> startRecording() async {
    await initializeAudioSettings();
    await stopPlayback();

    if (_isRecording) return null;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('VoiceService: No microphone permission');
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}/noor_voice_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        sampleRate: 16000,
        bitRate: 256000,
      ),
      path: filePath,
    );

    _isRecording = true;
    debugPrint('VoiceService: Recording started → $filePath');
    return filePath;
  }

  /// Stop recording and return the audio file path
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    final path = await _recorder.stop();
    _isRecording = false;
    debugPrint('VoiceService: Recording stopped → $path');
    return path;
  }

  /// Transcribe an audio file using ASR
  Future<String?> transcribe(String audioPath) async {
    if (!NativeBridge.instance.isAvailable) {
      debugPrint('VoiceService: Native bridge not available for ASR');
      return null;
    }

    if (!_asrReady) {
      final ready = await initAsr();
      if (!ready) {
        debugPrint('VoiceService: ASR not ready for transcription');
        return null;
      }
    }

    debugPrint('VoiceService: Transcribing $audioPath');
    final buffer = StringBuffer();
    await for (final partial in NativeBridge.instance.transcribeAudioStream(audioPath)) {
      buffer
        ..clear()
        ..write(partial);
    }

    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// Synthesize text to speech and return the WAV file path
  Future<String?> synthesize(String text) async {
    if (!NativeBridge.instance.isAvailable) {
      debugPrint('VoiceService: Native bridge not available for TTS');
      return null;
    }

    if (!_ttsReady) {
      return null;
    }

    if (text.trim().isEmpty) {
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/noor_tts_${DateTime.now().millisecondsSinceEpoch}.wav';

    final ok = NativeBridge.instance.ttsSynthesize(text, outputPath);
    if (!ok) {
      debugPrint('VoiceService: TTS synthesis failed');
      return null;
    }

    return outputPath;
  }

  /// Speak text using TTS with audio playback
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    await initializeAudioSettings();
    await _preparePlayback();
    _stopPlaybackRequested = false;

    if (!_ttsReady) {
      final ready = await initTts();
      if (!ready) {
        debugPrint('VoiceService: Skipping TTS playback because initialization failed');
        return;
      }
    }

    // Split into sentences for pipelined playback
    final sentences = _splitSentences(text);
    if (sentences.isEmpty) return;

    _playbackStateController.add(true);

    try {
      await _player.stop();

      for (final sentence in sentences) {
        if (_stopPlaybackRequested) {
          break;
        }

        final wavPath = await synthesize(sentence);
        if (wavPath == null) continue;

        final file = File(wavPath);
        if (!await file.exists()) continue;

        await _player.setFilePath(wavPath);
        await _player.setVolume(_playbackVolume);
        await _player.play();
        await _waitForPlaybackEnd();
      }
    } finally {
      await _finishPlayback();
      _playbackStateController.add(false);
    }
  }

  /// Play remote recitation audio directly from a URL.
  Future<void> playUrl(String url) async {
    await initializeAudioSettings();
    await _preparePlayback();
    _stopPlaybackRequested = false;

    _playbackStateController.add(true);

    try {
      await _player.stop();
      await _player.setUrl(url);
      await _player.setVolume(_playbackVolume);
      await _player.play();

      await _waitForPlaybackEnd();
    } finally {
      await _finishPlayback();
      _playbackStateController.add(false);
    }
  }

  /// Play multiple remote audio URLs sequentially.
  Future<void> playUrls(List<String> urls) async {
    final queue = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    if (queue.isEmpty) {
      return;
    }

    await initializeAudioSettings();
    await _preparePlayback();
    _stopPlaybackRequested = false;

    _playbackStateController.add(true);

    try {
      await _player.stop();

      for (final url in queue) {
        if (_stopPlaybackRequested) {
          break;
        }

        await _player.setUrl(url);
        await _player.setVolume(_playbackVolume);
        await _player.play();
        await _waitForPlaybackEnd();
      }
    } finally {
      await _finishPlayback();
      _playbackStateController.add(false);
    }
  }

  /// Stop any ongoing playback
  Future<void> stopPlayback() async {
    _stopPlaybackRequested = true;
    await _player.stop();
    await _finishPlayback();
    _playbackStateController.add(false);
  }

  List<String> _splitSentences(String text) {
    return text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _playbackStateController.close();
  }

  Future<void> _preparePlayback() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    await session.setActive(true);
  }

  Future<void> _finishPlayback() async {
    final session = await AudioSession.instance;
    await session.setActive(false);
  }

  Future<void> _waitForPlaybackEnd() {
    return _player.playerStateStream.firstWhere(
      (state) => !state.playing &&
          (state.processingState == ProcessingState.completed ||
              state.processingState == ProcessingState.idle),
    );
  }

  double _clampTtsGain(double value) {
    return value.clamp(_minTtsGain, _maxTtsGain).toDouble();
  }

  double _clampPlaybackVolume(double value) {
    return value.clamp(_minPlaybackVolume, _maxPlaybackVolume).toDouble();
  }

  String _normalizeVoiceId(String value) {
    final trimmed = value.trim();
    if (_supportedTtsVoices.any((voice) => voice.id == trimmed)) {
      return trimmed;
    }
    return _defaultTtsVoiceId;
  }
}
