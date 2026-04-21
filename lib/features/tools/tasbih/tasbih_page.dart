import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

class TasbihPage extends StatefulWidget {
  const TasbihPage({super.key});

  @override
  State<TasbihPage> createState() => _TasbihPageState();
}

class _TasbihPageState extends State<TasbihPage> {
  static const List<String> _dhikrs = [
    'SubhanAllah',
    'Alhamdulillah',
    'Allahu Akbar',
    'La ilaha illa Allah',
    'Astaghfirullah',
    'La hawla wa la quwwata illa billah',
  ];
  static const List<int> _targets = [33, 100, 500];

  int _count = 0;
  int _total = 0;
  int _dhikrIndex = 0;
  int _target = 33;
  bool _hapticsOn = true;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _prefs = p;
      _count = p.getInt('tasbih.count') ?? 0;
      _total = p.getInt('tasbih.total') ?? 0;
      _dhikrIndex = p.getInt('tasbih.dhikrIndex') ?? 0;
      _target = p.getInt('tasbih.target') ?? 33;
      _hapticsOn = p.getBool('tasbih.haptics') ?? true;
    });
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt('tasbih.count', _count);
    await p.setInt('tasbih.total', _total);
    await p.setInt('tasbih.dhikrIndex', _dhikrIndex);
    await p.setInt('tasbih.target', _target);
    await p.setBool('tasbih.haptics', _hapticsOn);
  }

  void _increment() {
    setState(() {
      _count++;
      _total++;
    });
    if (_hapticsOn) HapticFeedback.lightImpact();
    if (_count % _target == 0) {
      if (_hapticsOn) HapticFeedback.mediumImpact();
    }
    _save();
  }

  void _reset() {
    setState(() => _count = 0);
    _save();
  }

  void _resetAll() {
    setState(() {
      _count = 0;
      _total = 0;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_count % _target) / _target;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tasbih'),
        actions: [
          IconButton(
            tooltip: 'Haptics',
            onPressed: () {
              setState(() => _hapticsOn = !_hapticsOn);
              _save();
            },
            icon: Icon(_hapticsOn
                ? Icons.vibration_rounded
                : Icons.do_not_disturb_on_outlined),
          ),
          IconButton(
            tooltip: 'Reset total',
            onPressed: _resetAll,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _dhikrSelector(),
            const SizedBox(height: 20),
            Text(
              'Target: $_target',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            Wrap(
              spacing: 6,
              children: _targets
                  .map(
                    (t) => ChoiceChip(
                      label: Text('$t'),
                      selected: _target == t,
                      onSelected: (_) {
                        setState(() => _target = t);
                        _save();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: _increment,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 260,
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          height: 260,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 10,
                            backgroundColor: AppColors.divider,
                            color: AppColors.gold,
                          ),
                        ),
                        Container(
                          width: 210,
                          height: 210,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.cardGradient,
                            border: Border.all(color: AppColors.gold30),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$_count',
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 64,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Cycle ${(_count ~/ _target)} • Total $_total',
                                style: const TextStyle(
                                    color: AppColors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Tap anywhere on the circle to count',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 4, 20, MediaQuery.of(context).padding.bottom + 80),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _increment,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Count'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dhikrSelector() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _dhikrs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final selected = i == _dhikrIndex;
          return ChoiceChip(
            label: Text(_dhikrs[i]),
            selected: selected,
            onSelected: (_) {
              setState(() => _dhikrIndex = i);
              _save();
            },
          );
        },
      ),
    );
  }
}
