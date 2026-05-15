import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'database_service.dart';

/// Service to interact with the Quran MCP server (mcp.quran.ai).
/// This provides grounded, canonical Quranic data including search, translations, and tafsir.
class QuranMcpService {
  QuranMcpService._();
  static final QuranMcpService instance = QuranMcpService._();

  final String _baseUrl = 'https://mcp.quran.ai';
  final _dio = Dio();
  
  String? _sessionId;
  bool _isInitialized = false;
  
  /// Initialize the MCP session with the server.
  /// MCP requires an 'initialize' handshake and returns a session ID.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
          "protocolVersion": "2024-11-05",
          "capabilities": {},
          "clientInfo": {"name": "noor-ai", "version": "1.0.0"}
        }
      };

      final response = await _dio.post(
        _baseUrl,
        data: payload,
        options: Options(
          headers: {
            'Accept': 'application/json, text/event-stream',
            'Content-Type': 'application/json',
          },
        ),
      );

      _sessionId = response.headers.value('mcp-session-id');
      
      if (_sessionId == null) {
        throw Exception('Failed to obtain MCP session ID');
      }

      _isInitialized = true;
      debugPrint('MCP Initialized with Session ID: $_sessionId');
    } catch (e) {
      debugPrint('MCP Initialization Error: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  /// Calls a tool on the MCP server.
  Future<dynamic> callTool(String name, Map<String, dynamic> arguments) async {
    if (!_isInitialized) {
      await initialize();
    }

    final payload = {
      "jsonrpc": "2.0",
      "id": const Uuid().v4(),
      "method": "tools/call",
      "params": {
        "name": name,
        "arguments": arguments,
      }
    };

    try {
      final response = await _dio.post(
        _baseUrl,
        data: payload,
        options: Options(
          headers: {
            'Accept': 'application/json, text/event-stream',
            'Content-Type': 'application/json',
            'mcp-session-id': _sessionId,
          },
        ),
      );

      final String body = response.data.toString();
      
      if (body.contains('data: ')) {
        final lines = body.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final dataJson = line.substring(6).trim();
            final Map<String, dynamic> json = jsonDecode(dataJson);
            
            if (json['error'] != null) {
              throw Exception(json['error']['message'] ?? 'MCP Tool Error');
            }
            
            final result = json['result'];
            if (result is Map<String, dynamic>) {
              // MCP often wraps the real tool output in a 'content' array of 'text' blocks.
              final content = result['content'] as List?;
              if (content != null && content.isNotEmpty) {
                final firstContent = content.first;
                if (firstContent['type'] == 'text') {
                  final text = firstContent['text'] as String;
                  // If the text itself is a JSON string (common in some MCP implementations), parse it.
                  if (text.trim().startsWith('{') || text.trim().startsWith('[')) {
                    try {
                      return jsonDecode(text);
                    } catch (_) {
                      // Fallback to returning the raw text block content
                    }
                  }
                  return firstContent;
                }
              }
              return result;
            }
          }
        }
      }
      
      throw Exception('Malformed MCP response: $body');
    } catch (e) {
      debugPrint('MCP Tool Call Error ($name): $e');
      if (e is DioException && e.response?.statusCode == 400) {
        _isInitialized = false;
      }
      rethrow;
    }
  }

  /// Semantic search across Quran text with optional translations.
  Future<List<Map<String, dynamic>>> searchQuran(String query, {int limit = 5}) async {
    final result = await callTool('search_quran', {
      'query': query,
      'translations': 'en-abdel-haleem',
    });
    
    // search_quran returns {"query": "...", "results": [...], "total_found": N, "pagination": {...}}
    // Each result has: ayah_key, surah, ayah, text, translations, url, relevance_score
    if (result is Map && result['results'] != null) {
      return (result['results'] as List).cast<Map<String, dynamic>>();
    }
    
    // Fallback for different response formats
    if (result is List) {
      return List<Map<String, dynamic>>.from(
        result.map((item) => Map<String, dynamic>.from(item as Map)),
      );
    }
    
    return [];
  }

  /// Fetch translation for a specific verse using fetch_translation.
  Future<String?> fetchTranslation(String verseKey, {String edition = 'en-abdel-haleem'}) async {
    final result = await callTool('fetch_translation', {
      'ayahs': verseKey,
      'editions': edition,
    });

    // fetch_translation response: {"ayahs": [...], "results": {"en-abdel-haleem": [{"ayah": "...", "text": "..."}]}}
    if (result is Map && result['results'] != null) {
      final resultsMap = result['results'] as Map;
      if (resultsMap.isNotEmpty) {
        final editionData = resultsMap.values.first;
        if (editionData is List && editionData.isNotEmpty) {
          return editionData.first['text'] as String?;
        }
      }
    }

    return null;
  }

  /// Fetch tafsir for a specific verse.
  Future<String?> fetchTafsir(String verseKey) async {
    final result = await callTool('fetch_tafsir', {
      'ayahs': verseKey,
      'editions': 'en-ibn-kathir',
    });
    
    // fetch_tafsir response: {"ayahs": [...], "results": {"en-ibn-kathir": [{"ayahs": [...], "range": "...", "text": "..."}]}}
    if (result is Map && result['results'] != null) {
      final resultsMap = result['results'] as Map;
      if (resultsMap.isNotEmpty) {
        final editionData = resultsMap.values.first;
        if (editionData is List && editionData.isNotEmpty) {
          return editionData.first['text'] as String?;
        }
      }
    }
    
    return null;
  }

  /// List all chapters (surahs) of the Quran using fetch_quran_metadata.
  Future<List<Map<String, dynamic>>> listChapters() async {
    // Check cache first
    try {
      final cachedChapters = await DatabaseService.instance.getCachedSurahs();
      if (cachedChapters.isNotEmpty && cachedChapters.length == 114) {
        debugPrint('Returning 114 surahs from local cache');
        return cachedChapters;
      }
    } catch (e) {
      debugPrint('Error reading surah cache: $e');
    }

    debugPrint('Cache empty or incomplete, fetching surahs from MCP...');
    final List<Map<String, dynamic>> chapters = [];
    
    // Using Future.wait with chunks to avoid overwhelming the server 
    // while still being much faster than sequential loops.
    const int chunkSize = 10;
    for (int i = 1; i <= 114; i += chunkSize) {
      final end = (i + chunkSize - 1) > 114 ? 114 : (i + chunkSize - 1);
      final chunkFutures = <Future<void>>[];
      
      for (int j = i; j <= end; j++) {
        final surahIndex = j;
        chunkFutures.add(() async {
          try {
            final result = await callTool('fetch_quran_metadata', {'surah': surahIndex});
            final surahList = result['surah'] as List?;
            if (surahList != null && surahList.isNotEmpty) {
              chapters.add(Map<String, dynamic>.from(surahList.first as Map));
            }
          } catch (e) {
            debugPrint('Error fetching metadata for surah $surahIndex: $e');
          }
        }());
      }
      
      await Future.wait(chunkFutures);
    }

    if (chapters.isNotEmpty) {
      // Sort by number before caching and returning
      chapters.sort((a, b) {
        final aNum = a['id'] as int? ?? a['chapter_number'] as int? ?? 0;
        final bNum = b['id'] as int? ?? b['chapter_number'] as int? ?? 0;
        return aNum.compareTo(bNum);
      });
      
      // Save to cache
      try {
        await DatabaseService.instance.insertSurahs(chapters);
        debugPrint('Cached ${chapters.length} surahs locally');
      } catch (e) {
        debugPrint('Error saving surah cache: $e');
      }
    }
    
    return chapters;
  }

  /// Get specific chapter information using fetch_quran_metadata.
  Future<Map<String, dynamic>?> getChapter(int chapterNumber) async {
    final result = await callTool('fetch_quran_metadata', {
      'surah': chapterNumber,
    });
    final surahList = result['surah'] as List?;
    if (surahList != null && surahList.isNotEmpty) {
      return Map<String, dynamic>.from(surahList.first as Map);
    }
    return null;
  }

  /// Get specific ayah content using fetch_quran.
  Future<Map<String, dynamic>?> getAyah(String verseKey) async {
    final result = await callTool('fetch_quran', {
      'ayahs': verseKey,
      'editions': 'ar-uthmani',
    });
    if (result is Map) {
      final ayahs = result['results'] as Map?;
      if (ayahs != null && ayahs.isNotEmpty) {
        final editionData = ayahs.values.first as List?;
        if (editionData != null && editionData.isNotEmpty) {
          return Map<String, dynamic>.from(editionData.first as Map);
        }
      }
    }
    return null;
  }
}
