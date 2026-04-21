import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'names_data.dart';

class NamesOfAllahPage extends StatefulWidget {
  const NamesOfAllahPage({super.key});

  @override
  State<NamesOfAllahPage> createState() => _NamesOfAllahPageState();
}

class _NamesOfAllahPageState extends State<NamesOfAllahPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().trim();
    final names = q.isEmpty
        ? namesOfAllah
        : namesOfAllah.where((n) {
            return n.transliteration.toLowerCase().contains(q) ||
                n.meaning.toLowerCase().contains(q) ||
                n.arabic.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('99 Names of Allah')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search names or meanings…',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    16, 4, 16, MediaQuery.of(context).padding.bottom + 80),
                itemCount: names.length,
                itemBuilder: (_, i) => _tile(names[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(NameOfAllah n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.gold10,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold20),
            ),
            alignment: Alignment.center,
            child: Text('${n.number}',
                style: const TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.arabic,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl),
                const SizedBox(height: 4),
                Text(n.transliteration,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(n.meaning,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
