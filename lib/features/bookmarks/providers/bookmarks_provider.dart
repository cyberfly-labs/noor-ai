import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/bookmark.dart';
import '../../../core/models/verse.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/quran_user_sync_service.dart';

class BookmarksState {
  final List<Bookmark> bookmarks;
  final bool isLoading;

  const BookmarksState({this.bookmarks = const [], this.isLoading = false});

  BookmarksState copyWith({List<Bookmark>? bookmarks, bool? isLoading}) {
    return BookmarksState(
      bookmarks: bookmarks ?? this.bookmarks,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class BookmarksNotifier extends StateNotifier<BookmarksState> {
  BookmarksNotifier() : super(const BookmarksState());

  final _db = DatabaseService.instance;
  final _sync = QuranUserSyncService.instance;

  Future<void> load() async {
    state = state.copyWith(isLoading: true);

    if (await _sync.isReadyForSync) {
      try {
        await _sync.syncBookmarksToLocal();
      } catch (error) {
        debugPrint('Bookmarks: Remote merge skipped: $error');
      }
    }

    final bookmarks = await _db.getBookmarks();
    state = BookmarksState(bookmarks: bookmarks, isLoading: false);
  }

  Future<void> add(Bookmark bookmark) async {
    await _db.insertBookmark(bookmark);
    await load();

    final verse = _verseFromKey(
      bookmark.verseKey,
      arabicText: bookmark.arabicText,
      translationText: bookmark.translationText,
    );
    if (verse != null) {
      await _sync.addVerseBookmark(verse);
    }
  }

  Future<void> remove(String verseKey) async {
    final verse = _verseFromKey(verseKey);
    await _db.deleteBookmarkByVerseKey(verseKey);
    await load();

    if (verse != null) {
      await _sync.removeVerseBookmark(verse);
    }
  }

  Future<bool> toggleVerse(
    Verse verse, {
    String? surahName,
    String? note,
  }) async {
    final alreadyBookmarked = await _db.isBookmarked(verse.verseKey);

    if (alreadyBookmarked) {
      await _db.deleteBookmarkByVerseKey(verse.verseKey);
      await load();
      await _sync.removeVerseBookmark(verse);
      return false;
    }

    final bookmark = Bookmark(
      id: verse.verseKey,
      verseKey: verse.verseKey,
      surahName: surahName ?? 'Surah ${verse.surahNumber}',
      arabicText: verse.arabicText,
      translationText: verse.translationText,
      note: note,
      createdAt: DateTime.now(),
    );

    await _db.insertBookmark(bookmark);
    await load();
    await _sync.addVerseBookmark(verse);
    return true;
  }

  Future<bool> isBookmarked(String verseKey) async {
    return _db.isBookmarked(verseKey);
  }

  Future<void> syncWithRemote() async {
    if (!await _sync.isReadyForSync) {
      return;
    }

    state = state.copyWith(isLoading: true);
    await _sync.syncNow();
    final bookmarks = await _db.getBookmarks();
    state = BookmarksState(bookmarks: bookmarks, isLoading: false);
  }

  Verse? _verseFromKey(
    String verseKey, {
    String? arabicText,
    String? translationText,
  }) {
    final parts = verseKey.split(':');
    if (parts.length != 2) {
      return null;
    }

    final surahNumber = int.tryParse(parts.first);
    final ayahNumber = int.tryParse(parts.last);
    if (surahNumber == null || ayahNumber == null) {
      return null;
    }

    return Verse(
      verseKey: verseKey,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      arabicText: arabicText,
      translationText: translationText,
    );
  }
}

final bookmarksProvider =
    StateNotifierProvider<BookmarksNotifier, BookmarksState>((ref) {
  return BookmarksNotifier();
});
