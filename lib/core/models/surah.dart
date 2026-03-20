class Surah {
  final int number;
  final String name;
  final String englishName;
  final String englishNameTranslation;
  final int numberOfAyahs;
  final String revelationType;
  final List<int> pages;

  const Surah({
    required this.number,
    required this.name,
    required this.englishName,
    required this.englishNameTranslation,
    required this.numberOfAyahs,
    required this.revelationType,
    this.pages = const [],
  });

  factory Surah.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'] as List? ?? const [];

    return Surah(
      number: json['number'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      englishName: json['englishName'] as String? ?? json['name_simple'] as String? ?? '',
      englishNameTranslation: json['englishNameTranslation'] as String? ?? json['translated_name']?['name'] as String? ?? '',
      numberOfAyahs: json['numberOfAyahs'] as int? ?? json['verses_count'] as int? ?? 0,
      revelationType: json['revelationType'] as String? ?? json['revelation_place'] as String? ?? '',
      pages: rawPages.whereType<num>().map((page) => page.toInt()).toList(),
    );
  }
}

/// Hardcoded surah name lookup for intent parsing
class SurahLookup {
  SurahLookup._();

  static const List<String> canonicalSurahNames = [
    'al-fatihah',
    'al-baqarah',
    'ali-imran',
    'an-nisa',
    'al-maidah',
    'al-anam',
    'al-araf',
    'al-anfal',
    'at-tawbah',
    'yunus',
    'hud',
    'yusuf',
    'ar-rad',
    'ibrahim',
    'al-hijr',
    'an-nahl',
    'al-isra',
    'al-kahf',
    'maryam',
    'ta-ha',
    'al-anbiya',
    'al-hajj',
    'al-muminun',
    'an-nur',
    'al-furqan',
    'ash-shuara',
    'an-naml',
    'al-qasas',
    'al-ankabut',
    'ar-rum',
    'luqman',
    'as-sajdah',
    'al-ahzab',
    'saba',
    'fatir',
    'ya-sin',
    'as-saffat',
    'sad',
    'az-zumar',
    'ghafir',
    'fussilat',
    'ash-shura',
    'az-zukhruf',
    'ad-dukhan',
    'al-jathiyah',
    'al-ahqaf',
    'muhammad',
    'al-fath',
    'al-hujurat',
    'qaf',
    'adh-dhariyat',
    'at-tur',
    'an-najm',
    'al-qamar',
    'ar-rahman',
    'al-waqiah',
    'al-hadid',
    'al-mujadila',
    'al-hashr',
    'al-mumtahanah',
    'as-saf',
    'al-jumuah',
    'al-munafiqun',
    'at-taghabun',
    'at-talaq',
    'at-tahrim',
    'al-mulk',
    'al-qalam',
    'al-haqqah',
    'al-maarij',
    'nuh',
    'al-jinn',
    'al-muzzammil',
    'al-muddaththir',
    'al-qiyamah',
    'al-insan',
    'al-mursalat',
    'an-naba',
    'an-naziat',
    'abasa',
    'at-takwir',
    'al-infitar',
    'al-mutaffifin',
    'al-inshiqaq',
    'al-buruj',
    'at-tariq',
    'al-ala',
    'al-ghashiyah',
    'al-fajr',
    'al-balad',
    'ash-shams',
    'al-layl',
    'ad-duha',
    'ash-sharh',
    'at-tin',
    'al-alaq',
    'al-qadr',
    'al-bayyinah',
    'az-zalzalah',
    'al-adiyat',
    'al-qariah',
    'at-takathur',
    'al-asr',
    'al-humazah',
    'al-fil',
    'quraysh',
    'al-maun',
    'al-kawthar',
    'al-kafirun',
    'an-nasr',
    'al-masad',
    'al-ikhlas',
    'al-falaq',
    'an-nas',
  ];

