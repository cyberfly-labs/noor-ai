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
  static const int _maxTtsChunkLength = 220;
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
  int _playbackSessionId = 0;
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
    final spokenText = _normalizeSpokenText(text);
    if (spokenText.isEmpty) {
      return;
    }

    await initializeAudioSettings();
    await _preparePlayback();
    final sessionId = ++_playbackSessionId;
    _stopPlaybackRequested = false;

    if (!_ttsReady) {
      final ready = await initTts();
      if (!ready || sessionId != _playbackSessionId) {
        debugPrint('VoiceService: Skipping TTS playback because initialization failed');
        return;
      }
    }

    final speechChunks = _buildSpeechChunks(spokenText);
    if (speechChunks.isEmpty) {
      return;
    }

    final pendingChunks = List<String>.from(speechChunks);

    _playbackStateController.add(true);

    try {
      await _player.stop();

      for (var i = 0; i < pendingChunks.length; i += 1) {
        final chunk = pendingChunks[i];
        if (_stopPlaybackRequested || sessionId != _playbackSessionId) {
          break;
        }

        final wavPath = await synthesize(chunk);
        if (wavPath == null || sessionId != _playbackSessionId) {
          final splitChunks = _splitFailedSynthesisChunk(chunk);
          if (splitChunks != null) {
            pendingChunks
              ..removeAt(i)
              ..insertAll(i, splitChunks);
            i -= 1;
            continue;
          }
          debugPrint('VoiceService: Skipping unsynthesizable chunk (${chunk.length} chars)');
          continue;
        }

        if (!await _waitForWavFile(wavPath) || sessionId != _playbackSessionId) {
          continue;
        }

        try {
          // Reset player state from completed → idle before loading the next
          // chunk; avoids just_audio Android/iOS state-machine quirks.
          await _player.stop();
          if (sessionId != _playbackSessionId) break;

          await _player.setFilePath(wavPath);
          await _player.setVolume(_playbackVolume);
          await _player.play();
          await _waitForPlaybackEnd(sessionId);
        } catch (e) {
          debugPrint('VoiceService: chunk playback error: $e');
          // continue to the next chunk rather than aborting the whole response
        }
      }
    } finally {
      if (sessionId == _playbackSessionId) {
        await _finishPlayback();
        _playbackStateController.add(false);
      }
    }
  }

  /// Play remote recitation audio directly from a URL.
  Future<void> playUrl(String url) async {
    await initializeAudioSettings();
    await _preparePlayback();
    final sessionId = ++_playbackSessionId;
    _stopPlaybackRequested = false;

    _playbackStateController.add(true);

    try {
      await _player.stop();
      if (sessionId != _playbackSessionId) {
        return;
      }
      await _player.setUrl(url);
      await _player.setVolume(_playbackVolume);
      await _player.play();

      await _waitForPlaybackEnd(sessionId);
    } finally {
      if (sessionId == _playbackSessionId) {
        await _finishPlayback();
        _playbackStateController.add(false);
      }
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
    final sessionId = ++_playbackSessionId;
    _stopPlaybackRequested = false;

    _playbackStateController.add(true);

    try {
      await _player.stop();

      for (final url in queue) {
        if (_stopPlaybackRequested || sessionId != _playbackSessionId) {
          break;
        }

        await _player.setUrl(url);
        await _player.setVolume(_playbackVolume);
        await _player.play();
        await _waitForPlaybackEnd(sessionId);
      }
    } finally {
      if (sessionId == _playbackSessionId) {
        await _finishPlayback();
        _playbackStateController.add(false);
      }
    }
  }

  /// Stop any ongoing playback
  Future<void> stopPlayback() async {
    _stopPlaybackRequested = true;
    _playbackSessionId += 1;
    await _player.stop();
    await _finishPlayback();
    _playbackStateController.add(false);
  }

  String _normalizeSpokenText(String text) {
    var normalized = text
        // Strip emojis (will trip the on-device TTS engine)
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u2600-\u27BF]'), '');

    // Use replaceAllMapped for capture-group substitutions. String.replaceAll
    // does not expand $1-style groups and would leak literal "$1" into speech.
    normalized = normalized
        // Strip markdown headers (# / ## / ###)
        .replaceAllMapped(
          RegExp(r'(^|\n)\s*#{1,6}\s*'),
          (m) => m.group(1) ?? '',
        )
        // Strip markdown bold (**text** / __text__)
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1) ?? '')
        // Strip markdown italic (*text* / _text_)
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1) ?? '')
        // Strip any remaining lone * or _ markers
        .replaceAll(RegExp(r'[*_]+'), '')
        // Strip inline code (`code`)
        .replaceAll(RegExp(r'`+[^`]*`+'), '')
        // Strip markdown links [text](url) -> text
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1) ?? '')
        // Strip bare URLs
        .replaceAll(RegExp(r'https?://\S+'), '')
        // Strip markdown blockquotes (> )
        .replaceAllMapped(
          RegExp(r'(^|\n)\s*>\s*'),
          (m) => m.group(1) ?? '',
        )
        // Strip horizontal rules (---, ***, ___)
        .replaceAllMapped(
          RegExp(r'(^|\n)\s*[-*_]{3,}\s*(\n|$)'),
          (m) => m.group(1) ?? '',
        )
        // Strip numbered list markers (1. 2. etc.)
        .replaceAllMapped(
          RegExp(r'(^|\n)\s*\d+\.\s*'),
          (m) => m.group(1) ?? '',
        )
        // Strip bullet list markers (- / * / +)
        .replaceAllMapped(
          RegExp(r'(^|\n)\s*[-*+]\s+'),
          (m) => m.group(1) ?? '',
        )
        // Strip [QURAN], [TAFSIR], [HADITH] block labels
        .replaceAll(RegExp(r'\[(QURAN|TAFSIR|HADITH)\]\s*', caseSensitive: false), '')
        // Collapse whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return normalized;
  }

  List<String> _buildSpeechChunks(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }

    if (normalized.length <= _maxTtsChunkLength) {
      return <String>[normalized];
    }

    // Split only on sentence-ending punctuation — NOT on colons, to avoid
    // creating micro-chunks from verse refs like "2:153" or labels like "Quran:".
    final sentences = normalized
        .split(RegExp(r'(?<=[.!?;])\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final chunk = buffer.toString().trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }
      buffer.clear();
    }

    for (final sentence in sentences) {
      if (sentence.length > _maxTtsChunkLength) {
        if (buffer.isNotEmpty) {
          flush();
        }
        chunks.addAll(_splitLongChunk(sentence));
        continue;
      }

      final separator = buffer.isEmpty ? '' : ' ';
      final candidateLength = buffer.length + separator.length + sentence.length;
      if (candidateLength > _maxTtsChunkLength && buffer.isNotEmpty) {
        flush();
      }

      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(sentence);
    }

    if (buffer.isNotEmpty) {
      flush();
    }

    return chunks;
  }

  List<String> _splitLongChunk(String text) {
    final words = text.split(RegExp(r'\s+'));
    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final word in words) {
      if (word.isEmpty) {
        continue;
      }

      final separator = buffer.isEmpty ? '' : ' ';
      final candidateLength = buffer.length + separator.length + word.length;
      if (candidateLength > _maxTtsChunkLength && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }

      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(word);
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) {
      chunks.add(tail);
    }

    return chunks;
  }

  List<String>? _splitFailedSynthesisChunk(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 80) {
      return null;
    }

    final mid = trimmed.length ~/ 2;
    var splitAt = trimmed.lastIndexOf(' ', mid);
    if (splitAt < 24) {
      splitAt = trimmed.indexOf(' ', mid);
    }
    if (splitAt < 24 || splitAt >= trimmed.length - 24) {
      return null;
    }

    final left = trimmed.substring(0, splitAt).trim();
    final right = trimmed.substring(splitAt + 1).trim();
    if (left.isEmpty || right.isEmpty) {
      return null;
    }
    return <String>[left, right];
  }

  Future<bool> _waitForWavFile(String path) async {
    final file = File(path);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) {
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
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

  Future<void> _waitForPlaybackEnd(int sessionId) async {
    // Phase 1: confirm play() actually started before we wait for it to end.
    // playerStateStream is a BehaviorSubject that replays the last value, so
    // after chunk N completes (state = completed), subscribing for chunk N+1
    // would immediately match that stale "completed" and return early.
    // Waiting for playing==true first prevents that race condition.
    final started = await _player.playerStateStream
        .firstWhere(
          (s) => sessionId != _playbackSessionId || s.playing,
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => _player.playerState,
        );

    if (sessionId != _playbackSessionId || !started.playing) return;

    // Phase 2: playback has started — wait for it to finish.
    await _player.playerStateStream.firstWhere(
      (s) =>
          sessionId != _playbackSessionId ||
          (!s.playing &&
              (s.processingState == ProcessingState.completed ||
                  s.processingState == ProcessingState.idle)),
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
