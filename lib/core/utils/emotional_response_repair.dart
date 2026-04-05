class EmotionalResponseCitation {
  const EmotionalResponseCitation({
    required this.verseKey,
    required this.excerpt,
  });

  final String verseKey;
  final String excerpt;
}

class EmotionalResponseRepair {
  EmotionalResponseRepair._();

  static String repairIfNeeded({
    required String response,
    required String emotion,
    required List<EmotionalResponseCitation> citations,
  }) {
    final usableCitations = citations
        .where(
          (item) =>
              item.verseKey.trim().isNotEmpty && item.excerpt.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (usableCitations.isEmpty) {
      return response.trim();
    }

    if (!_looksBroken(response, usableCitations)) {
      return response.trim();
    }

    final limitedCitations = usableCitations.take(2).toList(growable: false);
    final quranLines = limitedCitations
        .map((item) => '- ${item.verseKey}: "${item.excerpt.trim()}"')
        .join('\n');
    final explanationLines = limitedCitations
        .map(
          (item) =>
              '- ${item.verseKey}: ${_explanationForCitation(item, emotion)}',
        )
        .join('\n');

    return '''📖 Quran:
$quranLines

📚 Explanation:
$explanationLines

🤍 Comfort:
${_comfortSection(limitedCitations, emotion)}

✨ Summary:
${_summarySection(limitedCitations, emotion)}''';
  }

  static bool _looksBroken(
    String response,
    List<EmotionalResponseCitation> citations,
  ) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) {
      return true;
    }

    final contentLines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !_isSectionHeader(line))
        .toList(growable: false);
    if (contentLines.isEmpty) {
      return true;
    }

    var proseLines = 0;
    for (final line in contentLines) {
      if (!_isCitationEchoLine(line, citations)) {
        proseLines += 1;
      }
    }

    return proseLines < 2;
  }

  static bool _isSectionHeader(String line) {
    return line.startsWith('📖 Quran:') ||
        line.startsWith('📚 Explanation:') ||
        line.startsWith('🤍 Comfort:') ||
        line.startsWith('✨ Summary:');
  }

  static bool _isCitationEchoLine(
    String line,
    List<EmotionalResponseCitation> citations,
  ) {
    final normalized = line.trim();
    for (final citation in citations) {
      final excerpt = citation.excerpt.trim();
      if (excerpt.isEmpty) {
        continue;
      }

      if (normalized.contains(citation.verseKey) &&
          normalized.contains(excerpt)) {
        return true;
      }

      if (normalized == '"$excerpt"' || normalized == excerpt) {
        return true;
      }
    }
    return false;
  }

  static String _explanationForCitation(
    EmotionalResponseCitation citation,
    String emotion,
  ) {
    final excerpt = citation.excerpt.toLowerCase();
    final emotionPhrase = _emotionPhrase(emotion);

    if (excerpt.contains('do not lose hope') ||
        excerpt.contains('nor be sad')) {
      return 'This verse speaks directly to $emotionPhrase by telling you not to surrender to despair or sadness.';
    }
    if (excerpt.contains('has not taken leave of you') ||
        excerpt.contains('has not forsaken you') ||
        excerpt.contains('nor has he detested you')) {
      return 'This verse reassures you that Allah has not abandoned you, even when your heart feels heavy.';
    }
    if (excerpt.contains('hearts find rest')) {
      return 'This verse points you toward calm through the remembrance of Allah, showing where the heart can settle.';
    }
    if (excerpt.contains('does not burden a soul')) {
      return 'This verse reassures you that what you are carrying is known to Allah and not beyond what He enables you to bear.';
    }
    if (excerpt.contains('do not grieve') ||
        excerpt.contains('allah is with us')) {
      return 'This verse gives immediate reassurance that you are not alone and that Allah\'s help remains near.';
    }
    if (excerpt.contains('relies upon allah') ||
        excerpt.contains('sufficient for him')) {
      return 'This verse teaches steadiness through trust, reminding you to lean on Allah when things feel uncertain.';
    }
    if (excerpt.contains('do not despair of the mercy')) {
      return 'This verse reopens hope by reminding you that Allah\'s mercy is greater than fear, regret, or exhaustion.';
    }
    if (excerpt.contains('with hardship will be ease')) {
      return 'This verse reminds you that hardship is not the end of the story and that ease comes with it.';
    }

    return 'This verse offers grounded comfort for $emotionPhrase by turning your heart back toward Allah\'s care and guidance.';
  }

  static String _comfortSection(
    List<EmotionalResponseCitation> citations,
    String emotion,
  ) {
    final firstVerseKey = citations.first.verseKey;
    final emotionPhrase = _emotionPhrase(emotion);
    return 'Your pain is real, but these verses redirect $emotionPhrase toward hope, patience, and trust in Allah. Let $firstVerseKey remind you that you are not abandoned in what you are carrying.';
  }

  static String _summarySection(
    List<EmotionalResponseCitation> citations,
    String emotion,
  ) {
    final emotionPhrase = _emotionPhrase(emotion);
    if (citations.any(
      (item) => item.excerpt.toLowerCase().contains('do not lose hope'),
    )) {
      return 'Do not lose hope; these verses remind you that sadness is not the end of your story before Allah.';
    }
    if (citations.any(
      (item) => item.excerpt.toLowerCase().contains('hearts find rest'),
    )) {
      return 'These verses guide $emotionPhrase back toward calm, remembrance, and trust in Allah.';
    }
    return 'These verses call $emotionPhrase back to hope, steadiness, and trust in Allah.';
  }

  static String _emotionPhrase(String emotion) {
    final normalized = emotion.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'difficulty') {
      return 'this difficult moment';
    }
    switch (normalized) {
      case 'anxiety':
      case 'anxious':
        return 'this anxious moment';
      case 'sadness':
      case 'sad':
        return 'this sadness';
      case 'lonely':
      case 'loneliness':
        return 'this loneliness';
      case 'hopeless':
        return 'this hopelessness';
      default:
        return 'feeling $normalized';
    }
  }
}
