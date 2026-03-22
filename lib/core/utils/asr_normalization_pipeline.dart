import '../models/intent.dart';
import '../models/surah.dart';
import 'intent_parser.dart';
import 'named_verse_registry.dart';
import 'quran_query_helpers.dart';

/// Result produced by [AsrNormalizationPipeline.process].
class AsrNormalizationResult {
  const AsrNormalizationResult({
    required this.cleanText,
    required this.canonicalQuery,
    required this.intent,
    this.surahNumber,
    this.ayahNumber,
    required this.needsLlmFallback,
    String? retrievalQuery,
    this.responseLanguage = 'en',
  }) : retrievalQuery = retrievalQuery ?? canonicalQuery;

  /// Cleaned, corrected text — ready for display and for [IntentParser].
  final String cleanText;

  /// Canonical rewritten query, e.g. "Explain Surah Al-Baqarah verse 255".
  /// Use this as the display label in the chat transcript.
  final String canonicalQuery;

  /// Always-English query for vector-DB retrieval.  Structured from resolved
  /// entities so the embedding model gets clean English input regardless of
  /// the user's original language.
  final String retrievalQuery;

  /// BCP-47-style language hint detected from the raw ASR input.
  /// Values: 'en', 'ar', 'ta', 'hi'.  Used so the LLM can respond in the
  /// user's language even when [retrievalQuery] is English.
  final String responseLanguage;

  /// Intent detected by the pipeline's offline rule engine.
  final IntentType intent;

  /// Resolved surah number (1-114), or null when unresolved.
  final int? surahNumber;

  /// Resolved ayah number, or null when not present.
  final int? ayahNumber;

  /// True when the pipeline could not confidently resolve a Quran reference.
  /// The caller should consider re-running the pipeline on an LLM-rewritten
  /// transcript before dispatching the intent.
  final bool needsLlmFallback;

  /// Convert this result to an [Intent] for the app routing layer.
  ///
  /// Returns an intent built from the pipeline's resolved fields when the
  /// pipeline found a structured Quran reference.  Falls back to
  /// [IntentParser] when the pipeline produced only a general question,
  /// but always carries the English [retrievalQuery] and [responseLanguage].
  Intent toIntent() {
    if (intent != IntentType.askGeneralQuestion || surahNumber != null) {
      return Intent(
        type: intent,
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
        rawText: cleanText,
        retrievalQuery: retrievalQuery,
        responseLanguage: responseLanguage,
      );
    }
    // General question — delegate type/emotion detection to IntentParser but
    // keep our English retrieval query and language hint.
    final parsed = IntentParser.instance.parse(cleanText);
    return Intent(
      type: parsed.type,
      surahNumber: parsed.surahNumber,
      ayahNumber: parsed.ayahNumber,
      emotion: parsed.emotion,
      rawText: cleanText,
      retrievalQuery: retrievalQuery,
      responseLanguage: responseLanguage,
    );
  }
}

/// Fully offline, layered ASR query normalization pipeline for Quran queries.
///
/// Runs entirely on-device (no LLM call). Sets
/// [AsrNormalizationResult.needsLlmFallback] when it cannot confidently
/// resolve a reference, so the caller can optionally run an LLM rewrite and
/// re-process.
///
/// **Pipeline stages:**
/// 1. Language detection   — detects script/language from raw input
/// 2. Text cleaning        — lowercase, strip punctuation, collapse whitespace
/// 3. Term corrections     — Islamic ASR misspellings + multilingual aliases
/// 4. Named-verse lookup   — exact / contains match against [namedVerseMap]
/// 5. Surah + ayah extract — multiple ASR-friendly numeric/named patterns
/// 6. Intent detection     — rule-based keyword matching, priority-ordered
/// 7. Retrieval query      — English-only query for vector-DB embedding search
/// 8. Canonical rewriting  — display form, e.g. "Explain Surah Al-Mulk verse 1"
/// 9. Confidence scoring   — sets [needsLlmFallback] flag
class AsrNormalizationPipeline {
  const AsrNormalizationPipeline._();

