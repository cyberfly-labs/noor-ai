import '../models/surah.dart';

/// Prompt templates for the on-device LLM (Qwen3.5-0.8B)
/// Optimized for speed and grounding accuracy.
class PromptTemplates {
  PromptTemplates._();

  /// Core identity prefix - shortened for faster prompt processing.
  static const String _noorIdentity =
      'You are Noor AI. Answer ONLY from supplied evidence. '
      'Prefer Quran, then Tafsir. Cite exact references. Do not speculate. '
      'If evidence missing, say: "I could not find this in the sources." '
      'Match user language. Plain text, no markdown.';

  /// Explain a Quran verse using only the supplied translation and tafsir
  static String explainVerse({
    required String verseKey,
    required String arabicText,
    required String translationText,
    String? tafsirText,
    String? tafsirSource,
  }) {
    final sourceLabel = tafsirSource != null && tafsirSource.isNotEmpty
        ? tafsirSource
        : 'retrieved tafsir source';
    final tafsirBlock = tafsirText != null && tafsirText.isNotEmpty
        ? '\n[TAFSIR]\nSource: $sourceLabel\nText: $tafsirText'
        : '';
    final arabicBlock = arabicText.isNotEmpty
        ? '\n[QURAN]\nText: $arabicText\nTranslation: $translationText'
        : '\n[QURAN]\nTranslation: $translationText';

    return '''$_noorIdentity

Explain verse $verseKey using ONLY:
$arabicBlock$tafsirBlock

Rules:
- 3-4 short sentences. Grounded only.
- Cite $verseKey. Attribute tafsir to $sourceLabel.
- No outside knowledge. No markdown.

Structure:
📚 Explanation:
[Grounded sentences]

✨ Summary:
[Short takeaway]''';
  }

  static String dailyAyahExplanation({
    required String verseKey,
    required String arabicText,
    required String translationText,
    String? tafsirText,
    String? tafsirSource,
  }) {
    final sourceLabel = tafsirSource != null && tafsirSource.isNotEmpty
        ? tafsirSource
        : 'retrieved tafsir source';
    final tafsirBlock = tafsirText != null && tafsirText.isNotEmpty
        ? '\n[TAFSIR]\nSource: $sourceLabel\nText: $tafsirText'
        : '';
    final arabicBlock = arabicText.isNotEmpty
        ? '\n[QURAN]\nVerse: $verseKey\nTranslation: $translationText'
        : '\n[QURAN]\nVerse: $verseKey\nTranslation: $translationText';

    return '''$_noorIdentity

Explain Daily Ayah $verseKey using:
$arabicBlock$tafsirBlock

Return ONLY 4-6 sentences. Prose only. No labels or markdown.
Every sentence must be directly supported. Attribute to $sourceLabel.''';
  }

  /// Explain the theme/overview of a surah
  static String explainSurah({
    required String surahName,
    required int surahNumber,
    required String firstVerseTranslation,
  }) {
    return '''$_noorIdentity

Overview of Surah $surahName ($surahNumber) based on:
$surahNumber:1 - $firstVerseTranslation

Rules:
- Ground every claim in this verse. Cite $surahNumber:1.
- No speculation. Match user language.

Structure:
1. Theme (2 sentences)
2. Key Messages (2 sentences)
3. Significance (1 sentence)''';
  }

  static String groundedSurahOverview({
    required String surahName,
    required int surahNumber,
    required List<String> evidenceBlocks,
  }) {
    final evidenceText = evidenceBlocks.join('\n\n');

    return '''$_noorIdentity

Overview of Surah $surahName ($surahNumber) using ONLY:
$evidenceText

Rules:
- Use ONLY supplied blocks. No outside info.
- Cite verse keys. Attribute tafsir.
- Keep total under 100 words.

Structure:
📚 Explanation:
[5 short grounded sentences]

✨ Summary:
[1 sentence theme]''';
  }

  /// Emotional guidance based on user's feeling
  static String emotionalGuidance({
    required String emotion,
    required String userText,
    required List<String> verseReferences,
    required List<String> verseTranslations,
  }) {
    final slotCount = verseReferences.length.clamp(1, 2); // Reduced for speed
    final verseEvidence = List.generate(slotCount, (i) {
      final key = verseReferences[i];
      final fill =
          i < verseTranslations.length && verseTranslations[i].isNotEmpty
          ? '"${verseTranslations[i]}"'
          : '[translation unavailable]';
      return '- $key: $fill';
    }).join('\n');
    final explanationSlots = List.generate(slotCount, (i) {
      return '- ${verseReferences[i]}: [Grounded comfort]';
    }).join('\n');

    return '''$_noorIdentity

User feeling $emotion: "$userText"
Use ONLY these:
$verseEvidence

Rules:
- Compassionate but grounded.
- Mention verse keys once.
- No markdown. Under 90 words.

Structure:
📚 Explanation:
$explanationSlots

🤍 Comfort:
[2 grounded sentences]

✨ Summary:
[1 hopeful sentence]''';
  }

  /// General Quran question (ungrounded fallback)
  static String generalQuestion(String question) {
    return '''$_noorIdentity

Answer: "$question"

Rules:
- Quote relevant verse. Attribute sources.
- No fatwas. Brief explanation.

Structure:
📖 Quran:
[Reference]

📚 Explanation:
[4-6 sentences]

✨ Summary:
[1 sentence]''';
  }

  static String groundedGeneralQuestion({
    required String question,
    required String retrievalQuery,
    required List<String> evidenceBlocks,
    required List<String> verseReferences,
    List<String> verseTranslations = const [],
  }) {
    final evidenceText = evidenceBlocks.join('\n\n');
    final slotCount = verseReferences.length.clamp(1, 2); // Reduced for speed
    final explanationSlots = List.generate(slotCount, (i) {
      return '- ${verseReferences[i]}: [1 grounded sentence]';
    }).join('\n');

    return '''$_noorIdentity

Question: "$question"
Evidence:
$evidenceText

Rules:
- Use ONLY supplied evidence.
- Do not skip verse slots.
- No markdown. Under 100 words.

Structure:
📚 Explanation:
$explanationSlots

🧭 What This Means:
[Direct answer, 2 grounded sentences]

✨ Summary:
[1 sentence takeaway]''';
  }

  static String rewriteAsrTranscript({required String transcript}) {
    final surahChoices = SurahLookup.promptSurahChoices(transcript: transcript);

    return '''Fix transcription errors in: "$transcript"
Valid surahs: $surahChoices

Task:
- Fix Islamic terms and surah names.
- Use closest valid name from list.
- Return ONLY the corrected plain line. No extra text.''';
  }

  static String normalizeVoiceCommand({required String userInput}) {
    final surahChoices = SurahLookup.promptSurahChoices(
      transcript: userInput,
      maxChoices: 6,
    );

    return '''Fix transcription in user input.
Valid surahs: $surahChoices

Return ONLY JSON:
{
  "intent": "intent_id",
  "surah": "name",
  "ayah": number|null,
  "clean_text": "clean"
}

Input: $userInput''';
  }

  static String translateTafsirText({required String tafsirText}) {
    return '''Translate to English:
$tafsirText

Rules:
- Clear English. No commentary.
- Return only the translation.''';
  }

  /// Generate a daily ayah reflection
  static String dailyReflection({
    required String arabicText,
    required String translationText,
  }) {
    return '''$_noorIdentity

Daily reflection for:
Text: $arabicText
Translation: $translationText

Write 2-3 grounded, warm sentences. No fatwas. Brief only.''';
  }
}

