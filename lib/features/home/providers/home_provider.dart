import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/intent.dart';
import '../../../core/models/surah.dart';
import '../../../core/models/verse.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/llm_service.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/services/vector_store_service.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/utils/intent_parser.dart';
import '../../../core/utils/prompt_templates.dart';

const _uuid = Uuid();
const _unset = Object();

/// Voice pipeline state
enum VoiceState { idle, listening, processing, speaking }

class HomeState {
  final VoiceState voiceState;
  final String? transcription;
  final String? response;
  final bool isStreaming;
  final String? error;
  final Verse? currentVerse;
  final List<GroundingCitation> citations;

  const HomeState({
    this.voiceState = VoiceState.idle,
    this.transcription,
    this.response,
    this.isStreaming = false,
    this.error,
    this.currentVerse,
    this.citations = const <GroundingCitation>[],
  });

  HomeState copyWith({
    VoiceState? voiceState,
    Object? transcription = _unset,
    Object? response = _unset,
    bool? isStreaming,
    Object? error = _unset,
    Object? currentVerse = _unset,
    List<GroundingCitation>? citations,
  }) {
    return HomeState(
      voiceState: voiceState ?? this.voiceState,
      transcription: identical(transcription, _unset)
          ? this.transcription
          : transcription as String?,
      response: identical(response, _unset)
          ? this.response
          : response as String?,
      isStreaming: isStreaming ?? this.isStreaming,
      error: identical(error, _unset) ? this.error : error as String?,
      currentVerse: identical(currentVerse, _unset)
          ? this.currentVerse
          : currentVerse as Verse?,
      citations: citations ?? this.citations,
    );
  }
}

class HomeNotifier extends StateNotifier<HomeState> {
  HomeNotifier() : super(const HomeState()) {
    unawaited(_llmService.initialize());
  }

  final _voiceService = VoiceService.instance;
  final _llmService = LlmService.instance;
  final _quranApi = QuranApiService.instance;
  final _db = DatabaseService.instance;
  final _intentParser = IntentParser.instance;
  final _vectorStore = VectorStoreService.instance;

  String? _recordingPath;
  int _speechSessionId = 0;
  final Map<String, _VoiceNormalizationResult> _voiceNormalizationCache =
      <String, _VoiceNormalizationResult>{};

  /// Start/stop voice recording toggle
  Future<void> toggleVoice() async {
    if (state.voiceState == VoiceState.listening) {
      await _stopAndProcess();
    } else if (state.voiceState == VoiceState.speaking) {
      await _interruptSpeechAndListen();
    } else if (state.voiceState == VoiceState.idle) {
      await _startListening();
    }
  }

  Future<void> _interruptSpeechAndListen() async {
    _speechSessionId += 1;
    await _voiceService.stopPlayback();

    if (state.voiceState == VoiceState.speaking) {
      state = state.copyWith(voiceState: VoiceState.idle);
    }

    await _startListening();
  }

