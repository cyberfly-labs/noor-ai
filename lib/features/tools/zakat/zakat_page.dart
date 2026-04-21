import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ZakatPage extends StatefulWidget {
  const ZakatPage({super.key});

  @override
  State<ZakatPage> createState() => _ZakatPageState();
}

class _ZakatPageState extends State<ZakatPage> {
  final _cash = TextEditingController();
  final _bank = TextEditingController();
  final _gold = TextEditingController(); // grams of gold
  final _silver = TextEditingController(); // grams of silver
  final _investments = TextEditingController();
  final _business = TextEditingController();
  final _liabilities = TextEditingController();

  final _goldPrice = TextEditingController(text: '75'); // USD per gram
  final _silverPrice = TextEditingController(text: '0.95'); // USD per gram

  double get _goldPricePerGram => double.tryParse(_goldPrice.text) ?? 0;
  double get _silverPricePerGram => double.tryParse(_silverPrice.text) ?? 0;

  double _num(TextEditingController c) => double.tryParse(c.text) ?? 0;

  double get _goldValue => _num(_gold) * _goldPricePerGram;
  double get _silverValue => _num(_silver) * _silverPricePerGram;

  double get _assets =>
      _num(_cash) +
      _num(_bank) +
      _goldValue +
      _silverValue +
      _num(_investments) +
      _num(_business);

  double get _netWealth => (_assets - _num(_liabilities)).clamp(0, double.infinity);

  // Nisab: 87.48g gold OR 612.36g silver — use silver for lower threshold
  // (more zakat-eligible) per majority scholars.
  double get _nisab => 612.36 * _silverPricePerGram;

  bool get _meetsNisab => _netWealth >= _nisab;
  double get _zakatDue => _meetsNisab ? _netWealth * 0.025 : 0;

  @override
  void dispose() {
    for (final c in [
      _cash,
      _bank,
      _gold,
      _silver,
      _investments,
      _business,
      _liabilities,
      _goldPrice,
      _silverPrice,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Zakat Calculator')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).padding.bottom + 100),
          children: [
            _result(),
            const SizedBox(height: 20),
            const _SectionLabel('Assets'),
            _field('Cash on hand', _cash, prefix: '\$'),
            _field('Bank balances', _bank, prefix: '\$'),
            _field('Gold (grams)', _gold, suffix: 'g'),
            _field('Silver (grams)', _silver, suffix: 'g'),
            _field('Investments / stocks', _investments, prefix: '\$'),
            _field('Business inventory', _business, prefix: '\$'),
            const SizedBox(height: 8),
            const _SectionLabel('Liabilities'),
            _field('Debts due', _liabilities, prefix: '\$'),
            const SizedBox(height: 8),
            const _SectionLabel('Metal prices (per gram)'),
            _field('Gold price', _goldPrice, prefix: '\$'),
            _field('Silver price', _silverPrice, prefix: '\$'),
            const SizedBox(height: 20),
            Text(
              'Zakat is 2.5% of net wealth held for one lunar year above the '
              'nisab threshold. The silver nisab (≈612g) is used as the lower '
              'bound. This calculator is a guide; consult a scholar for '
              'edge cases.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _result() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_meetsNisab ? 'Zakat due' : 'Below nisab',
              style: const TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('\$${_zakatDue.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 34,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              'Net wealth: \$${_netWealth.toStringAsFixed(2)} • '
              'Nisab: \$${_nisab.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.black87, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {String? prefix, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: AppColors.textPrimary),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textMuted),
          prefixText: prefix == null ? null : '$prefix ',
          suffixText: suffix,
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 6),
        child: Text(label,
            style: const TextStyle(
                color: AppColors.gold, fontWeight: FontWeight.w700)),
      );
}
