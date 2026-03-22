import 'dart:async';

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
import '../../../core/services/quran_rag_service.dart';
import '../../../core/services/vector_store_service.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/utils/asr_normalization_pipeline.dart';
import '../../../core/utils/intent_parser.dart';
import '../../../core/utils/perf_trace.dart';
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
  HomeNotifier() : super(const HomeState());

  final _voiceService = VoiceService.instance;
  final _llmService = LlmService.instance;
  final _quranApi = QuranApiService.instance;
  final _quranRag = QuranRagService.instance;
  final _db = DatabaseService.instance;
  final _intentParser = IntentParser.instance;
  final _vectorStore = VectorStoreService.instance;

  String? _recordingPath;
  int _speechSessionId = 0;
  final Map<String, AsrNormalizationResult> _normalizationCache =
      <String, AsrNormalizationResult>{};

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

    // Run the offline normalization pipeline (with LLM rewrite on low confidence)
    final cacheKey = transcription.toLowerCase();
    var normalized = _normalizationCache[cacheKey];
    if (normalized == null) {
      normalized = AsrNormalizationPipeline.instance.process(transcription);
      if (normalized.needsLlmFallback) {
        final rewritePrompt =
            PromptTemplates.rewriteAsrTranscript(transcript: transcription);
        final buffer = StringBuffer();
        await for (final token in _llmService.generate(rewritePrompt)) {
          buffer.write(token);
        }
        final rewritten = buffer.toString().trim();
        if (rewritten.isNotEmpty) {
          normalized = AsrNormalizationPipeline.instance.process(rewritten);
        }
      }
      _normalizationCache[cacheKey] = normalized;
    }

    final normalizedIntent = normalized.toIntent();
    state = state.copyWith(transcription: normalized.cleanText);
    await processTextInput(
      normalized.cleanText,
      normalizedIntent: normalizedIntent,
    );
  }

  /// Process text input (from voice or direct text entry)
  Future<void> processTextInput(
    String text, {
    Intent? normalizedIntent,
  }) async {
    final traceTag = PerfTrace.nextTag('home.processTextInput');
    final totalSw = PerfTrace.start(traceTag, 'request');

    _speechSessionId += 1;
    _llmService.cancelGeneration();
    await _voiceService.stopPlayback();

    state = state.copyWith(
      voiceState: VoiceState.processing,
      transcription: text,
      response: null,
      error: null,
      currentVerse: null,
      citations: const <GroundingCitation>[],
    );
    PerfTrace.mark(traceTag, 'ui_reset', totalSw);

    // Save user message
    final saveUserSw = Stopwatch()..start();
    await _db.insertMessage(ChatMessage(
      id: _uuid.v4(),
      content: text,
      role: 'user',
      createdAt: DateTime.now(),
    ));
    PerfTrace.mark(traceTag, 'save_user_message', saveUserSw);

    // Parse intent
    final parseSw = Stopwatch()..start();
    final intent = normalizedIntent ?? _intentParser.parse(text);
    PerfTrace.mark(traceTag, 'intent_parse', parseSw);

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
      PerfTrace.end(traceTag, 'request_success', totalSw);
    } catch (e) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        error: 'Something went wrong: $e',
        citations: const <GroundingCitation>[],
      );
      PerfTrace.end(traceTag, 'request_error', totalSw);
    }
  }

  Future<void> _handleExplainAyah(Intent intent) async {
    final verseKey = intent.verseKey ?? '${intent.surahNumber ?? 1}:${intent.ayahNumber ?? 1}';
    final evidence = await _quranRag.retrieveVerseEvidence(
      verseKey,
      queryHint: intent.rawText,
    );
    if (evidence == null) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not retrieve Quran source material for verse $verseKey. Please try again.',
      );
      return;
    }

    final parts = evidence.verseKey.split(':');
    final surah = parts.length == 2 ? int.tryParse(parts[0]) ?? 1 : 1;
    final ayah = parts.length == 2 ? int.tryParse(parts[1]) ?? 1 : 1;
    state = state.copyWith(
      currentVerse: Verse(
        verseKey: evidence.verseKey,
        surahNumber: surah,
        ayahNumber: ayah,
        translationText: evidence.translationText,
      ),
    );

    final prompt = PromptTemplates.explainVerse(
      arabicText: '',
      translationText: evidence.translationText,
      tafsirText: evidence.tafsirText,
      tafsirSource: evidence.tafsirSource,
    );

    await _streamLlmResponse(
      prompt,
      intent,
      citations: <GroundingCitation>[
        GroundingCitation(
          verseKey: evidence.verseKey,
          sourceLabel: evidence.tafsirSource,
          excerpt: evidence.translationText,
        ),
      ],
    );
  }

  Future<void> _handleExplainSurah(Intent intent) async {
    final surahNum = intent.surahNumber ?? 1;
    final ayahCount = _quranApi.getAyahCountForSurah(surahNum);
    if (ayahCount == null || ayahCount <= 0) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not identify Surah $surahNum.',
      );
      return;
    }

    final sampleVerseKeys = _sampleSurahVerseKeys(surahNum, ayahCount);
  final evidence = await _buildGroundedVerseEvidence(sampleVerseKeys, maxItems: 3);
    if (evidence.isEmpty) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not retrieve enough Quran source material for Surah $surahNum from the bundled RAG database, so I will not generate an unsourced overview.',
      );
      return;
    }

    final primaryEvidence = evidence.first;
    final verseParts = primaryEvidence.verseKey.split(':');
    final currentSurah = verseParts.length == 2 ? int.tryParse(verseParts[0]) ?? surahNum : surahNum;
    final currentAyah = verseParts.length == 2 ? int.tryParse(verseParts[1]) ?? 1 : 1;
    final surahName = _displaySurahName(surahNum);

    state = state.copyWith(
      currentVerse: Verse(
        verseKey: primaryEvidence.verseKey,
        surahNumber: currentSurah,
        ayahNumber: currentAyah,
        translationText: primaryEvidence.translationText,
      ),
    );

    final prompt = PromptTemplates.groundedSurahOverview(
      surahName: surahName,
      surahNumber: surahNum,
      evidenceBlocks: evidence.take(2).map((item) => item.promptBlock).toList(),
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
    final verseKey = intent.verseKey ?? '${intent.surahNumber ?? 1}:${intent.ayahNumber ?? 1}';
    final evidence = await _quranRag.retrieveVerseEvidence(
      verseKey,
      queryHint: intent.rawText,
    );
    if (evidence == null) {
      state = state.copyWith(voiceState: VoiceState.idle, response: 'Verse not found.');
      return;
    }

    final parts = evidence.verseKey.split(':');
    final surah = parts.length == 2 ? int.tryParse(parts[0]) ?? 1 : 1;
    final ayah = parts.length == 2 ? int.tryParse(parts[1]) ?? 1 : 1;
    final verse = Verse(
      verseKey: evidence.verseKey,
      surahNumber: surah,
      ayahNumber: ayah,
      translationText: evidence.translationText,
    );

    state = state.copyWith(
      voiceState: VoiceState.idle,
      currentVerse: verse,
      response: '**$surah:$ayah**\n\n*${evidence.translationText}*',
      citations: const <GroundingCitation>[],
    );

    _saveAssistantMessage(state.response!, intent);
  }

  Future<void> _handleEmotionalGuidance(Intent intent) async {
    final emotion = intent.emotion ?? 'difficulty';

    // Query vector store for relevant Quran/emotional verses only (exclude hadith).
    // Use the English retrieval query so the embedding search hits English-only DB.
    final vectorQuery = intent.retrievalQuery.isNotEmpty
        ? intent.retrievalQuery
        : '$emotion ${intent.rawText}';
    final results = _vectorStore.queryByText(
      vectorQuery,
      topK: 5,
      filter: (e) {
        final kind = e.metadata['kind'] ?? '';
        return kind == 'emotional' || kind == 'quran_corpus';
      },
    );

    final relevantVerses = results
        .where((r) => (r.entry.metadata['verse_key'] ?? '').isNotEmpty)
        .map((r) {
          final key = r.entry.metadata['verse_key']!;
          // emotional entries store raw text; quran_corpus stores "Translation: ..."
          final rawContent = r.entry.content;
          final translation = rawContent.contains('Translation: ')
              ? rawContent
                  .split('\n')
                  .firstWhere((l) => l.startsWith('Translation: '), orElse: () => rawContent)
                  .replaceFirst('Translation: ', '')
              : rawContent;
          return '[QURAN]\nSurah: $key\nTranslation: $translation';
        })
        .take(2)
        .toList();

    if (relevantVerses.isEmpty) {
      relevantVerses.add('[QURAN]\nSurah: 94:5-6\nTranslation: For indeed, with hardship will be ease. Indeed, with hardship will be ease.');
      relevantVerses.add('[QURAN]\nSurah: 2:286\nTranslation: Allah does not burden a soul beyond that it can bear.');
    }

    final prompt = PromptTemplates.emotionalGuidance(
      emotion: emotion,
      userText: intent.rawText,
      relevantVerses: relevantVerses,
    );

    await _streamLlmResponse(prompt, intent);
  }

  Future<void> _handleGeneralQuestion(Intent intent) async {
    // Use English retrieval query for vector DB (may differ from rawText when
    // user spoke in Tamil / Hinglish / Arabic romanization).
    final ragQuery = intent.retrievalQuery.isNotEmpty
        ? intent.retrievalQuery
        : intent.rawText;
    final evidence = await _buildGlobalQuestionEvidence(ragQuery);

    if (evidence.isEmpty) {
      state = state.copyWith(
        voiceState: VoiceState.idle,
        response: 'I could not retrieve enough Quran source material for that question, so I will not generate an unsourced answer.',
      );
      return;
    }

    // Keep grounding compact to reduce first-token latency on mobile devices.
    final allEvidenceBlocks = evidence
      .take(2)
      .map((item) => item.promptBlock)
      .toList(growable: false);

    // Pass rawText (user's language) as the question so LLM responds in kind.
    final prompt = PromptTemplates.groundedGeneralQuestion(
      question: intent.rawText,
      evidenceBlocks: allEvidenceBlocks,
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
    final evidence = await _quranRag.retrieveGroundedEvidence(rawQuery, limit: 3);
    return evidence
        .map((item) => _GroundedVerseEvidence(
              verseKey: item.verseKey,
              translationText: item.translationText,
              tafsirText: item.tafsirText,
              tafsirSource: item.tafsirSource,
            ))
        .toList(growable: false);
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
    final evidence = await _quranRag.retrieveVerseEvidenceBatch(
      verseKeys,
      maxItems: maxItems,
    );
    return evidence
        .map((item) => _GroundedVerseEvidence(
              verseKey: item.verseKey,
              translationText: item.translationText,
              tafsirText: item.tafsirText,
              tafsirSource: item.tafsirSource,
            ))
        .toList(growable: false);
  }

  List<String> _sampleSurahVerseKeys(int surahNumber, int ayahCount) {
    if (ayahCount <= 0) {
      return const <String>[];
    }

    final ayahNumbers = <int>{
      1,
      (ayahCount * 0.25).round().clamp(1, ayahCount),
      ((ayahCount + 1) / 2).round(),
      (ayahCount * 0.75).round().clamp(1, ayahCount),
      ayahCount,
    };
    return ayahNumbers
        .where((ayahNumber) => ayahNumber >= 1 && ayahNumber <= ayahCount)
        .map((ayahNumber) => '$surahNumber:$ayahNumber')
        .toList(growable: false);
  }

  String _displaySurahName(int surahNumber) {
    if (surahNumber < 1 || surahNumber > SurahLookup.canonicalSurahNames.length) {
      return 'Surah $surahNumber';
    }

    final canonical = SurahLookup.canonicalSurahNames[surahNumber - 1];
    return canonical
        .split('-')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<void> _streamLlmResponse(
    String prompt,
    Intent intent, {
    List<GroundingCitation> citations = const <GroundingCitation>[],
  }) async {
    final traceTag = PerfTrace.nextTag('home.streamLlmResponse');
    final totalSw = PerfTrace.start(traceTag, 'stream');
    final promptLineCount = '\n'.allMatches(prompt).length + 1;
    final promptWordCount = prompt.trim().isEmpty
        ? 0
        : prompt.trim().split(RegExp(r'\s+')).length;
    final evidenceBlockCount = RegExp(r'\[QURAN\]|\[TAFSIR\]').allMatches(prompt).length;
    if (PerfTrace.enabled) {
      debugPrint(
        'PerfTrace[$traceTag] prompt_chars=${prompt.length} '
        'prompt_words=$promptWordCount prompt_lines=$promptLineCount '
        'evidence_blocks=$evidenceBlockCount citations=${citations.length}',
      );
    }
    state = state.copyWith(
      isStreaming: true,
      response: '',
      citations: citations,
    );
    PerfTrace.mark(traceTag, 'stream_state_initialized', totalSw);

    final buffer = StringBuffer();
    var lastUiEmit = DateTime.now();
    var charsSinceLastEmit = 0;
    bool first = true;
    bool firstUiEmit = true;

    await for (final token in _llmService.generate(prompt)) {
      buffer.write(token);
      charsSinceLastEmit += token.length;

      if (first) {
        PerfTrace.mark(traceTag, 'first_token_received', totalSw);
      }

      final now = DateTime.now();
      final shouldEmit =
          charsSinceLastEmit >= 24 ||
          now.difference(lastUiEmit) >= const Duration(milliseconds: 70) ||
          token.contains('\n');
      if (shouldEmit) {
        state = state.copyWith(response: buffer.toString());
        if (firstUiEmit) {
          firstUiEmit = false;
          PerfTrace.mark(traceTag, 'first_ui_emit', totalSw);
        }
        lastUiEmit = now;
        charsSinceLastEmit = 0;
      }

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
    PerfTrace.mark(traceTag, 'final_state_committed', totalSw);

    final saveAssistantSw = Stopwatch()..start();
    _saveAssistantMessage(fullResponse, intent);
    PerfTrace.mark(traceTag, 'save_assistant_message_dispatched', saveAssistantSw);

    // TTS playback (fire and forget)
    PerfTrace.mark(traceTag, 'tts_dispatch', totalSw);
    _speakResponse(fullResponse);
    PerfTrace.end(traceTag, 'stream', totalSw);
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

  String get promptBlock {
    final tafsirBlock = tafsirText.isNotEmpty
        ? '\n[TAFSIR]\nSource: $tafsirSource\nText: $tafsirText'
        : '';
    return '[QURAN]\nSurah: $verseKey\nTranslation: $translationText$tafsirBlock';
  }
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