  static const AsrNormalizationPipeline instance = AsrNormalizationPipeline._();

  // ── Islamic ASR term corrections ───────────────────────────────────────────

  // Multi-word phrases — applied first so they take priority over single-word pass.
  static const Map<String, String> _phraseCorrections = <String, String>{
    'ya seen':         'yasin',
    'kul hu':          'ikhlas',
    'kul huvallahu':   'ikhlas',
    'ik loss':         'ikhlas',
    'ik las':          'ikhlas',
  };

  // Single-word corrections — covers common ASR mis-transcriptions.
  static const Map<String, String> _wordCorrections = <String, String>{
    // Quran
    'qoran':       'quran',
    'koran':       'quran',
    'kuran':       'quran',
    // Surah keyword
    'suratul':     'surah',
    'suram':       'surah',
    'surat':       'surah',
    'sora':        'surah',
    'sorah':       'surah',
    'sura':        'surah',
    // Ayah keyword
    'aya':         'ayah',
    'ayat':        'ayah',
    'aayat':       'ayah',
    // Tafsir
    'tafseer':     'tafsir',
    'tafsirr':     'tafsir',
    // Islamic terms
    'duaah':       'dua',
    'zikr':        'dhikr',
    'ramadhan':    'ramadan',
    'azan':        'adhan',
    'salat':       'salah',
    'qadar':       'qadr',
    'kadr':        'qadr',
    'falak':       'falaq',
    'iklaas':      'ikhlas',
    'iklas':       'ikhlas',
    'allahh':      'allah',
    'mohammad':    'muhammad',
    'muhamad':     'muhammad',
    // Surah name ASR corrections
    'yaseen':      'yasin',
    'yaasin':      'yasin',
    'baqara':      'baqarah',
    'bakara':      'baqarah',
    'bakra':       'baqarah',
    'baqra':       'baqarah',
    'imraan':      'imran',
    'rehman':      'rahman',
    'rahmaan':     'rahman',
    'rukh':        'mulk',
    'mulq':        'mulk',
    'mulkh':       'mulk',
    'kausar':      'kawthar',
    'kauthar':     'kawthar',
    'kousar':      'kawthar',
    'kahaf':       'kahf',
    'kahhf':       'kahf',
    'fatiha':      'al-fatihah',
    'fateha':      'al-fatihah',
    'qureish':     'quraysh',
    'quraish':     'quraysh',
    'kafiroon':    'kafirun',
    'naas':        'nas',
    'pheel':       'fil',
    'feel':        'fil',
    'humaza':      'humazah',
    'takasur':     'takathur',
    'maaun':       'maun',
    'zalzala':     'zalzalah',
    // Verb typos
    'explan':      'explain',
    'explane':     'explain',
    'xplain':      'explain',
    // Hinglish intent verbs (normalise to English equivalents)
    'batao':       'explain',
    'samjhao':     'explain',
    'padho':       'recite',
    'suno':        'listen',
    'tilawat':     'recitation',
    'tarjuma':     'translation',
    'tarjumah':    'translation',
    'arth':        'meaning',
    'matlab':      'meaning',
    'tafheemul':   'tafsir',
    'tafsirul':    'tafsir',
  };

  // ── Intent keyword table (priority order — first match wins) ───────────────
  static const List<(String, IntentType)> _intentKeywords = [
    ('recite',      IntentType.playAudio),
    ('recitation',  IntentType.playAudio),
    ('play',        IntentType.playAudio),
    ('listen',      IntentType.playAudio),
    ('read aloud',  IntentType.playAudio),
    ('tafsir',      IntentType.tafsir),
    ('tafseer',     IntentType.tafsir),
    ('exegesis',    IntentType.tafsir),
    ('commentary',  IntentType.tafsir),
    ('translate',   IntentType.translation),
    ('translation', IntentType.translation),
    ('explain',     IntentType.explainAyah),
    ('meaning',     IntentType.explainAyah),
    ('what does',   IntentType.explainAyah),
    ('what is',     IntentType.explainAyah),
    ('how',         IntentType.explainAyah),
  ];