  static const Map<String, int> nameToNumber = {
    'al-fatihah': 1, 'fatiha': 1, 'fatihah': 1, 'opening': 1,
    'al-baqarah': 2, 'baqarah': 2, 'cow': 2,
    'ali-imran': 3, 'imran': 3,
    'an-nisa': 4, 'nisa': 4, 'women': 4,
    'al-maidah': 5, 'maidah': 5, 'table': 5,
    'al-anam': 6, 'anam': 6, 'cattle': 6,
    'al-araf': 7, 'araf': 7, 'heights': 7,
    'al-anfal': 8, 'anfal': 8, 'spoils': 8,
    'at-tawbah': 9, 'tawbah': 9, 'repentance': 9,
    'yunus': 10, 'jonah': 10,
    'hud': 11,
    'yusuf': 12, 'joseph': 12,
    'ar-rad': 13, 'rad': 13, 'thunder': 13,
    'ibrahim': 14, 'abraham': 14,
    'al-hijr': 15, 'hijr': 15,
    'an-nahl': 16, 'nahl': 16, 'bee': 16,
    'al-isra': 17, 'isra': 17, 'night journey': 17,
    'al-kahf': 18, 'kahf': 18, 'cave': 18,
    'maryam': 19, 'mary': 19,
    'ta-ha': 20, 'taha': 20,
    'al-anbiya': 21, 'anbiya': 21, 'prophets': 21,
    'al-hajj': 22, 'hajj': 22, 'pilgrimage': 22,
    'al-muminun': 23, 'muminun': 23, 'believers': 23,
    'an-nur': 24, 'nur': 24, 'light': 24,
    'al-furqan': 25, 'furqan': 25, 'criterion': 25,
    'ash-shuara': 26, 'shuara': 26, 'poets': 26,
    'an-naml': 27, 'naml': 27, 'ants': 27,
    'al-qasas': 28, 'qasas': 28, 'stories': 28,
    'al-ankabut': 29, 'ankabut': 29, 'spider': 29,
    'ar-rum': 30, 'rum': 30, 'romans': 30,
    'luqman': 31,
    'as-sajdah': 32, 'sajdah': 32, 'prostration': 32,
    'al-ahzab': 33, 'ahzab': 33, 'confederates': 33,
    'saba': 34, 'sheba': 34,
    'fatir': 35, 'originator': 35,
    'ya-sin': 36, 'yasin': 36,
    'as-saffat': 37, 'saffat': 37,
    'sad': 38,
    'az-zumar': 39, 'zumar': 39, 'groups': 39,
    'ghafir': 40, 'forgiver': 40,
    'fussilat': 41, 'explained': 41,
    'ash-shura': 42, 'shura': 42, 'consultation': 42,
    'az-zukhruf': 43, 'zukhruf': 43, 'ornaments': 43,
    'ad-dukhan': 44, 'dukhan': 44, 'smoke': 44,
    'al-jathiyah': 45, 'jathiyah': 45, 'crouching': 45,
    'al-ahqaf': 46, 'ahqaf': 46, 'dunes': 46,
    'muhammad': 47,
    'al-fath': 48, 'fath': 48, 'victory': 48,
    'al-hujurat': 49, 'hujurat': 49, 'rooms': 49,
    'qaf': 50,
    'adh-dhariyat': 51, 'dhariyat': 51, 'winds': 51,
    'at-tur': 52, 'tur': 52, 'mount': 52,
    'an-najm': 53, 'najm': 53, 'star': 53,
    'al-qamar': 54, 'qamar': 54, 'moon': 54,
    'ar-rahman': 55, 'rahman': 55, 'merciful': 55,
    'al-waqiah': 56, 'waqiah': 56, 'event': 56,
    'al-hadid': 57, 'hadid': 57, 'iron': 57,
    'al-mujadila': 58, 'mujadila': 58,
    'al-hashr': 59, 'hashr': 59, 'exile': 59,
    'al-mumtahanah': 60, 'mumtahanah': 60,
    'as-saf': 61, 'saf': 61, 'ranks': 61,
    'al-jumuah': 62, 'jumuah': 62, 'friday': 62,
    'al-munafiqun': 63, 'munafiqun': 63, 'hypocrites': 63,
    'at-taghabun': 64, 'taghabun': 64,
    'at-talaq': 65, 'talaq': 65, 'divorce': 65,
    'at-tahrim': 66, 'tahrim': 66, 'prohibition': 66,
    'al-mulk': 67, 'mulk': 67, 'mulq': 67, 'sovereignty': 67,
    'al-qalam': 68, 'qalam': 68, 'pen': 68,
    'al-haqqah': 69, 'haqqah': 69, 'reality': 69,
    'al-maarij': 70, 'maarij': 70, 'ascending': 70,
    'nuh': 71, 'noah': 71,
    'al-jinn': 72, 'jinn': 72,
    'al-muzzammil': 73, 'muzzammil': 73, 'enshrouded': 73,
    'al-muddaththir': 74, 'muddaththir': 74, 'cloaked': 74,
    'al-qiyamah': 75, 'qiyamah': 75, 'resurrection': 75,
    'al-insan': 76, 'insan': 76, 'man': 76,
    'al-mursalat': 77, 'mursalat': 77, 'emissaries': 77,
    'an-naba': 78, 'naba': 78, 'tidings': 78,
    'an-naziat': 79, 'naziat': 79, 'extractors': 79,
    'abasa': 80, 'frowned': 80,
    'at-takwir': 81, 'takwir': 81, 'overthrowing': 81,
    'al-infitar': 82, 'infitar': 82, 'cleaving': 82,
    'al-mutaffifin': 83, 'mutaffifin': 83, 'defrauding': 83,
    'al-inshiqaq': 84, 'inshiqaq': 84, 'splitting': 84,
    'al-buruj': 85, 'buruj': 85, 'constellations': 85,
    'at-tariq': 86, 'tariq': 86, 'morning star': 86,
    'al-ala': 87, 'ala': 87, 'most high': 87,
    'al-ghashiyah': 88, 'ghashiyah': 88, 'overwhelming': 88,
    'al-fajr': 89, 'fajr': 89, 'dawn': 89,
    'al-balad': 90, 'balad': 90, 'city': 90,
    'ash-shams': 91, 'shams': 91, 'sun': 91,
    'al-layl': 92, 'layl': 92, 'night': 92,
    'ad-duha': 93, 'duha': 93, 'morning': 93,
    'ash-sharh': 94, 'sharh': 94, 'relief': 94,
    'at-tin': 95, 'tin': 95, 'fig': 95,
    'al-alaq': 96, 'alaq': 96, 'clot': 96,
    'al-qadr': 97, 'qadr': 97, 'power': 97, 'decree': 97,
    'al-bayyinah': 98, 'bayyinah': 98, 'evidence': 98,
    'az-zalzalah': 99, 'zalzalah': 99, 'earthquake': 99,
    'al-adiyat': 100, 'adiyat': 100, 'chargers': 100,
    'al-qariah': 101, 'qariah': 101, 'calamity': 101,
    'at-takathur': 102, 'takathur': 102, 'rivalry': 102,
    'al-asr': 103, 'asr': 103, 'time': 103,
    'al-humazah': 104, 'humazah': 104, 'traducer': 104,
    'al-fil': 105, 'fil': 105, 'elephant': 105,
    'quraysh': 106,
    'al-maun': 107, 'maun': 107, 'almsgiving': 107,
    'al-kawthar': 108, 'kawthar': 108, 'abundance': 108,
    'al-kafirun': 109, 'kafirun': 109, 'disbelievers': 109,
    'an-nasr': 110, 'nasr': 110, 'divine support': 110,
    'al-masad': 111, 'masad': 111, 'palm fiber': 111,
    'al-ikhlas': 112, 'ikhlas': 112, 'sincerity': 112,
    'al-falaq': 113, 'falaq': 113, 'daybreak': 113,
    'an-nas': 114, 'nas': 114, 'mankind': 114,
  };

