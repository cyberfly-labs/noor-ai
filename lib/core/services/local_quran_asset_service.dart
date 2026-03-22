import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/surah.dart';
import '../models/verse.dart';
import 'vector_store_service.dart';

class LocalQuranAssetService {
  LocalQuranAssetService._();

  static final LocalQuranAssetService instance = LocalQuranAssetService._();

  static const String _arabicAssetPath = 'assets/db/quran.db';
  static const String _translationAssetPath = 'assets/db/english_saheeh.db';
  static const String _transliterationAssetPath = 'assets/db/english_transliteration.db';
  static const String _tafsirAssetPath = 'assets/db/quran-tafsir-english.db';
  static const String _tafsirSourceLabel = 'Local English Tafsir';

  Future<void>? _initializeFuture;
  Database? _arabicDb;
  Database? _translationDb;
  Database? _transliterationDb;
  Database? _tafsirDb;
  List<Surah>? _surahCache;

  Future<void> initialize() {
    final pending = _initializeFuture;
    if (pending != null) {
      return pending;
    }

    final future = _initializeInternal();
    _initializeFuture = future;
    return future;
  }

  Future<void> _initializeInternal() async {
    _arabicDb = await _openAssetDatabase(_arabicAssetPath, 'quran_local_asset.db');
    _translationDb = await _openAssetDatabase(
      _translationAssetPath,
      'english_saheeh_local_asset.db',
    );
    _transliterationDb = await _openAssetDatabase(
      _transliterationAssetPath,
      'english_transliteration_local_asset.db',
    );
    _tafsirDb = await _openAssetDatabase(
      _tafsirAssetPath,
      'quran_tafsir_english_local_asset.db',
    );
  }

