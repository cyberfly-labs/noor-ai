import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import 'quiz_data.dart';

class IslamicQuizPage extends StatefulWidget {
  const IslamicQuizPage({super.key});

  @override
  State<IslamicQuizPage> createState() => _IslamicQuizPageState();
}

class _IslamicQuizPageState extends State<IslamicQuizPage> {
  static const _prefHighScore = 'quiz.highscore.v1';
  static const _prefPlayed = 'quiz.played.v1';
  static const _questionsPerRound = 10;

  late List<QuizQuestion> _round;
  int _index = 0;
  int _score = 0;
  int? _selected;
  bool _finished = false;

  int _highScore = 0;
  int _played = 0;

  @override
  void initState() {
    super.initState();
    _round = _pickRound();
    _loadStats();
  }

  List<QuizQuestion> _pickRound() {
    final bank = List<QuizQuestion>.of(kQuizBank);
    bank.shuffle(math.Random());
    return bank.take(_questionsPerRound).toList();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _highScore = prefs.getInt(_prefHighScore) ?? 0;
      _played = prefs.getInt(_prefPlayed) ?? 0;
    });
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    _played += 1;
    if (_score > _highScore) _highScore = _score;
    await prefs.setInt(_prefHighScore, _highScore);
    await prefs.setInt(_prefPlayed, _played);
  }

  void _answer(int i) {
    if (_selected != null) return;
    setState(() {
      _selected = i;
      if (i == _round[_index].correctIndex) _score += 1;
    });
  }

  void _next() {
    if (_index + 1 >= _round.length) {
      _saveStats();
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index += 1;
      _selected = null;
    });
  }

  void _restart() {
    setState(() {
      _round = _pickRound();
      _index = 0;
      _score = 0;
      _selected = null;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      appBar: AppBar(
        title: const Text('Islamic Quiz'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        bottom: false,
        child: _finished ? _buildResult() : _buildQuestion(),
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _round[_index];
    final progress = (_index + 1) / _round.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Question ${_index + 1} / ${_round.length}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gold10,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.gold25),
                    ),
                    child: Text(
                      q.category,
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceLightAlpha55,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.gold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            physics: const BouncingScrollPhysics(),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gold15),
                ),
                child: Text(
                  q.question,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (int i = 0; i < q.options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionTile(
                    label: q.options[i],
                    selected: _selected == i,
                    isCorrect: _selected != null && i == q.correctIndex,
                    isWrong: _selected == i && i != q.correctIndex,
                    onTap: () => _answer(i),
                  ),
                ),
              if (_selected != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.gold08,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold15),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded,
                          color: AppColors.gold, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          q.explanation,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _next,
                    child: Text(
                      _index + 1 >= _round.length ? 'See results' : 'Next',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                ),
              ],
              SizedBox(height: MediaQuery.of(context).padding.bottom + 60),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final pct = (_score / _round.length);
    final msg = pct >= 0.8
        ? 'Excellent! May Allah increase you in knowledge.'
        : pct >= 0.5
            ? 'Good effort — keep learning!'
            : 'Seeking knowledge is an act of worship. Try again!';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold25),
            ),
            child: Column(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    color: AppColors.gold, size: 48),
                const SizedBox(height: 12),
                Text(
                  '$_score / ${_round.length}',
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 36,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  label: 'High score',
                  value: '$_highScore / ${_round.length}',
                  icon: Icons.star_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatChip(
                  label: 'Rounds',
                  value: '$_played',
                  icon: Icons.replay_rounded,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _restart,
              child: const Text('Play again',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isCorrect;
  final bool isWrong;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.selected,
    required this.isCorrect,
    required this.isWrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.card;
    Color border = AppColors.divider;
    IconData? trailing;
    Color trailingColor = AppColors.textMuted;

    if (isCorrect) {
      bg = AppColors.success.withValues(alpha: 0.12);
      border = AppColors.success;
      trailing = Icons.check_circle_rounded;
      trailingColor = AppColors.success;
    } else if (isWrong) {
      bg = AppColors.errorAlpha10;
      border = AppColors.error;
      trailing = Icons.cancel_rounded;
      trailingColor = AppColors.error;
    } else if (selected) {
      border = AppColors.gold;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                      height: 1.4),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Icon(trailing, color: trailingColor, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatChip(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold15),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
