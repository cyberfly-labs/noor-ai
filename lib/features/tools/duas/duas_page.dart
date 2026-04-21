import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import 'duas_data.dart';

class DuasPage extends StatefulWidget {
  const DuasPage({super.key});

  @override
  State<DuasPage> createState() => _DuasPageState();
}

class _DuasPageState extends State<DuasPage> {
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final categories = ['All', ...{for (final d in duas) d.category}];
    final list = _selectedCategory == 'All'
        ? duas
        : duas.where((d) => d.category == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Duas')),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final c = categories[i];
                  return Center(
                    child: ChoiceChip(
                      label: Text(c),
                      selected: _selectedCategory == c,
                      onSelected: (_) => setState(() => _selectedCategory = c),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, MediaQuery.of(context).padding.bottom + 80),
                itemCount: list.length,
                itemBuilder: (_, i) => _tile(list[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Dua d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(d.title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: '${d.arabic}\n\n${d.transliteration}\n\n${d.translation}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Copied'), duration: Duration(seconds: 1)),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(d.arabic,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 22,
                height: 1.9,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl),
          const SizedBox(height: 10),
          Text(d.transliteration,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                  fontSize: 13.5,
                  height: 1.5)),
          const SizedBox(height: 8),
          Text(d.translation,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14, height: 1.5)),
          if (d.reference != null) ...[
            const SizedBox(height: 8),
            Text('— ${d.reference!}',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
