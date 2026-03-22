import '../models/intent.dart';
import '../models/surah.dart';

/// Shared utilities for generating always-English retrieval queries and
/// detecting the user's response language.  Extracted into a standalone
/// library so both [AsrNormalizationPipeline] and [IntentParser] can import
/// it without creating a circular dependency.
class QuranQueryHelpers {
  QuranQueryHelpers._();

  // ── Multilingual topic aliases ───────────────────────────────────────────
  // Maps multilingual / Islamic terms → English search phrases.
  static const Map<String, String> topicAliases = <String, String>{
    // Arabic Islamic terms
    'sabr':        'patience endurance',
    'tawakkul':    'trust in Allah reliance',
    'tawbah':      'repentance forgiveness',
    'istighfar':   'seeking forgiveness',
    'rizq':        'sustenance provision livelihood',
    'dua':         'supplication prayer invocation',
    'dhikr':       'remembrance of Allah',
    'jannah':      'paradise heaven',
    'jannat':      'paradise heaven',
    'jahannam':    'hellfire punishment',
    'taqwa':       'piety God-consciousness righteousness',
    'zakat':       'charity almsgiving',
    'sadaqah':     'charity giving generosity',
    'sadaka':      'charity giving',
    'hijab':       'modesty covering',
    'jihad':       'striving struggle effort',
    'shukr':       'gratitude thankfulness',
    'amanah':      'trust responsibility honesty',
    'iman':        'faith belief',
    'kufr':        'disbelief',
    'nifaq':       'hypocrisy',
    'kibr':        'arrogance pride',
    'israf':       'extravagance waste',
    'halal':       'permissible lawful',
    'haram':       'forbidden unlawful',
    'akhirah':     'afterlife hereafter',
    'akhirat':     'afterlife hereafter',
    'aakhirat':    'afterlife hereafter',
    'qiyamah':     'Day of Judgment resurrection',
    'qiyamat':     'Day of Judgment resurrection',
    'mizan':       'scales of deeds judgment',
    'shafaat':     'intercession',
    'barakah':     'blessing',
    'barakat':     'blessings',
    'rahma':       'mercy compassion',
    'rahmah':      'mercy compassion',
    'noor':        'light guidance',
    'hidayah':     'guidance right path',
    'hidaya':      'guidance right path',
    // Hinglish / Urdu terms
    'namaz':       'prayer salah',
    'namaaz':      'prayer salah',
    'roza':        'fasting Ramadan',
    'roja':        'fasting Ramadan',
    'dozakh':      'hellfire punishment',
    'gunah':       'sin transgression',
    'gunaah':      'sin transgression',
    'tohba':       'repentance forgiveness',
    'toba':        'repentance',
    'niyat':       'intention',
    'khauf':       'fear of Allah',
    'umeed':       'hope',
    // Tamil Islamic terms (romanized)
    'sabru':       'patience',
    'thowbah':     'repentance',
    'namazh':      'prayer salah',
    'vilaakku':    'forgiveness',
  };

  // ── Language detection ──────────────────────────────────────────────────

  /// Returns a BCP-47-style language code from raw (pre-clean) text.
  /// Detection order: Unicode script → romanized-keyword heuristics → 'en'.
  static String detectResponseLanguage(String rawText) {
    // Arabic script (U+0600–U+06FF)
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(rawText)) return 'ar';
    // Tamil script (U+0B80–U+0BFF)
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(rawText)) return 'ta';
    // Devanagari / Hindi (U+0900–U+097F)
    if (RegExp(r'[\u0900-\u097F]').hasMatch(rawText)) return 'hi';

    final lower = rawText.toLowerCase();

    // Hinglish / Urdu romanization indicators
    if (RegExp(
            r'\b(kya|hai|mujhe|aap|kyun|kaise|mera|tera|yeh|woh|aur|lekin|namaz|roza|akhirat|tohba|batao|samjhao|padho|tarjuma)\b')
        .hasMatch(lower)) {
      return 'hi';
    }

    // Tamil romanization indicators
    if (RegExp(
            r'\b(enna|yenna|eppadi|sollu|solla|irukkum|kuraan|namazh|thowbah|sabru|vilaakku)\b')
        .hasMatch(lower)) {
      return 'ta';
    }

    return 'en';
  }

  // ── Retrieval query builder ──────────────────────────────────────────────

  /// Builds an always-English query for the vector-DB embedding search.
  ///
  /// Priority:
  ///   1. Resolved surah + ayah → structured canonical form
  ///   2. Resolved surah only   → overview canonical form
  ///   3. Topic alias match     → "What does the Quran say about X"
  ///   4. Fallback              → [correctedText] as-is (already mostly English
  ///                             after term-correction stage)
  static String buildEnglishRetrievalQuery({
    required String correctedText,
    required IntentType intent,
    int? surahNumber,
    int? ayahNumber,
  }) {
    final surahName = surahNumber != null ? _formatSurahName(surahNumber) : null;

    // Case 1 — specific verse
    if (surahName != null && ayahNumber != null) {
      switch (intent) {
        case IntentType.tafsir:
          return 'Tafsir of Surah $surahName verse $ayahNumber';
        case IntentType.translation:
          return 'Translation of Surah $surahName verse $ayahNumber';
        case IntentType.playAudio:
          return 'Surah $surahName verse $ayahNumber recitation';
        default:
          return 'Surah $surahName verse $ayahNumber meaning explanation';
      }
    }

    // Case 2 — surah only
    if (surahName != null) {
      switch (intent) {
        case IntentType.tafsir:
          return 'Tafsir of Surah $surahName';
        case IntentType.playAudio:
          return 'Surah $surahName recitation';
        default:
          return 'Surah $surahName themes overview message';
      }
    }

    // Case 3 — topic alias match
    final topicPhrase = extractEnglishTopic(correctedText);
    if (topicPhrase != null) {
      return 'What does the Quran say about $topicPhrase';
    }

    // Case 4 — fallback
    return correctedText;
  }

  /// Scans [text] for any multilingual topic alias and returns the mapped
  /// English phrase, or null if no alias matched.
  static String? extractEnglishTopic(String text) {
    final lower = text.toLowerCase();
    // Longest key first (prefer more specific matches)
    final sortedKeys = topicAliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      if (RegExp('\\b${RegExp.escape(key)}\\b', caseSensitive: false)
          .hasMatch(lower)) {
        return topicAliases[key];
      }
    }
    return null;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _formatSurahName(int surahNumber) {
    if (surahNumber < 1 || surahNumber > SurahLookup.canonicalSurahNames.length) {
      return 'Surah $surahNumber';
    }
    return SurahLookup.canonicalSurahNames[surahNumber - 1]
        .split('-')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join('-');
  }
}