  static final Map<String, int> _normalizedNameToNumber = {
    for (final entry in nameToNumber.entries) _normalizeLookupKey(entry.key): entry.value,
  };

  static final Map<String, int> _compactNameToNumber = {
    for (final entry in nameToNumber.entries) _compactLookupKey(entry.key): entry.value,
  };

  static int? findSurahNumber(String name) {
    final normalized = _normalizeLookupKey(name);
    if (normalized.isEmpty) {
      return null;
    }

    final direct = _lookupExact(normalized);
    if (direct != null) {
      return direct;
    }

    final extracted = _extractPotentialSurahQuery(name);
    if (extracted.isNotEmpty && extracted != normalized) {
      final extractedDirect = _lookupExact(extracted);
      if (extractedDirect != null) {
        return extractedDirect;
      }

      final extractedFuzzy = _lookupFuzzy(extracted);
      if (extractedFuzzy != null) {
        return extractedFuzzy;
      }
    }

    return _lookupFuzzy(normalized);
  }

  static String normalizeSurahMentions(String input) {
    if (input.trim().isEmpty) {
      return input;
    }

    return input.replaceAllMapped(
      RegExp(
        r'\b(?:suratul|surah|surat|sura|sorah)\s+([a-z][a-z0-9\- ]*)',
        caseSensitive: false,
      ),
      (match) {
        final raw = (match.group(1) ?? '').trim();
        if (raw.isEmpty) {
          return match.group(0) ?? '';
        }

        final candidate = raw
            .split(
              RegExp(
                r'\b(?:ayah|verse|translation|tafsir|audio|play|details?|meaning|of|from|please)\b',
                caseSensitive: false,
              ),
            )
            .first
            .trim();
        final number = findSurahNumber(candidate);
        if (number == null || number < 1 || number > canonicalSurahNames.length) {
          return match.group(0) ?? '';
        }

        final suffix = raw.substring(candidate.length);
        final canonical = canonicalSurahNames[number - 1].replaceAll('-', ' ');
        return 'surah $canonical$suffix';
      },
    );
  }