  Future<Database> _openAssetDatabase(String assetPath, String fileName) async {
    final databasesPath = await getDatabasesPath();
    final targetPath = p.join(databasesPath, 'noor_assets', fileName);
    final file = File(targetPath);

    await file.parent.create(recursive: true);

    if (kDebugMode || !await file.exists()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    return openDatabase(
      targetPath,
      readOnly: true,
      singleInstance: true,
    );
  }

  Future<Database> get _arabic async {
    await initialize();
    return _arabicDb!;
  }

  Future<Database> get _translation async {
    await initialize();
    return _translationDb!;
  }

  Future<Database> get _transliteration async {
    await initialize();
    return _transliterationDb!;
  }

  Future<Database> get _tafsir async {
    await initialize();
    return _tafsirDb!;
  }

  Future<Verse?> getVerse(int surahNumber, int ayahNumber) async {
    final arabicDb = await _arabic;
    final rows = await arabicDb.query(
      'quran',
      where: 'sora = ? AND aya_no = ?',
      whereArgs: <Object>[surahNumber, ayahNumber],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final translation = await _getTranslationText(surahNumber, ayahNumber);
    final transliteration = await _getTransliterationText(surahNumber, ayahNumber);

    return Verse(
      verseKey: '$surahNumber:$ayahNumber',
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      arabicText: _normalizedText(
        row['aya_text_tashkil'] as String? ?? row['aya_text'] as String?,
      ),
      translationText: translation,
      transliteration: transliteration,
    );
  }

  Future<List<Verse>> getSurahVerses(int surahNumber) async {
    final arabicDb = await _arabic;
    final translationDb = await _translation;
    final transliterationDb = await _transliteration;

    final arabicRows = await arabicDb.query(
      'quran',
      where: 'sora = ?',
      whereArgs: <Object>[surahNumber],
      orderBy: 'aya_no ASC',
    );
    if (arabicRows.isEmpty) {
      return const <Verse>[];
    }

    final translationRows = await translationDb.query(
      'english_saheeh',
      columns: const <String>['sura', 'aya', 'text'],
      where: 'sura = ?',
      whereArgs: <Object>[surahNumber],
      orderBy: 'aya ASC',
    );
    final transliterationRows = await transliterationDb.query(
      'english_transliteration',
      columns: const <String>['sura', 'aya', 'text'],
      where: 'sura = ?',
      whereArgs: <Object>[surahNumber],
      orderBy: 'aya ASC',
    );

    final translationMap = <int, String>{
      for (final row in translationRows)
        row['aya'] as int: _normalizedText(row['text'] as String?) ?? '',
    };
    final transliterationMap = <int, String>{
      for (final row in transliterationRows)
        row['aya'] as int: _normalizedHtmlText(row['text'] as String?) ?? '',
    };

    return arabicRows.map((row) {
      final ayahNumber = row['aya_no'] as int;
      return Verse(
        verseKey: '$surahNumber:$ayahNumber',
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
        arabicText: _normalizedText(
          row['aya_text_tashkil'] as String? ?? row['aya_text'] as String?,
        ),
        translationText: translationMap[ayahNumber],
        transliteration: transliterationMap[ayahNumber],
      );
    }).toList(growable: false);
  }

  Future<List<Surah>> listSurahs() async {
    final cached = _surahCache;
    if (cached != null) {
      return cached;
    }

    final arabicDb = await _arabic;
    final rows = await arabicDb.rawQuery('''
      SELECT
        sora,
        sora_name_en,
        sora_name_ar,
        MAX(aya_no) AS ayah_count,
        MIN(page) AS first_page,
        MAX(page) AS last_page
      FROM quran
      GROUP BY sora, sora_name_en, sora_name_ar
      ORDER BY sora ASC
    ''');

    final surahs = rows.map((row) {
      final firstPage = row['first_page'] as int? ?? 0;
      final lastPage = row['last_page'] as int? ?? firstPage;
      final pages = <int>[];
      if (firstPage > 0) {
        pages.add(firstPage);
        if (lastPage > firstPage) {
          pages.add(lastPage);
        }
      }

      final surahNumber = row['sora'] as int? ?? 0;
      final englishName = _normalizedText(row['sora_name_en'] as String?) ?? 'Surah $surahNumber';

      return Surah(
        number: surahNumber,
        name: _normalizedText(row['sora_name_ar'] as String?) ?? '',
        englishName: englishName,
        englishNameTranslation: englishName,
        numberOfAyahs: row['ayah_count'] as int? ?? 0,
        revelationType: _revelationTypeForSurah(surahNumber),
        pages: pages,
      );
    }).toList(growable: false);

    _surahCache = surahs;
    return surahs;
  }

  Future<String?> getVerseTafsir(int surahNumber, int ayahNumber) async {
    final verseKey = '$surahNumber:$ayahNumber';
    final tafsirDb = await _tafsir;

    final exact = await tafsirDb.query(
      'tafsir',
      columns: const <String>['text'],
      where: 'ayah_key = ?',
      whereArgs: <Object>[verseKey],
      limit: 1,
    );
    if (exact.isNotEmpty) {
      return _normalizedText(exact.first['text'] as String?);
    }

    final grouped = await tafsirDb.query(
      'tafsir',
      columns: const <String>['text'],
      where: 'group_ayah_key = ? OR ayah_keys LIKE ?',
      whereArgs: <Object>[verseKey, '%$verseKey%'],
      limit: 1,
    );
    if (grouped.isNotEmpty) {
      return _normalizedText(grouped.first['text'] as String?);
    }

    return null;
  }

  Future<String?> getVerseTafsirSource(int surahNumber, int ayahNumber) async {
    final text = await getVerseTafsir(surahNumber, ayahNumber);
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return _tafsirSourceLabel;
  }

  Future<List<Verse>> search(String query, {int limit = 8}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <Verse>[];
    }

    final verseKeyMatch = RegExp(r'^(\d{1,3}):(\d{1,3})$').firstMatch(trimmed);
    if (verseKeyMatch != null) {
      final verse = await getVerse(
        int.parse(verseKeyMatch.group(1)!),
        int.parse(verseKeyMatch.group(2)!),
      );
      return verse == null ? const <Verse>[] : <Verse>[verse];
    }

    final arabicDb = await _arabic;
    final translationDb = await _translation;
    final transliterationDb = await _transliteration;
    final tafsirDb = await _tafsir;
    final likeQuery = '%${trimmed.toLowerCase()}%';
    final weighted = <String, int>{};

    void addMatch(String verseKey, int weight) {
      final current = weighted[verseKey] ?? 0;
      weighted[verseKey] = current + weight;
    }

    final translationMatches = await translationDb.rawQuery(
      '''
      SELECT sura, aya
      FROM english_saheeh
      WHERE lower(text) LIKE ? OR lower(COALESCE(footnotes, '')) LIKE ?
      LIMIT 16
      ''',
      <Object>[likeQuery, likeQuery],
    );
    for (final row in translationMatches) {
      addMatch('${row['sura']}:${row['aya']}', 5);
    }

    final tafsirMatches = await tafsirDb.rawQuery(
      '''
      SELECT ayah_key
      FROM tafsir
      WHERE lower(text) LIKE ?
      LIMIT 12
      ''',
      <Object>[likeQuery],
    );
    for (final row in tafsirMatches) {
      final verseKey = row['ayah_key'] as String?;
      if (verseKey != null && verseKey.isNotEmpty) {
        addMatch(verseKey, 4);
      }
    }

    final transliterationMatches = await transliterationDb.rawQuery(
      '''
      SELECT sura, aya
      FROM english_transliteration
      WHERE lower(text) LIKE ?
      LIMIT 12
      ''',
      <Object>[likeQuery],
    );
    for (final row in transliterationMatches) {
      addMatch('${row['sura']}:${row['aya']}', 3);
    }

    final arabicMatches = await arabicDb.rawQuery(
      '''
      SELECT sora, aya_no
      FROM quran
      WHERE aya_text LIKE ?
         OR aya_text_emlaey LIKE ?
         OR lower(sora_name_en) LIKE ?
         OR sora_name_ar LIKE ?
      LIMIT 12
      ''',
      <Object>['%$trimmed%', '%$trimmed%', likeQuery, '%$trimmed%'],
    );
    for (final row in arabicMatches) {
      addMatch('${row['sora']}:${row['aya_no']}', 6);
    }

    final rankedKeys = weighted.entries.toList()
      ..sort((left, right) {
        final scoreCompare = right.value.compareTo(left.value);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return left.key.compareTo(right.key);
      });

    final verses = <Verse>[];
    for (final match in rankedKeys.take(limit)) {
      final parts = match.key.split(':');
      if (parts.length != 2) {
        continue;
      }

      final surahNumber = int.tryParse(parts[0]);
      final ayahNumber = int.tryParse(parts[1]);
      if (surahNumber == null || ayahNumber == null) {
        continue;
      }

      final verse = await getVerse(surahNumber, ayahNumber);
      if (verse != null) {
        verses.add(verse);
      }
    }

    return verses;
  }

  Future<List<VectorSeedDocument>> loadVectorDocuments() async {
    final arabicDb = await _arabic;
    final translationDb = await _translation;
    final tafsirDb = await _tafsir;

    final arabicRows = await arabicDb.query(
      'quran',
      columns: const <String>[
        'sora',
        'aya_no',
      ],
      orderBy: 'id ASC',
    );
    final translationRows = await translationDb.query(
      'english_saheeh',
      columns: const <String>['sura', 'aya', 'text', 'footnotes'],
    );
    final tafsirRows = await tafsirDb.query(
      'tafsir',
      columns: const <String>['ayah_key', 'text'],
    );

    final translationMap = <String, String>{
      for (final row in translationRows)
        '${row['sura']}:${row['aya']}': _combineTranslationParts(
              row['text'] as String?,
              row['footnotes'] as String?,
            ) ?? '',
    };
    final tafsirMap = <String, String>{
      for (final row in tafsirRows)
        (row['ayah_key'] as String?) ?? '': _normalizedText(
              row['text'] as String?,
            ) ?? '',
    };

    final documents = <VectorSeedDocument>[];

    for (final row in arabicRows) {
      final surahNumber = row['sora'] as int? ?? 0;
      final ayahNumber = row['aya_no'] as int? ?? 0;
      final verseKey = '$surahNumber:$ayahNumber';
      final translation = translationMap[verseKey] ?? '';
      final tafsir = tafsirMap[verseKey] ?? '';

      final sections = <String>[];

      if (translation.isNotEmpty) {
        sections.add('Translation: $translation');
      }
      if (tafsir.isNotEmpty) {
        sections.add('Tafsir: $tafsir');
      }

      if (sections.isEmpty) {
        continue;
      }

      documents.add(VectorSeedDocument(
        id: 'quran_$verseKey',
        content: sections.join('\n'),
        metadata: <String, String>{
          'kind': 'quran_corpus',
          'verse_key': verseKey,
          'surah': surahNumber.toString(),
          'ayah': ayahNumber.toString(),
          'source': _tafsirSourceLabel,
        },
      ));
    }

    return documents;
  }

  Future<String?> _getTranslationText(int surahNumber, int ayahNumber) async {
    final translationDb = await _translation;
    final rows = await translationDb.query(
      'english_saheeh',
      columns: const <String>['text'],
      where: 'sura = ? AND aya = ?',
      whereArgs: <Object>[surahNumber, ayahNumber],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _normalizedText(rows.first['text'] as String?);
  }

  Future<String?> _getTransliterationText(int surahNumber, int ayahNumber) async {
    final transliterationDb = await _transliteration;
    final rows = await transliterationDb.query(
      'english_transliteration',
      columns: const <String>['text'],
      where: 'sura = ? AND aya = ?',
      whereArgs: <Object>[surahNumber, ayahNumber],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _normalizedHtmlText(rows.first['text'] as String?);
  }

  String? _combineTranslationParts(String? text, String? footnotes) {
    final normalizedText = _normalizedText(text);
    final normalizedFootnotes = _normalizedText(footnotes);
    if (normalizedText == null || normalizedText.isEmpty) {
      return normalizedFootnotes;
    }
    if (normalizedFootnotes == null || normalizedFootnotes.isEmpty) {
      return normalizedText;
    }
    return '$normalizedText\nFootnotes: $normalizedFootnotes';
  }

  String? _normalizedHtmlText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return _normalizedText(
      value
          .replaceAll(RegExp(r'<[^>]+>', caseSensitive: false), '')
          .replaceAll('&nbsp;', ' '),
    );
  }

  String? _normalizedText(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('﴿', '')
        .replaceAll('﴾', '')
        .trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _revelationTypeForSurah(int surahNumber) {
    return _madinanSurahs.contains(surahNumber) ? 'medinan' : 'meccan';
  }

  static const Set<int> _madinanSurahs = <int>{
    2,
    3,
    4,
    5,
    8,
    9,
    22,
    24,
    33,
    47,
    48,
    49,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    76,
    98,
    99,
    110,
  };
}