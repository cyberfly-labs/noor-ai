import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class SeerahPage extends StatelessWidget {
  const SeerahPage({super.key});

  static const List<_Event> _events = [
    _Event(
      year: '570 CE',
      age: 'Year of the Elephant',
      title: 'Birth of the Prophet ﷺ',
      description:
          'Muhammad ﷺ is born in Mecca to Abdullah and Aminah, in the Year of the Elephant when Abraha failed to destroy the Ka\'bah.',
    ),
    _Event(
      year: '575 CE',
      age: 'Age 5',
      title: 'Splitting of the chest',
      description:
          'While with his foster mother Halimah, the Prophet ﷺ\'s chest is opened by angels and his heart purified.',
    ),
    _Event(
      year: '576 CE',
      age: 'Age 6',
      title: 'Death of his mother',
      description:
          'Aminah passes away at Abwa, leaving the young Muhammad ﷺ an orphan.',
    ),
    _Event(
      year: '578 CE',
      age: 'Age 8',
      title: 'Death of Abdul-Muttalib',
      description:
          'His grandfather dies; the Prophet ﷺ is raised by his uncle Abu Talib.',
    ),
    _Event(
      year: '595 CE',
      age: 'Age 25',
      title: 'Marriage to Khadijah رضي الله عنها',
      description:
          'Marries Khadijah bint Khuwaylid, a noble and successful merchant, after leading her trade caravan to Sham.',
    ),
    _Event(
      year: '605 CE',
      age: 'Age 35',
      title: 'Rebuilding of the Ka\'bah',
      description:
          'The Prophet ﷺ resolves a tribal dispute by placing the Black Stone on a cloth and having all chiefs lift it together.',
    ),
    _Event(
      year: '610 CE',
      age: 'Age 40',
      title: 'First revelation in the Cave of Hira',
      description:
          'Jibreel عليه السلام appears with the first verses of Surah Al-\'Alaq: "Read in the name of your Lord who created."',
    ),
    _Event(
      year: '613 CE',
      age: 'Age 43',
      title: 'Public call to Islam',
      description:
          'After three years of private da\'wah, the Prophet ﷺ openly invites his tribe at the hill of Safa.',
    ),
    _Event(
      year: '615 CE',
      age: 'Age 45',
      title: 'First migration to Abyssinia',
      description:
          'Persecuted companions migrate to Abyssinia (Ethiopia), finding refuge under the just king Najashi.',
    ),
    _Event(
      year: '619 CE',
      age: 'Year of Sorrow',
      title: 'Death of Khadijah and Abu Talib',
      description:
          'In a single year, the Prophet ﷺ loses both his wife Khadijah and his uncle Abu Talib, losing vital support.',
    ),
    _Event(
      year: '620 CE',
      age: 'Age 50',
      title: 'Isra and Mi\'raj',
      description:
          'The miraculous night journey from Mecca to Jerusalem, and ascent through the seven heavens. Five daily prayers are ordained.',
    ),
    _Event(
      year: '622 CE',
      age: 'Age 52 • Year 1 AH',
      title: 'The Hijrah to Madinah',
      description:
          'The Prophet ﷺ migrates with Abu Bakr to Madinah, establishing the first Islamic state. Islamic calendar begins.',
    ),
    _Event(
      year: '624 CE',
      age: '2 AH',
      title: 'Battle of Badr',
      description:
          'A decisive victory for 313 Muslims against 1,000 Meccans — a major sign of divine aid.',
    ),
    _Event(
      year: '625 CE',
      age: '3 AH',
      title: 'Battle of Uhud',
      description:
          'A harder battle in which the Prophet ﷺ is wounded and his uncle Hamzah is martyred.',
    ),
    _Event(
      year: '627 CE',
      age: '5 AH',
      title: 'Battle of the Trench',
      description:
          'A confederate siege of Madinah is foiled by the strategy of digging a trench, suggested by Salman al-Farisi رضي الله عنه.',
    ),
    _Event(
      year: '628 CE',
      age: '6 AH',
      title: 'Treaty of Hudaybiyyah',
      description:
          'A ten-year peace treaty with Quraysh that opens the way for massive growth of Islam.',
    ),
    _Event(
      year: '630 CE',
      age: '8 AH',
      title: 'Conquest of Mecca',
      description:
          'Mecca is reconquered peacefully; the Prophet ﷺ pardons his former enemies and the Ka\'bah is purified of idols.',
    ),
    _Event(
      year: '632 CE',
      age: '10 AH',
      title: 'Farewell Pilgrimage',
      description:
          'The Prophet ﷺ performs his only Hajj, delivers the Farewell Sermon, and receives: "This day I have perfected for you your religion."',
    ),
    _Event(
      year: '632 CE',
      age: '63 • 11 AH',
      title: 'Passing of the Prophet ﷺ',
      description:
          'The Prophet Muhammad ﷺ passes away in Madinah, in the home of A\'ishah رضي الله عنها, after completing his mission.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Seerah')),
      body: SafeArea(
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).padding.bottom + 80),
          itemCount: _events.length,
          itemBuilder: (_, i) => _TimelineTile(
            event: _events[i],
            isFirst: i == 0,
            isLast: i == _events.length - 1,
          ),
        ),
      ),
    );
  }
}

class _Event {
  final String year;
  final String age;
  final String title;
  final String description;
  const _Event({
    required this.year,
    required this.age,
    required this.title,
    required this.description,
  });
}

class _TimelineTile extends StatelessWidget {
  final _Event event;
  final bool isFirst;
  final bool isLast;

  const _TimelineTile({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Expanded(
                flex: 0,
                child: Container(
                  width: 2,
                  height: isFirst ? 18 : 0,
                  color: AppColors.gold30,
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.goldLight, width: 2),
                ),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : AppColors.gold30,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: AppColors.cardGradient,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.gold15),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _chip(event.year),
                      const SizedBox(width: 6),
                      _chip(event.age),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(event.title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(event.description,
                      style: const TextStyle(
                          color: AppColors.textSecondary, height: 1.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.gold10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.gold20),
        ),
        child: Text(label,
            style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}