  static String promptSurahChoices({
    String? transcript,
    int maxChoices = 12,
  }) {
    final choices = rankedPromptSurahChoices(
      transcript,
      maxChoices: maxChoices,
    );

    return List<String>.generate(
      choices.length,
      (index) => '${index + 1}. ${choices[index]}',
      growable: false,
    ).join(', ');
  }

  static List<String> rankedPromptSurahChoices(
    String? transcript, {
    int maxChoices = 12,
  }) {
    if (maxChoices <= 0) {
      return const <String>[];
    }

    final surahQuery = _extractPotentialSurahQuery(transcript ?? '');
    if (surahQuery.isEmpty) {
      return canonicalSurahNames.take(maxChoices).toList(growable: false);
    }

    final compactQuery = _compactLookupKey(surahQuery);
    final queryTokens = _normalizeLookupKey(surahQuery)
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList(growable: false);

    final ranked = canonicalSurahNames.toList(growable: false)
      ..sort((left, right) {
        final rightScore = _promptCandidateScore(right, compactQuery, queryTokens);
        final leftScore = _promptCandidateScore(left, compactQuery, queryTokens);
        if (rightScore != leftScore) {
          return rightScore.compareTo(leftScore);
        }
        return canonicalSurahNames.indexOf(left).compareTo(canonicalSurahNames.indexOf(right));
      });

    return ranked.take(maxChoices).toList(growable: false);
  }

  static int _promptCandidateScore(
    String candidate,
    String compactQuery,
    List<String> queryTokens,
  ) {
    final normalizedCandidate = _normalizeLookupKey(candidate);
    final compactCandidate = _compactLookupKey(candidate);
    var score = 0;

    if (compactQuery == compactCandidate) {
      score += 1000;
    }
    if (compactQuery.isNotEmpty && compactCandidate.contains(compactQuery)) {
      score += 500;
    }
    if (compactQuery.isNotEmpty && compactQuery.contains(compactCandidate)) {
      score += 300;
    }

    for (final token in queryTokens) {
      if (token == normalizedCandidate || token == compactCandidate) {
        score += 300;
        continue;
      }
      if (normalizedCandidate.contains(token) || compactCandidate.contains(token)) {
        score += token.length * 20;
      }
      if (token.contains(normalizedCandidate) || token.contains(compactCandidate)) {
        score += token.length * 12;
      }
    }

    if (compactQuery.isNotEmpty && compactCandidate.isNotEmpty) {
      score -= _levenshteinDistance(compactQuery, compactCandidate);
    }

    return score;
  }

