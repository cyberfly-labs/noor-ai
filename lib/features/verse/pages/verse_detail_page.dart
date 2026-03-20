import 'package:flutter/material.dart';

import '../../../core/models/verse.dart';
import '../../../core/services/llm_service.dart';
import '../../../core/services/quran_api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/prompt_templates.dart';

class VerseDetailPage extends StatefulWidget {
  const VerseDetailPage({
    super.key,
    required this.surahNumber,
    required this.ayahNumber,
  });

  final int surahNumber;
  final int ayahNumber;

  @override
  State<VerseDetailPage> createState() => _VerseDetailPageState();
}

class _VerseDetailPageState extends State<VerseDetailPage> {
  late final Future<_VerseDetailData> _detailFuture;
  Future<String?>? _tafsirTranslationFuture;
  String? _tafsirTranslationSource;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  @override
  Widget build(BuildContext context) {
    final verseKey = '${widget.surahNumber}:${widget.ayahNumber}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Verse $verseKey'),
      ),
      body: FutureBuilder<_VerseDetailData>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            );
          }

          final detail = snapshot.data;
          if (detail == null || detail.verse == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'I could not load the full details for verse $verseKey.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        detail.verse!.verseKey,
                        style: TextStyle(
                          color: AppColors.gold.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        detail.verse!.arabicText ?? '',
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 28,
                          height: 1.9,
                        ),
                      ),
                      if ((detail.verse!.translationText ?? '').isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          detail.verse!.translationText!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.6,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Tafsir',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((detail.tafsirSource ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            detail.tafsirSource!,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Text(
                        (detail.tafsirText ?? '').isNotEmpty
                            ? detail.tafsirText!
                            : 'No tafsir is available for this verse right now.',
                        style: TextStyle(
                          color: AppColors.textPrimary.withValues(alpha: 0.95),
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_translationFutureFor(detail.tafsirText) case final translationFuture?) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Tafsir Translation',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.12)),
                    ),
                    child: FutureBuilder<String?>(
                      future: translationFuture,
                      builder: (context, translationSnapshot) {
                        if (translationSnapshot.connectionState == ConnectionState.waiting) {
                          return Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.gold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Translating tafsir...',
                                  style: TextStyle(
                                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        final translationText = translationSnapshot.data?.trim() ?? '';
                        if (translationText.isEmpty) {
                          return Text(
                            'Translation is not available for this tafsir right now.',
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(alpha: 0.9),
                              fontSize: 14,
                              height: 1.6,
                            ),
                          );
                        }

                        return Text(
                          translationText,
                          style: TextStyle(
                            color: AppColors.textPrimary.withValues(alpha: 0.95),
                            fontSize: 14,
                            height: 1.6,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<_VerseDetailData> _loadDetail() async {
    final results = await Future.wait<dynamic>([
      QuranApiService.instance.getVerse(
        widget.surahNumber,
        widget.ayahNumber,
      ),
      QuranApiService.instance.getVerseTafsir(
        widget.surahNumber,
        widget.ayahNumber,
      ),
      QuranApiService.instance.getVerseTafsirSource(
        widget.surahNumber,
        widget.ayahNumber,
      ),
    ]);

    return _VerseDetailData(
      verse: results[0] as Verse?,
      tafsirText: results[1] as String?,
      tafsirSource: results[2] as String?,
    );
  }

  Future<String?>? _translationFutureFor(String? tafsirText) {
    final text = tafsirText?.trim() ?? '';
    if (text.isEmpty || !_containsArabic(text)) {
      _tafsirTranslationSource = null;
      _tafsirTranslationFuture = null;
      return null;
    }

    if (_tafsirTranslationSource == text && _tafsirTranslationFuture != null) {
      return _tafsirTranslationFuture;
    }

    _tafsirTranslationSource = text;
    _tafsirTranslationFuture = _translateTafsirIfNeeded(text);
    return _tafsirTranslationFuture;
  }

  Future<String?> _translateTafsirIfNeeded(String? tafsirText) async {
    final text = tafsirText?.trim() ?? '';
    if (text.isEmpty || !_containsArabic(text)) {
      return null;
    }

    try {
      final translated = await LlmService.instance
          .generateComplete(
            PromptTemplates.translateTafsirText(tafsirText: text),
          )
          .timeout(const Duration(seconds: 15));
      final normalized = translated.trim();
      if (normalized.isEmpty || normalized == text) {
        return null;
      }
      return normalized;
    } catch (_) {
      return null;
    }
  }

  bool _containsArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }
}

class _VerseDetailData {
  const _VerseDetailData({
    required this.verse,
    required this.tafsirText,
    required this.tafsirSource,
  });

  final Verse? verse;
  final String? tafsirText;
  final String? tafsirSource;
}