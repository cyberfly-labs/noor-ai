import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/bookmark.dart';
import '../models/chat_message.dart';
import '../models/daily_ayah.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'noor_ai.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE surahs (
          number INTEGER PRIMARY KEY,
          name_arabic TEXT,
          name_complex TEXT,
          name_simple TEXT,
          revelation_place TEXT,
          verses_count INTEGER,
          pages TEXT,
          translated_name TEXT
        )
      ''');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        role TEXT NOT NULL,
        intent TEXT,
        verse_key TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        verse_key TEXT NOT NULL,
        surah_name TEXT,
        arabic_text TEXT,
        translation_text TEXT,
        note TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE streaks (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        completed INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_ayah (
        id TEXT PRIMARY KEY,
        verse_key TEXT NOT NULL,
        arabic_text TEXT,
        translation_text TEXT,
        explanation TEXT,
        date TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE verse_cache (
        verse_key TEXT PRIMARY KEY,
        surah_number INTEGER,
        ayah_number INTEGER,
        arabic_text TEXT,
        translation_text TEXT,
        audio_url TEXT,
        cached_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE surahs (
        number INTEGER PRIMARY KEY,
        name_arabic TEXT,
        name_complex TEXT,
        name_simple TEXT,
        revelation_place TEXT,
        verses_count INTEGER,
        pages TEXT,
        translated_name TEXT
      )
    ''');
  }

  // ── Surahs Cache ──

  Future<void> insertSurahs(List<Map<String, dynamic>> surahs) async {
    final db = await database;
    final batch = db.batch();
    for (final surah in surahs) {
      batch.insert('surahs', {
        'number': surah['id'] ?? surah['chapter_number'] ?? surah['number'],
        'name_arabic': surah['name_arabic'],
        'name_complex': surah['name_complex'],
        'name_simple': surah['name_simple'],
        'revelation_place': surah['revelation_place'],
        'verses_count': surah['verses_count'],
        'pages': surah['pages'] != null ? surah['pages'].join(',') : null,
        'translated_name': surah['translated_name'] is Map 
            ? surah['translated_name']['name'] 
            : surah['translated_name'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedSurahs() async {
    final db = await database;
    final maps = await db.query('surahs', orderBy: 'number ASC');
    return maps.map((map) {
      final mutableMap = Map<String, dynamic>.from(map);
      if (mutableMap['pages'] != null) {
        mutableMap['pages'] = (mutableMap['pages'] as String)
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .toList();
      }
      if (mutableMap['translated_name'] != null) {
        mutableMap['translated_name'] = {'name': mutableMap['translated_name']};
      }
      return mutableMap;
    }).toList();
  }

  // ── Chat Messages ──

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert('chat_messages', message.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChatMessage>> getMessages({int limit = 100, int offset = 0}) async {
    final db = await database;
    final maps = await db.query(
      'chat_messages',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map(ChatMessage.fromDb).toList().reversed.toList();
  }

  Future<void> deleteMessage(String id) async {
    final db = await database;
    await db.delete('chat_messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearMessages() async {
    final db = await database;
    await db.delete('chat_messages');
  }

  // ── Bookmarks ──

  Future<void> insertBookmark(Bookmark bookmark) async {
    final db = await database;
    await db.insert('bookmarks', bookmark.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Bookmark>> getBookmarks() async {
    final db = await database;
    final maps = await db.query('bookmarks', orderBy: 'created_at DESC');
    return maps.map(Bookmark.fromDb).toList();
  }

  Future<bool> isBookmarked(String verseKey) async {
    final db = await database;
    final result = await db.query('bookmarks',
        where: 'verse_key = ?', whereArgs: [verseKey]);
    return result.isNotEmpty;
  }

  Future<void> deleteBookmark(String id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBookmarkByVerseKey(String verseKey) async {
    final db = await database;
    await db.delete('bookmarks', where: 'verse_key = ?', whereArgs: [verseKey]);
  }

  // ── Streaks ──

  Future<void> recordStreak(String date) async {
    final db = await database;
    await db.insert('streaks', {
      'id': date,
      'date': date,
      'completed': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> getCurrentStreak() async {
    final db = await database;
    final maps = await db.query('streaks',
        where: 'completed = 1', orderBy: 'date DESC');

    if (maps.isEmpty) return 0;

    int streak = 0;
    DateTime checkDate = DateTime.now();

    for (final map in maps) {
      final dateStr = map['date'] as String;
      final date = DateTime.parse(dateStr);
      final expected = DateTime(checkDate.year, checkDate.month, checkDate.day);
      final actual = DateTime(date.year, date.month, date.day);

      if (actual == expected || actual == expected.subtract(const Duration(days: 1))) {
        streak++;
        checkDate = actual;
      } else {
        break;
      }
    }
    return streak;
  }

  // ── Daily Ayah ──

  Future<void> insertDailyAyah(DailyAyah ayah) async {
    final db = await database;
    await db.insert('daily_ayah', ayah.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DailyAyah?> getDailyAyah(String date) async {
    final db = await database;
    final maps = await db.query('daily_ayah',
        where: 'date = ?', whereArgs: [date]);
    if (maps.isEmpty) return null;
    return DailyAyah.fromDb(maps.first);
  }

  // ── Verse Cache ──

  Future<void> cacheVerse(Map<String, dynamic> verseData) async {
    final db = await database;
    verseData['cached_at'] = DateTime.now().millisecondsSinceEpoch;
    await db.insert('verse_cache', verseData,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getCachedVerse(String verseKey) async {
    final db = await database;
    final maps = await db.query('verse_cache',
        where: 'verse_key = ?', whereArgs: [verseKey]);
    if (maps.isEmpty) return null;
    return maps.first;
  }
}