  static int? _lookupExact(String query) {
    final direct = _normalizedNameToNumber[query];
    if (direct != null) {
      return direct;
    }

    final compact = _compactLookupKey(query);
    return _compactNameToNumber[compact];
  }

  static int? _lookupFuzzy(String query) {
    final compactQuery = _compactLookupKey(query);
    if (compactQuery.length < 3 || query.split(' ').length > 3) {
      return null;
    }

    var bestDistance = 1 << 20;
    var secondBestDistance = 1 << 20;
    int? bestNumber;
    int? secondBestNumber;

    for (final entry in _compactNameToNumber.entries) {
      var distance = _levenshteinDistance(compactQuery, entry.key);
      if (entry.key.startsWith(compactQuery) || compactQuery.startsWith(entry.key)) {
        distance -= 1;
      }

      if (distance < bestDistance) {
        secondBestDistance = bestDistance;
        secondBestNumber = bestNumber;
        bestDistance = distance;
        bestNumber = entry.value;
      } else if (entry.value != bestNumber && distance < secondBestDistance) {
        secondBestDistance = distance;
        secondBestNumber = entry.value;
      }
    }

    if (bestNumber == null) {
      return null;
    }

    final maxDistance = _maxFuzzyDistance(compactQuery.length);
    if (bestDistance > maxDistance) {
      return null;
    }

    if (secondBestNumber != null &&
        secondBestNumber != bestNumber &&
        bestDistance > 1 &&
        secondBestDistance <= bestDistance) {
      return null;
    }

    return bestNumber;
  }

  static int _maxFuzzyDistance(int queryLength) {
    if (queryLength <= 4) {
      return 1;
    }
    if (queryLength <= 7) {
      return 2;
    }
    if (queryLength <= 11) {
      return 3;
    }
    return 4;
  }

  static String extractRecognizedSurahName(String text) {
    final match = RegExp(
      r'\b(?:suratul|surah|surat|sura|sorah)\s+([a-z0-9\- ]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      return '';
    }

    final rawCandidate = match.group(1) ?? '';
    final candidate = rawCandidate
        .split(RegExp(r'\b(?:ayah|verse|translation|tafsir|audio|play|details?|meaning|of|from)\b', caseSensitive: false))
        .first
        .trim();

    final number = findSurahNumber(candidate);
    if (number == null || number < 1 || number > canonicalSurahNames.length) {
      return '';
    }

    return canonicalSurahNames[number - 1];
  }

  static String _extractPotentialSurahQuery(String transcript) {
    final explicitMatch = RegExp(
      r'\b(?:suratul|surah|surat|sura|sorah)\s+([a-z0-9\- ]+)',
      caseSensitive: false,
    ).firstMatch(transcript);
    final source = explicitMatch?.group(1) ?? transcript;

    var normalized = source.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r"['’]"), '');
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    normalized = normalized.replaceAll(
      RegExp(r'\b(?:explain|show|open|play|listen|read|recite|recitation|translation|tafsir|details?|detail|meaning|verse|ayah|surah|surat|sura|sorah|for|of|from|the|a|an|to|please|about)\b'),
      ' ',
    );
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  static int _levenshteinDistance(String left, String right) {
    if (left == right) {
      return 0;
    }
    if (left.isEmpty) {
      return right.length;
    }
    if (right.isEmpty) {
      return left.length;
    }

    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 0; i < left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = i + 1;

      for (var j = 0; j < right.length; j++) {
        final substitutionCost = left.codeUnitAt(i) == right.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + substitutionCost,
        ].reduce((value, element) => value < element ? value : element);
      }

      previous = current;
    }

    return previous.last;
  }

  static String _normalizeLookupKey(String input) {
    var normalized = input.trim().toLowerCase();
    normalized = normalized.replaceAll(RegExp(r"['’]"), '');
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    normalized = normalized.replaceFirst(
      RegExp(r'^(?:suratul|surah|surat|sura|sorah)\s*'),
      '',
    );
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  static String _compactLookupKey(String input) {
    return _normalizeLookupKey(input).replaceAll(' ', '');
  }
}