  // Noise words stripped during surah-name scanning (stage 5 word scan).
  static const Set<String> _noiseWords = {
    'explain', 'meaning', 'translate', 'translation', 'tafsir', 'tafseer',
    'recite', 'recitation', 'play', 'listen', 'tell', 'about', 'what', 'is',
    'the', 'a', 'an', 'of', 'for', 'me', 'i', 'please', 'show', 'open',
    'read', 'from', 'verse', 'ayah', 'surah', 'chapter', 'how', 'why', 'to',
    'and', 'in', 'with', 'quran', 'does',
  };

  // ── Public entry point ─────────────────────────────────────────────────────

  /// Runs the full normalization pipeline on [rawAsrText] and returns a
  /// structured [AsrNormalizationResult].
  AsrNormalizationResult process(String rawAsrText) {
    if (rawAsrText.trim().isEmpty) {
      return const AsrNormalizationResult(
        cleanText: '',
        canonicalQuery: '',
        intent: IntentType.askGeneralQuestion,
        needsLlmFallback: false,
      );
    }

    // Stage 1 — detect language from raw input before cleaning strips script
    final responseLanguage = _detectLanguage(rawAsrText);

    // Stage 2 — clean
    final cleaned = _cleanText(rawAsrText);

    // Stage 3 — term corrections
    final corrected = _applyTermCorrections(cleaned);

    // Stage 4 — named-verse alias lookup.
    // Check the cleaned (pre-correction) text first so that aliases containing
    // "ayat" (e.g. "ayat noor") are matched before the word-correction pass
    // converts "ayat" → "ayah".
    final namedResult = _lookupNamedVerse(cleaned) ?? _lookupNamedVerse(corrected);
    if (namedResult != null) {
      // Preserve detected language on named-verse hits
      return AsrNormalizationResult(
        cleanText: namedResult.cleanText,
        canonicalQuery: namedResult.canonicalQuery,
        intent: namedResult.intent,
        surahNumber: namedResult.surahNumber,
        ayahNumber: namedResult.ayahNumber,
        needsLlmFallback: namedResult.needsLlmFallback,
        retrievalQuery: namedResult.retrievalQuery,
        responseLanguage: responseLanguage,
      );
    }

    // Stage 5 — extract surah + ayah
    final (surahNumber, ayahNumber) = _extractSurahAyah(corrected);

    // Stage 6 — detect intent
    final intent = _detectIntent(
      corrected,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
    );

    // Stage 7 — build English retrieval query (always English for vector DB)
    final retrievalQuery = _buildRetrievalQuery(
      corrected: corrected,
      intent: intent,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
    );

    // Stage 8 — canonical query rewriting (display form)
    final canonical = _rewriteQuery(
      text: corrected,
      intent: intent,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
    );

    // Stage 9 — confidence scoring
    final needsFallback = _needsLlmFallback(
      corrected: corrected,
      surahNumber: surahNumber,
      intent: intent,
    );

    return AsrNormalizationResult(
      cleanText: corrected,
      canonicalQuery: canonical,
      intent: intent,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      needsLlmFallback: needsFallback,
      retrievalQuery: retrievalQuery,
      responseLanguage: responseLanguage,
    );
  }

  // ── Public helpers for cross-component use ────────────────────────────────

  /// Generates an always-English retrieval query from typed-input intent fields.
  /// Delegates to [QuranQueryHelpers] — called by [IntentParser] so the typed
  /// path benefits from multilingual topic mapping without a circular import.
  static String buildRetrievalQueryFromIntent(Intent intent) {
    return QuranQueryHelpers.buildEnglishRetrievalQuery(
      correctedText: intent.rawText.toLowerCase(),
      intent: intent.type,
      surahNumber: intent.surahNumber,
      ayahNumber: intent.ayahNumber,
    );
  }

