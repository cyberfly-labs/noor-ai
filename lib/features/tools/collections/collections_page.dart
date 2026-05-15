import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

/// A local verse collection (like a playlist of ayahs).
class VerseCollection {
  final String id;
  final String name;
  final String? description;
  final List<String> verseKeys;
  final DateTime createdAt;

  const VerseCollection({
    required this.id,
    required this.name,
    this.description,
    required this.verseKeys,
    required this.createdAt,
  });

  VerseCollection copyWith({
    String? name,
    String? description,
    List<String>? verseKeys,
  }) {
    return VerseCollection(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      verseKeys: verseKeys ?? this.verseKeys,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'verseKeys': verseKeys,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VerseCollection.fromJson(Map<String, dynamic> json) {
    return VerseCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      verseKeys: (json['verseKeys'] as List).cast<String>(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  static const _prefsKey = 'verse_collections.v1';

  List<VerseCollection> _collections = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() {
          _collections = list
              .map((e) => VerseCollection.fromJson(
                    (e as Map).cast<String, dynamic>(),
                  ))
              .toList();
        });
      } catch (_) {}
    }
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_collections.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _createCollection() async {
    final result = await showDialog<({String name, String desc})>(
      context: context,
      builder: (ctx) => _CreateCollectionDialog(),
    );
    if (result == null) return;

    final collection = VerseCollection(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: result.name,
      description: result.desc.isEmpty ? null : result.desc,
      verseKeys: const [],
      createdAt: DateTime.now(),
    );

    setState(() => _collections.insert(0, collection));
    await _save();
  }

  Future<void> _deleteCollection(VerseCollection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Delete Collection',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Delete "${collection.name}"? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _collections.removeWhere((c) => c.id == collection.id));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Collections'),
        actions: [
          IconButton(
            onPressed: _createCollection,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New collection',
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: !_loaded
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            : _collections.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).padding.bottom + 80,
                ),
                itemCount: _collections.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _CollectionCard(
                  collection: _collections[i],
                  onDelete: () => _deleteCollection(_collections[i]),
                  onTap: () => _openCollection(_collections[i]),
                ),
              ),
      ),
      floatingActionButton: _collections.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _createCollection,
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'New Collection',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }

  void _openCollection(VerseCollection collection) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CollectionDetailPage(
          collection: collection,
          onUpdated: (updated) {
            setState(() {
              final idx = _collections.indexWhere((c) => c.id == updated.id);
              if (idx >= 0) _collections[idx] = updated;
            });
            _save();
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceLight,
                border: Border.all(color: AppColors.divider),
              ),
              child: const Icon(
                Icons.collections_bookmark_rounded,
                size: 36,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No collections yet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create collections to organise your favourite verses by theme, topic, or mood.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _createCollection,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: Colors.black),
                    SizedBox(width: 8),
                    Text(
                      'Create Collection',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final VerseCollection collection;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _CollectionCard({
    required this.collection,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold15, width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.gold10,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.gold20),
              ),
              child: const Icon(
                Icons.collections_bookmark_rounded,
                color: AppColors.gold,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    collection.description?.isNotEmpty == true
                        ? collection.description!
                        : '${collection.verseKeys.length} verse${collection.verseKeys.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gold08,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${collection.verseKeys.length}',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionDetailPage extends StatefulWidget {
  final VerseCollection collection;
  final void Function(VerseCollection) onUpdated;

  const _CollectionDetailPage({
    required this.collection,
    required this.onUpdated,
  });

  @override
  State<_CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<_CollectionDetailPage> {
  late VerseCollection _collection;

  @override
  void initState() {
    super.initState();
    _collection = widget.collection;
  }

  void _removeVerse(String verseKey) {
    final updated = _collection.copyWith(
      verseKeys: _collection.verseKeys.where((k) => k != verseKey).toList(),
    );
    setState(() => _collection = updated);
    widget.onUpdated(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_collection.name),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        bottom: false,
        child: _collection.verseKeys.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bookmark_add_outlined,
                      size: 48,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No verses yet',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add verses from the Quran reader or verse detail page.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).padding.bottom + 80,
                ),
                itemCount: _collection.verseKeys.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final key = _collection.verseKeys[i];
                  return GestureDetector(
                    onTap: () {
                      final parts = key.split(':');
                      if (parts.length == 2) {
                        final s = int.tryParse(parts[0]);
                        final a = int.tryParse(parts[1]);
                        if (s != null && a != null) {
                          context.push('/verse/$s/$a');
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.divider,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold10,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.gold20),
                            ),
                            child: Text(
                              key,
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _removeVerse(key),
                            child: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _CreateCollectionDialog extends StatefulWidget {
  @override
  State<_CreateCollectionDialog> createState() =>
      _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends State<_CreateCollectionDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text(
        'New Collection',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Collection name',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Description (optional)',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        TextButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              (name: name, desc: _descCtrl.text.trim()),
            );
          },
          child: const Text(
            'Create',
            style: TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