  Future<void> _startListening() async {
    state = const HomeState(voiceState: VoiceState.listening);
    _recordingPath = await _voiceService.startRecording();
    if (_recordingPath == null) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        error: 'Failed to start recording. Check microphone permission.',
      );
    }
  }

  Future<void> _stopAndProcess() async {
    state = state.copyWith(voiceState: VoiceState.processing);

    final audioPath = await _voiceService.stopRecording();
    if (audioPath == null) {
      state = state.copyWith(voiceState: VoiceState.idle, error: 'Recording failed');
      return;
    }

    // Transcribe
    final transcription = await _voiceService.transcribe(audioPath);
    if (transcription == null || transcription.isEmpty) {
      state = state.copyWith(voiceState: VoiceState.idle, error: 'Could not understand speech');
      return;
    }

    final normalizedCommand = await _normalizeVoiceCommand(transcription);
    final normalizedIntent = _intentFromNormalizedCommand(normalizedCommand);

    state = state.copyWith(transcription: normalizedCommand.cleanText);
    await processTextInput(
      normalizedCommand.cleanText,
      normalizedIntent: normalizedIntent,
    );
  }

  /// Process text input (from voice or direct text entry)
  Future<void> processTextInput(
    String text, {
    Intent? normalizedIntent,
  }) async {
    state = state.copyWith(
      voiceState: VoiceState.processing,
      transcription: text,
      response: null,
      error: null,
      currentVerse: null,
      citations: const <GroundingCitation>[],
    );

    // Save user message
    await _db.insertMessage(ChatMessage(
      id: _uuid.v4(),
      content: text,
      role: 'user',
      createdAt: DateTime.now(),
    ));

    // Parse intent
    final intent = normalizedIntent ?? _intentParser.parse(text);

    try {
      switch (intent.type) {
        case IntentType.explainAyah:
          await _handleExplainAyah(intent);
          break;
        case IntentType.explainSurah:
          await _handleExplainSurah(intent);
          break;
        case IntentType.playAudio:
          await _handlePlayAudio(intent);
          break;
        case IntentType.translation:
          await _handleTranslation(intent);
          break;
        case IntentType.tafsir:
          await _handleExplainAyah(intent); // Same flow
          break;
        case IntentType.emotionalGuidance:
          await _handleEmotionalGuidance(intent);
          break;
        case IntentType.askGeneralQuestion:
          await _handleGeneralQuestion(intent);
          break;
      }
    } catch (e) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        error: 'Something went wrong: $e',
        citations: const <GroundingCitation>[],
      );
    }
  }

  Future<_VoiceNormalizationResult> _normalizeVoiceCommand(
    String transcription,
  ) async {
    final locallyCorrected = _applyIslamicTermCorrections(transcription).trim();
    if (locallyCorrected.isEmpty) {
      return _fallbackVoiceNormalization(transcription);
    }

    final cacheKey = locallyCorrected.toLowerCase();
    final cached = _voiceNormalizationCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    try {
      unawaited(_llmService.initialize());
      final rawResponse = await _llmService
          .generateComplete(
            PromptTemplates.normalizeVoiceCommand(userInput: locallyCorrected),
          )
          .timeout(const Duration(seconds: 8));
      final parsed = _safeParseNormalizedCommand(
        rawResponse,
        fallbackInput: locallyCorrected,
      );
      _voiceNormalizationCache[cacheKey] = parsed;
      debugPrint(
        'ASR normalize: "$transcription" -> intent=${parsed.intent}, surah=${parsed.surahNumber}, ayah=${parsed.ayahNumber}, clean="${parsed.cleanText}"',
      );
      return parsed;
    } catch (error) {
      debugPrint('ASR normalize skipped: $error');
      final fallback = _fallbackVoiceNormalization(locallyCorrected);
      _voiceNormalizationCache[cacheKey] = fallback;
      return fallback;
    }
  }

  Intent _intentFromNormalizedCommand(_VoiceNormalizationResult result) {
    final fallbackIntent = _intentParser.parse(result.cleanText);
    final type = _intentTypeFromLabel(result.intent);
    if (type == null) {
      return fallbackIntent;
    }

    final requiresSurahOnly =
        type == IntentType.explainSurah || type == IntentType.playAudio;
    final requiresVerseReference =
        type == IntentType.explainAyah ||
        type == IntentType.translation ||
        type == IntentType.tafsir;

    if (requiresSurahOnly && result.surahNumber == null) {
      return fallbackIntent;
    }

    if (requiresVerseReference &&
        (result.surahNumber == null || result.ayahNumber == null)) {
      return fallbackIntent;
    }

    return Intent(
      type: type,
      surahNumber: result.surahNumber,
      ayahNumber: result.ayahNumber,
      rawText: result.cleanText,
    );
  }

  IntentType? _intentTypeFromLabel(String label) {
    switch (label.trim().toLowerCase()) {
      case 'explain_surah':
        return IntentType.explainSurah;
      case 'explain_ayah':
        return IntentType.explainAyah;
      case 'play_audio':
        return IntentType.playAudio;
      case 'translation':
        return IntentType.translation;
      case 'tafsir':
        return IntentType.tafsir;
      case 'emotional_guidance':
        return IntentType.emotionalGuidance;
      case 'ask_general_question':
        return IntentType.askGeneralQuestion;
      default:
        return null;
    }
  }

  _VoiceNormalizationResult _safeParseNormalizedCommand(
    String text, {
    required String fallbackInput,
  }) {
    try {
      final jsonStart = text.indexOf('{');
      final jsonEnd = text.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
        return _fallbackVoiceNormalization(fallbackInput);
      }

      final jsonString = text.substring(jsonStart, jsonEnd + 1);
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        return _fallbackVoiceNormalization(fallbackInput);
      }

      final map = decoded.cast<String, dynamic>();
      final cleanText = _normalizedCleanText(
        map['clean_text'] as String?,
        fallbackInput,
      );
      final surahName = _normalizedNullableString(map['surah']);
      final surahNumber = _resolveNormalizedSurah(
        surahName,
        cleanText: cleanText,
        fallbackInput: fallbackInput,
      );

      return _VoiceNormalizationResult(
        intent: _normalizedNullableString(map['intent']) ?? 'unknown',
        surahName: surahName,
        surahNumber: surahNumber,
        ayahNumber: _normalizedAyah(map['ayah']),
        cleanText: cleanText,
      );
    } catch (_) {
      return _fallbackVoiceNormalization(fallbackInput);
    }
  }

  _VoiceNormalizationResult _fallbackVoiceNormalization(String input) {
    final cleanText = _normalizedCleanText(null, input);
    return _VoiceNormalizationResult(
      intent: 'unknown',
      surahName: null,
      surahNumber: _resolveNormalizedSurah(
        null,
        cleanText: cleanText,
        fallbackInput: input,
      ),
      ayahNumber: null,
      cleanText: cleanText,
    );
  }

  String _normalizedCleanText(String? cleanText, String fallbackInput) {
    final candidate = cleanText?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      return _applyIslamicTermCorrections(candidate).trim();
    }
    return _applyIslamicTermCorrections(fallbackInput).trim();
  }

  String? _normalizedNullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  int? _normalizedAyah(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      final ayah = value.toInt();
      return ayah > 0 ? ayah : null;
    }
    final parsed = int.tryParse(value.toString().trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  int? _resolveNormalizedSurah(
    String? surahName, {
    required String cleanText,
    required String fallbackInput,
  }) {
    final direct = surahName == null ? null : SurahLookup.findSurahNumber(surahName);
    if (direct != null) {
      return direct;
    }

    final fromCleanText = SurahLookup.findSurahNumber(cleanText);
    if (fromCleanText != null) {
      return fromCleanText;
    }

    return SurahLookup.findSurahNumber(fallbackInput);
  }

  String _applyIslamicTermCorrections(String input) {
    var normalized = input
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) {
      return normalized;
    }

    const replacements = <String, String>{
      'qoran': 'Quran',
      'koran': 'Quran',
      'kuran': 'Quran',
      'suram': 'surah',
      'allahh': 'Allah',
      'mohammad': 'Muhammad',
      'muhamad': 'Muhammad',
      'sura': 'surah',
      'sorah': 'surah',
      'surat': 'surah',
      'aya': 'ayah',
      'ayat': 'ayah',
      'aayat': 'ayah',
      'tafseer': 'tafsir',
      'tafsirr': 'tafsir',
      'duaah': 'dua',
      'zikr': 'dhikr',
      'ramadhan': 'Ramadan',
      'azan': 'adhan',
      'salat': 'salah',
      'qadar': 'qadr',
      'kadr': 'qadr',
      'falak': 'falaq',
      'iklaas': 'ikhlas',
      'iklas': 'ikhlas',
      'yaseen': 'yasin',
      'ya seen': 'yasin',
      'baqara': 'baqarah',
      'bakara': 'baqarah',
      'imraan': 'imran',
      'rehman': 'rahman',
      'rahmaan': 'rahman',
      'rukh': 'mulk',
      'mulq': 'mulk',
      'mulkh': 'mulk',
      'kausar': 'kawthar',
      'kauthar': 'kawthar',
    };

    normalized = _applyReplacements(normalized, replacements);

    if (RegExp(r"^(?:let'?s|lets|let us|lex|less)\s+play\b", caseSensitive: false)
            .hasMatch(normalized) &&
        RegExp(r'\b(?:sur[a-z]*|ayah?|verse|tafsir|quran)\b', caseSensitive: false)
            .hasMatch(normalized)) {
      normalized = normalized.replaceFirst(
        RegExp(r"^(?:let'?s|lets|let us|lex|less)\s+play\b", caseSensitive: false),
        'explain',
      );
    }

    normalized = normalized.replaceAllMapped(
      RegExp(r'\b(?:explan|explane|xplain)\b', caseSensitive: false),
      (_) => 'explain',
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'\b(?:suratul|surah|surat|suram|sura|sorah)([a-z]{2,})\b', caseSensitive: false),
      (match) => 'surah ${match.group(1)}',
    );

    normalized = normalized.replaceAllMapped(
      RegExp(r'\bverse\s+(\d+)\s+(\d+)\b', caseSensitive: false),
      (match) => 'verse ${match.group(1)}:${match.group(2)}',
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'\bayah\s+(\d+)\s+(\d+)\b', caseSensitive: false),
      (match) => 'ayah ${match.group(1)}:${match.group(2)}',
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'\bsurah\s+(\d+)\s+ayah\s+(\d+)\b', caseSensitive: false),
      (match) => 'ayah ${match.group(1)}:${match.group(2)}',
    );
    normalized = SurahLookup.normalizeSurahMentions(normalized);
    normalized = normalized
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    normalized = _applyReplacements(normalized, replacements)
        .replaceAllMapped(
          RegExp(r'\bsurah\s+([a-z][a-z0-9\- ]*)', caseSensitive: false),
          (match) => SurahLookup.normalizeSurahMentions(match.group(0) ?? ''),
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return normalized;
  }

  String _applyReplacements(String input, Map<String, String> replacements) {
    var normalized = input;
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(
        RegExp('\\b${RegExp.escape(source)}\\b', caseSensitive: false),
        target,
      );
    });
    return normalized;
  }

  Future<void> _handleExplainAyah(Intent intent) async {
    final surah = intent.surahNumber ?? 1;
    final ayah = intent.ayahNumber ?? 1;

    final verse = await _quranApi.getVerse(surah, ayah);
    if (verse == null) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not find verse $surah:$ayah. Please try again.',
      );
      return;
    }

    state = state.copyWith(currentVerse: verse);

    final tafsirText = await _quranApi.getVerseTafsir(surah, ayah);
    if (tafsirText == null || tafsirText.isEmpty) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not retrieve a tafsir source for verse $surah:$ayah, so I will not generate an unsourced explanation.',
      );
      return;
    }

    final tafsirSource = await _quranApi.getVerseTafsirSource(surah, ayah);

    final prompt = PromptTemplates.explainVerse(
      arabicText: verse.arabicText ?? '',
      translationText: verse.translationText ?? '',
      tafsirText: tafsirText,
      tafsirSource: tafsirSource,
    );

    await _streamLlmResponse(
      prompt,
      intent,
      citations: <GroundingCitation>[
        GroundingCitation(
          verseKey: verse.verseKey,
          sourceLabel: tafsirSource ?? 'Retrieved tafsir',
          excerpt: verse.translationText,
        ),
      ],
    );
  }

  Future<void> _handleExplainSurah(Intent intent) async {
    final surahNum = intent.surahNumber ?? 1;
    final verses = await _quranApi.getSurahVerses(surahNum);

    if (verses.isEmpty) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'Could not fetch surah $surahNum.',
      );
      return;
    }

    final firstVerse = verses.first;
    state = state.copyWith(currentVerse: firstVerse);

    final sampleVerseKeys = _sampleSurahVerseKeys(verses);
    final evidence = await _buildGroundedVerseEvidence(sampleVerseKeys);
    if (evidence.isEmpty) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not retrieve enough tafsir-backed source material for Surah $surahNum, so I will not generate an unsourced overview.',
      );
      return;
    }

    final prompt = PromptTemplates.groundedSurahOverview(
      surahName: 'Surah $surahNum',
      surahNumber: surahNum,
      evidenceBlocks: evidence.map((item) => item.promptBlock).toList(),
    );

    await _streamLlmResponse(
      prompt,
      intent,
      citations: _citationsFromEvidence(evidence),
    );
  }

  Future<void> _handlePlayAudio(Intent intent) async {
    if (intent.surahNumber == null) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not identify which surah or verse to play. Please say something like "play surah mulk" or "play ayah 2:255".',
      );
      return;
    }

    final surahNum = intent.surahNumber ?? 1;
    final ayahNum = intent.ayahNumber ?? 1;
    final audioUrl = await _quranApi.getAudioUrl(surahNum, ayahNum);

    if (audioUrl != null) {
      final targetLabel = '$surahNum:$ayahNum';
      state = state.copyWith(
        voiceState: VoiceState.speaking,
        response: 'Playing recitation for verse $targetLabel...',
      );

      try {
        await _voiceService.playUrl(audioUrl);
        state = state.copyWith(voiceState: VoiceState.idle);
      } catch (e) {
        state = state.copyWith(
          voiceState: VoiceState.idle,
          error: 'Could not play recitation: $e',
        );
      }
      return;
    }

    state = state.copyWith(
      voiceState: VoiceState.idle,
      response: 'Audio not available for verse $surahNum:$ayahNum.',
    );
  }

  Future<void> _handleTranslation(Intent intent) async {
    final surah = intent.surahNumber ?? 1;
    final ayah = intent.ayahNumber ?? 1;

    final verse = await _quranApi.getVerse(surah, ayah);
    if (verse == null) {
      state = state.copyWith(voiceState: VoiceState.idle, response: 'Verse not found.');
      return;
    }

    state = state.copyWith(
      voiceState: VoiceState.idle,
      currentVerse: verse,
      response: '**$surah:$ayah**\n\n${verse.arabicText ?? ""}\n\n*${verse.translationText ?? ""}*',
      citations: const <GroundingCitation>[],
    );

    _saveAssistantMessage(state.response!, intent);
  }

  Future<void> _handleEmotionalGuidance(Intent intent) async {
    final emotion = intent.emotion ?? 'difficulty';

    // Query vector store for relevant verses
    final results = _vectorStore.queryByText(
      '$emotion ${intent.rawText}',
      topK: 3,
    );

    final relevantVerses = results.map((r) {
      final key = r.entry.metadata['verse_key'] ?? '';
      return 'Verse $key: ${r.entry.content}';
    }).toList();

    if (relevantVerses.isEmpty) {
      // Fallback with pre-defined comforting text
      relevantVerses.add('Verse 94:5-6: For indeed, with hardship will be ease. Indeed, with hardship will be ease.');
      relevantVerses.add('Verse 2:286: Allah does not burden a soul beyond that it can bear.');
    }

    final prompt = PromptTemplates.emotionalGuidance(
      emotion: emotion,
      userText: intent.rawText,
      relevantVerses: relevantVerses,
    );

    await _streamLlmResponse(prompt, intent);
  }

  Future<void> _handleGeneralQuestion(Intent intent) async {
    final evidence = await _buildGlobalQuestionEvidence(intent.rawText);

    if (evidence.isEmpty) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not retrieve enough Quran source material for that question, so I will not generate an unsourced answer.',
      );
      return;
    }

    final prompt = PromptTemplates.groundedGeneralQuestion(
      question: intent.rawText,
      evidenceBlocks: evidence.map((item) => item.promptBlock).toList(),
    );
    await _streamLlmResponse(
      prompt,
      intent,
      citations: _citationsFromEvidence(evidence),
    );
  }

  Future<List<_GroundedVerseEvidence>> _buildGlobalQuestionEvidence(
    String rawQuery,
  ) async {
    final query = _normalizeSearchQuery(rawQuery);
    final searchResults = await _quranApi.search(query);
    final verseKeys = searchResults
        .map((result) => result.verseKey)
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList();

    return _buildGroundedVerseEvidence(verseKeys, maxItems: 3);
  }

  List<GroundingCitation> _citationsFromEvidence(
    List<_GroundedVerseEvidence> evidence,
  ) {
    return evidence
        .map((item) => GroundingCitation(
              verseKey: item.verseKey,
              sourceLabel: item.tafsirSource,
              excerpt: item.translationText,
            ))
        .toList(growable: false);
  }

  Future<List<_GroundedVerseEvidence>> _buildGroundedVerseEvidence(
    List<String> verseKeys, {
    int maxItems = 3,
  }) async {
    final evidence = <_GroundedVerseEvidence>[];

    for (final verseKey in verseKeys) {
      if (evidence.length >= maxItems) {
        break;
      }

      final parts = verseKey.split(':');
      if (parts.length != 2) {
        continue;
      }

      final surahNumber = int.tryParse(parts[0]);
      final ayahNumber = int.tryParse(parts[1]);
      if (surahNumber == null || ayahNumber == null) {
        continue;
      }

      final verse = await _quranApi.getVerse(surahNumber, ayahNumber);
      final tafsirText = await _quranApi.getVerseTafsir(surahNumber, ayahNumber);
      if (verse == null || tafsirText == null || tafsirText.isEmpty) {
        continue;
      }

      final tafsirSource = await _quranApi.getVerseTafsirSource(surahNumber, ayahNumber);
      evidence.add(_GroundedVerseEvidence(
        verseKey: verseKey,
        translationText: verse.translationText ?? '',
        tafsirText: tafsirText,
        tafsirSource: tafsirSource ?? 'retrieved tafsir source',
      ));
    }

    return evidence;
  }

  List<String> _sampleSurahVerseKeys(List<Verse> verses) {
    if (verses.isEmpty) {
      return const <String>[];
    }

    final indexes = <int>{0, verses.length ~/ 2, verses.length - 1};
    return indexes
        .where((index) => index >= 0 && index < verses.length)
        .map((index) => verses[index].verseKey)
        .toList();
  }

  String _normalizeSearchQuery(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) {
      return input.trim();
    }

    return normalized;
  }

  Future<void> _streamLlmResponse(
    String prompt,
    Intent intent, {
    List<GroundingCitation> citations = const <GroundingCitation>[],
  }) async {
    state = state.copyWith(
      isStreaming: true,
      response: '',
      citations: citations,
    );

    final buffer = StringBuffer();
    bool first = true;

    await for (final token in _llmService.generate(prompt)) {
      buffer.write(token);
      state = state.copyWith(response: buffer.toString());

      if (first) {
        first = false;
        state = state.copyWith(voiceState: VoiceState.processing);
      }
    }

    final fullResponse = buffer.toString();
    state = state.copyWith(
      isStreaming: false,
      voiceState: VoiceState.idle,
      response: fullResponse,
      citations: citations,
    );

    _saveAssistantMessage(fullResponse, intent);

    // TTS playback (fire and forget)
    _speakResponse(fullResponse);
  }

  void _saveAssistantMessage(String response, Intent intent) {
    _db.insertMessage(ChatMessage(
      id: _uuid.v4(),
      content: response,
      role: 'assistant',
      intent: intent.type.name,
      verseKey: intent.verseKey,
      createdAt: DateTime.now(),
    ));
  }

  Future<void> _speakResponse(String text) async {
    final sessionId = ++_speechSessionId;
    state = state.copyWith(voiceState: VoiceState.speaking);
    try {
      await _voiceService.speak(text);
    } finally {
      if (mounted && _speechSessionId == sessionId && state.voiceState == VoiceState.speaking) {
        state = state.copyWith(voiceState: VoiceState.idle);
      }
    }
  }

  /// Stop everything
  void stop() {
    _llmService.cancelGeneration();
    _voiceService.stopPlayback();
    state = state.copyWith(voiceState: VoiceState.idle, isStreaming: false);
  }
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>((ref) {
  return HomeNotifier();
});

class _GroundedVerseEvidence {
  const _GroundedVerseEvidence({
    required this.verseKey,
    required this.translationText,
    required this.tafsirText,
    required this.tafsirSource,
  });

  final String verseKey;
  final String translationText;
  final String tafsirText;
  final String tafsirSource;

  String get promptBlock =>
      'Verse $verseKey\nTranslation: $translationText\nTafsir Source: $tafsirSource\nTafsir: $tafsirText';
}

class _VoiceNormalizationResult {
  const _VoiceNormalizationResult({
    required this.intent,
    required this.surahName,
    required this.surahNumber,
    required this.ayahNumber,
    required this.cleanText,
  });

  final String intent;
  final String? surahName;
  final int? surahNumber;
  final int? ayahNumber;
  final String cleanText;
}

class GroundingCitation {
  const GroundingCitation({
    required this.verseKey,
    required this.sourceLabel,
    this.excerpt,
  });

  final String verseKey;
  final String sourceLabel;
  final String? excerpt;
}