  /// Detects the response language from arbitrary raw input text.
  /// Returns a BCP-47-style code: 'en', 'ar', 'ta', 'hi'.
  static String detectLanguageCode(String text) =>
      QuranQueryHelpers.detectResponseLanguage(text);

  // ── Stage 1: Language detection ───────────────────────────────────────────

  String _detectLanguage(String rawText) =>
      QuranQueryHelpers.detectResponseLanguage(rawText);

  // ── Stage 2: Text cleaning ─────────────────────────────────────────────────

  String _cleanText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s:]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── Stage 2: Term corrections ──────────────────────────────────────────────

  String _applyTermCorrections(String input) {
    var text = input;

    // Multi-word phrases first
    for (final entry in _phraseCorrections.entries) {
      text = text.replaceAll(
        RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false),
        entry.value,
      );
    }

    // Single-word replacements
    final singleWordPattern = RegExp(
      r'\b(' +
          _wordCorrections.keys.map(RegExp.escape).join('|') +
          r')\b',
      caseSensitive: false,
    );
    text = text.replaceAllMapped(
      singleWordPattern,
      (m) => _wordCorrections[m.group(1)?.toLowerCase() ?? ''] ?? (m.group(0) ?? ''),
    );

    // Fix "surahX" (no space after prefix) → "surah X"
    text = text.replaceAllMapped(
      RegExp(r'\bsurah([a-z]{2,})\b', caseSensitive: false),
      (m) => 'surah ${m.group(1)}',
    );

    // Normalise "verse N N" / "ayah N N" → "verse N:N"
    text = text.replaceAllMapped(
      RegExp(r'\b(verse|ayah)\s+(\d{1,3})\s+(\d{1,3})\b', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}:${m.group(3)}',
    );

    // Normalise "let's play …" → "explain …" when it looks like a Quran query
    if (RegExp(r"^(?:let'?s|lets|let us)\s+play\b", caseSensitive: false)
            .hasMatch(text) &&
        RegExp(r'\b(?:surah?|ayah?|verse|tafsir|quran)\b', caseSensitive: false)
            .hasMatch(text)) {
      text = text.replaceFirst(
        RegExp(r"^(?:let'?s|lets|let us)\s+play\b", caseSensitive: false),
        'explain',
      );
    }

    // Apply SurahLookup canonical name normalisation only for explicit "surah <name>"
    // mentions that lack a trailing number; do NOT call normalizeSurahMentions on
    // the whole string as it greedily consumes trailing ayah numbers.
    text = text.replaceAllMapped(
      RegExp(r'\bsurah\s+([a-z][a-z0-9 \-]+?)(?=\s+(?:ayah|verse|\d)|$)', caseSensitive: false),
      (m) {
        final candidate = m.group(1)?.trim() ?? '';
        final num = SurahLookup.findSurahNumber(candidate);
        if (num == null || num < 1 || num > SurahLookup.canonicalSurahNames.length) {
          return m.group(0) ?? '';
        }
        return 'surah ${SurahLookup.canonicalSurahNames[num - 1]}';
      },
    );

    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ── Stage 3: Named-verse alias lookup ─────────────────────────────────────

  AsrNormalizationResult? _lookupNamedVerse(String text) {
    // Exact match
    final exact = namedVerseMap[text];
    if (exact != null) return _buildNamedVerseResult(text, exact);

    // Contains-match — longest key first to avoid short-key collisions
    final sortedKeys = namedVerseMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      if (text.contains(key)) {
        return _buildNamedVerseResult(text, namedVerseMap[key]!);
      }
    }
    return null;
  }

  AsrNormalizationResult _buildNamedVerseResult(String cleanText, NamedVerseRef ref) {
    final surahName = _formatSurahName(ref.surah);
    final intent = ref.ayah != null ? IntentType.explainAyah : IntentType.explainSurah;
    final canonical = ref.ayah != null
        ? 'Explain Surah $surahName verse ${ref.ayah}'
        : 'Explain Surah $surahName';
    final retrieval = ref.ayah != null
        ? 'Surah $surahName verse ${ref.ayah} meaning explanation'
        : 'Surah $surahName themes overview message';
    return AsrNormalizationResult(
      cleanText: cleanText,
      canonicalQuery: canonical,
      intent: intent,
      surahNumber: ref.surah,
      ayahNumber: ref.ayah,
      needsLlmFallback: false,
      retrievalQuery: retrieval,
    );
  }

  // ── Stage 4: Surah + ayah extraction ──────────────────────────────────────

  (int?, int?) _extractSurahAyah(String text) {
    // Pattern A: "2:255"
    final colonMatch = RegExp(r'\b(\d{1,3}):(\d{1,3})\b').firstMatch(text);
    if (colonMatch != null) {
      return (int.tryParse(colonMatch.group(1)!), int.tryParse(colonMatch.group(2)!));
    }

    // Pattern B: "surah 2 ayah 255" / "chapter 2 verse 255"
    final numericSurahAyah = RegExp(
      r'\b(?:surah|chapter)\s+(\d{1,3})\s+(?:ayah|verse)\s+(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (numericSurahAyah != null) {
      return (
        int.tryParse(numericSurahAyah.group(1)!),
        int.tryParse(numericSurahAyah.group(2)!),
      );
    }

    // Pattern C: "baqarah ayah 255" / "surah al-baqarah verse 255"
    final namedExplicitAyah = RegExp(
      r'\b(?:surah\s+)?([a-z][a-z0-9\-]+(?:\s+[a-z][a-z0-9\-]+)?)\s+(?:ayah|verse)\s+(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (namedExplicitAyah != null) {
      final surahNum = SurahLookup.findSurahNumber(namedExplicitAyah.group(1)!);
      final ayahNum = int.tryParse(namedExplicitAyah.group(2)!);
      if (surahNum != null && ayahNum != null) return (surahNum, ayahNum);
    }

    // Pattern D: "baqarah 255" / "surah mulk 28" (named + bare number)
    final namedBareAyah = RegExp(
      r'\b(?:surah\s+)?([a-z][a-z0-9\-]+(?:\s+[a-z][a-z0-9\-]+)?)\s+(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (namedBareAyah != null) {
      final surahNum = SurahLookup.findSurahNumber(namedBareAyah.group(1)!);
      final ayahNum = int.tryParse(namedBareAyah.group(2)!);
      // Sanity bound: ayah numbers go up to 286 (Al-Baqarah)
      if (surahNum != null && ayahNum != null && ayahNum >= 1 && ayahNum <= 286) {
        return (surahNum, ayahNum);
      }
    }

    // Pattern E: surah only (no ayah)
    return (_resolveSurahFromText(text), null);
  }

  int? _resolveSurahFromText(String text) {
    // Explicit "surah <name>"
    final surahPrefix = RegExp(r'\bsurah\s+([a-z][a-z0-9\- ]+)', caseSensitive: false)
        .firstMatch(text);
    if (surahPrefix != null) {
      final num = SurahLookup.findSurahNumber(surahPrefix.group(1)!.trim());
      if (num != null) return num;
    }

    // Scan individual words and two-word combos (exact matching to avoid false positives)
    final words = text.split(RegExp(r'\s+'));
    for (var i = 0; i < words.length; i++) {
      if (_isNoise(words[i])) continue;
      final single = SurahLookup.findExactSurahNumber(words[i]);
      if (single != null) return single;
      if (i + 1 < words.length && !_isNoise(words[i + 1])) {
        final pair = SurahLookup.findExactSurahNumber('${words[i]} ${words[i + 1]}');
        if (pair != null) return pair;
      }
    }

    // Last resort: fuzzy match on full corrected text
    return SurahLookup.findSurahNumber(text);
  }

  bool _isNoise(String word) => _noiseWords.contains(word.toLowerCase());

  // ── Stage 5: Intent detection ──────────────────────────────────────────────

  IntentType _detectIntent(
    String text, {
    required int? surahNumber,
    required int? ayahNumber,
  }) {
    for (final (keyword, intentType) in _intentKeywords) {
      if (!text.contains(keyword)) continue;

      // Unambiguous Quran intents: always decisive regardless of extracted refs.
      if (intentType == IntentType.playAudio ||
          intentType == IntentType.tafsir ||
          intentType == IntentType.translation) {
        return intentType;
      }

      // Ambiguous intents (explain / meaning / what is / how): only apply when
      // a Quran reference was actually resolved; otherwise fall through to the
      // reference-based inference below to avoid misclassifying general queries.
      if (surahNumber != null || ayahNumber != null) {
        if (intentType == IntentType.explainAyah &&
            ayahNumber == null &&
            surahNumber != null) {
          return IntentType.explainSurah;
        }
        return intentType;
      }
    }

    // No keyword matched (or keyword matched but no reference resolved)
    if (surahNumber != null && ayahNumber != null) return IntentType.explainAyah;
    if (surahNumber != null) return IntentType.explainSurah;
    return IntentType.askGeneralQuestion;
  }

  // ── Stage 7: English retrieval query construction ─────────────────────────

  /// Delegates to [QuranQueryHelpers.buildEnglishRetrievalQuery].
  String _buildRetrievalQuery({
    required String corrected,
    required IntentType intent,
    int? surahNumber,
    int? ayahNumber,
  }) {
    return QuranQueryHelpers.buildEnglishRetrievalQuery(
      correctedText: corrected,
      intent: intent,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
    );
  }

  // ── Stage 8: Canonical query rewriting ────────────────────────────────────

  String _rewriteQuery({
    required String text,
    required IntentType intent,
    int? surahNumber,
    int? ayahNumber,
  }) {
    final surahName = surahNumber != null ? _formatSurahName(surahNumber) : null;

    switch (intent) {
      case IntentType.playAudio:
        if (surahName != null && ayahNumber != null) {
          return 'Recite Surah $surahName verse $ayahNumber';
        }
        return 'Recite Surah ${surahName ?? text}';

      case IntentType.tafsir:
        if (surahName != null && ayahNumber != null) {
          return 'Tafsir of Surah $surahName verse $ayahNumber';
        }
        if (surahName != null) return 'Tafsir of Surah $surahName';
        return 'Tafsir: $text';

      case IntentType.translation:
        if (surahName != null && ayahNumber != null) {
          return 'Translation of Surah $surahName verse $ayahNumber';
        }
        if (surahName != null) return 'Translation of Surah $surahName';
        return 'Translation: $text';

      case IntentType.explainAyah:
        if (surahName != null && ayahNumber != null) {
          return 'Explain Surah $surahName verse $ayahNumber';
        }
        return text;

      case IntentType.explainSurah:
        if (surahName != null) return 'Explain Surah $surahName';
        return text;

      case IntentType.emotionalGuidance:
      case IntentType.askGeneralQuestion:
        return text;
    }
  }

  // ── Stage 9: Confidence scoring ────────────────────────────────────────────

  bool _needsLlmFallback({
    required String corrected,
    required int? surahNumber,
    required IntentType intent,
  }) {
    // Explicit "surah" in text but no surah resolved → ASR likely garbled the name
    if (surahNumber == null &&
        RegExp(r'\bsurah\b', caseSensitive: false).hasMatch(corrected)) {
      return true;
    }

    // Non-general intent with an unresolved reference ("play xyzzy", "tafsir ???")
    if (surahNumber == null &&
        intent != IntentType.askGeneralQuestion &&
        RegExp(
          r'\b(?:ayah|verse|tafsir|recite|play|meaning)\b',
          caseSensitive: false,
        ).hasMatch(corrected)) {
      return true;
    }

    return false;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Title-case hyphenated canonical surah name, e.g. "al-baqarah" → "Al-Baqarah".
  String _formatSurahName(int surahNumber) {
    if (surahNumber < 1 || surahNumber > SurahLookup.canonicalSurahNames.length) {
      return 'Surah $surahNumber';
    }
    return SurahLookup.canonicalSurahNames[surahNumber - 1]
        .split('-')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join('-');
  }
}
