class TajweedRule {
  final String title;
  final String arabic;
  final String description;
  final List<String> letters;
  final String example;
  final String exampleRef;
  const TajweedRule({
    required this.title,
    required this.arabic,
    required this.description,
    required this.letters,
    required this.example,
    required this.exampleRef,
  });
}

class TajweedGroup {
  final String category;
  final List<TajweedRule> rules;
  const TajweedGroup({required this.category, required this.rules});
}

const List<TajweedGroup> kTajweedGroups = [
  TajweedGroup(
    category: 'Nūn Sākinah & Tanwīn',
    rules: [
      TajweedRule(
        title: 'Iẓhār (Clear pronunciation)',
        arabic: 'إِظْهَار',
        description:
            'When nūn sākinah or tanwīn is followed by one of the six throat letters, pronounce the nūn clearly without merging or concealing.',
        letters: ['ء', 'هـ', 'ع', 'ح', 'غ', 'خ'],
        example: 'مَنْ آمَنَ',
        exampleRef: 'Al-Baqarah 2:62',
      ),
      TajweedRule(
        title: 'Idghām (Merging)',
        arabic: 'إِدْغَام',
        description:
            'Merge the nūn into the next letter. With ي م و ن — with ghunnah (nasal). With ل ر — without ghunnah.',
        letters: ['ي', 'ر', 'م', 'ل', 'و', 'ن'],
        example: 'مِن رَّبِّهِمْ',
        exampleRef: 'Al-Baqarah 2:5',
      ),
      TajweedRule(
        title: 'Iqlāb (Conversion)',
        arabic: 'إِقْلَاب',
        description:
            'When nūn sākinah or tanwīn is followed by bāʾ (ب), convert it into a mīm with ghunnah (about 2 counts).',
        letters: ['ب'],
        example: 'مِنۢ بَعْدِ',
        exampleRef: 'Al-Baqarah 2:27',
      ),
      TajweedRule(
        title: 'Ikhfāʾ (Concealing)',
        arabic: 'إِخْفَاء',
        description:
            'Partially conceal the nūn with ghunnah (about 2 counts) before the remaining 15 letters.',
        letters: [
          'ت',
          'ث',
          'ج',
          'د',
          'ذ',
          'ز',
          'س',
          'ش',
          'ص',
          'ض',
          'ط',
          'ظ',
          'ف',
          'ق',
          'ك'
        ],
        example: 'أَنْتُمْ',
        exampleRef: 'Al-Baqarah 2:22',
      ),
    ],
  ),
  TajweedGroup(
    category: 'Mīm Sākinah',
    rules: [
      TajweedRule(
        title: 'Ikhfāʾ Shafawī',
        arabic: 'إِخْفَاء شَفَوِي',
        description:
            'When mīm sākinah is followed by bāʾ, conceal it with a light ghunnah while keeping the lips closed.',
        letters: ['ب'],
        example: 'تَرْمِيهِم بِحِجَارَةٍ',
        exampleRef: 'Al-Fīl 105:4',
      ),
      TajweedRule(
        title: 'Idghām Shafawī',
        arabic: 'إِدْغَام شَفَوِي',
        description:
            'When mīm sākinah meets another mīm, merge them with ghunnah.',
        letters: ['م'],
        example: 'لَهُم مَّا',
        exampleRef: 'Al-Baqarah 2:25',
      ),
      TajweedRule(
        title: 'Iẓhār Shafawī',
        arabic: 'إِظْهَار شَفَوِي',
        description:
            'With all remaining letters, the mīm is pronounced clearly without ghunnah. Extra care with wāw and fāʾ.',
        letters: ['كل الحروف عدا ب و م'],
        example: 'أَمْ لَمْ',
        exampleRef: 'Al-Baqarah 2:6',
      ),
    ],
  ),
  TajweedGroup(
    category: 'Madd (Elongation)',
    rules: [
      TajweedRule(
        title: 'Madd Ṭabīʿī (Natural)',
        arabic: 'مَدّ طَبِيعِي',
        description:
            'A natural 2-count stretch when a madd letter (ا و ي) is not followed by hamzah or sukūn.',
        letters: ['ا', 'و', 'ي'],
        example: 'قَالَ',
        exampleRef: 'Al-Baqarah 2:30',
      ),
      TajweedRule(
        title: 'Madd Muttaṣil (Connected)',
        arabic: 'مَدّ مُتَّصِل',
        description:
            'Obligatory madd of 4–5 counts when a madd letter is followed by hamzah in the same word.',
        letters: ['ا + ء', 'و + ء', 'ي + ء'],
        example: 'جَآءَ',
        exampleRef: 'An-Naṣr 110:1',
      ),
      TajweedRule(
        title: 'Madd Munfaṣil (Separated)',
        arabic: 'مَدّ مُنْفَصِل',
        description:
            'Permissible madd of 2, 4, or 5 counts when a madd letter ends a word and the next begins with hamzah.',
        letters: ['ا | ء', 'و | ء', 'ي | ء'],
        example: 'يَٰٓأَيُّهَا',
        exampleRef: 'Al-Baqarah 2:21',
      ),
      TajweedRule(
        title: 'Madd Lāzim (Necessary)',
        arabic: 'مَدّ لَازِم',
        description:
            'Necessary madd of 6 counts when a madd letter is followed by a letter with sukūn or shaddah.',
        letters: ['حرف مدّ + سكون لازم'],
        example: 'الٓمٓ',
        exampleRef: 'Al-Baqarah 2:1',
      ),
      TajweedRule(
        title: 'Madd ʿĀriḍ lis-Sukūn',
        arabic: 'مَدّ عَارِض لِلسُّكُون',
        description:
            'Permissible 2, 4, or 6 counts when stopping on a word whose final letter has a temporary sukūn after a madd letter.',
        letters: ['آخر الكلمة عند الوقف'],
        example: 'الْعَالَمِينَ (waqf)',
        exampleRef: 'Al-Fātiḥah 1:2',
      ),
    ],
  ),
  TajweedGroup(
    category: 'Qalqalah (Echoing)',
    rules: [
      TajweedRule(
        title: 'Qalqalah letters',
        arabic: 'قَلْقَلَة',
        description:
            'Echo the pronunciation with a slight bounce when these letters carry sukūn (mid-word = small; end of word at waqf = large).',
        letters: ['ق', 'ط', 'ب', 'ج', 'د'],
        example: 'الْفَلَقِ / أَحَدْ',
        exampleRef: 'Al-Falaq 113:1 / Al-Ikhlāṣ 112:1',
      ),
    ],
  ),
  TajweedGroup(
    category: 'Rāʾ & Lām',
    rules: [
      TajweedRule(
        title: 'Tafkhīm of Rāʾ',
        arabic: 'تَفْخِيم الرَّاء',
        description:
            'Pronounce rāʾ heavy when it has fatḥah or ḍammah, or is sākinah after fatḥah/ḍammah.',
        letters: ['رَ', 'رُ', 'ْر بعد فتح/ضم'],
        example: 'رَبِّ',
        exampleRef: 'Al-Fātiḥah 1:2',
      ),
      TajweedRule(
        title: 'Tarqīq of Rāʾ',
        arabic: 'تَرْقِيق الرَّاء',
        description:
            'Pronounce rāʾ light when it has kasrah, or is sākinah after kasrah (with no high letter following).',
        letters: ['رِ', 'ْر بعد كسر'],
        example: 'رِزْقًا',
        exampleRef: 'Al-Baqarah 2:22',
      ),
      TajweedRule(
        title: 'Lām of Allah',
        arabic: 'لَام الجَلَالَة',
        description:
            'The lām in "Allah" is heavy after fatḥah or ḍammah, and light after kasrah.',
        letters: ['اللَّه'],
        example: 'بِسْمِ اللَّهِ',
        exampleRef: 'Al-Fātiḥah 1:1',
      ),
    ],
  ),
  TajweedGroup(
    category: 'Makhārij (Points of articulation)',
    rules: [
      TajweedRule(
        title: 'Five main regions',
        arabic: 'مَخَارِج الحُرُوف',
        description:
            'Every Arabic letter has a specific articulation point: 1) Jawf (empty space — madd letters), 2) Ḥalq (throat), 3) Lisān (tongue), 4) Shafatān (lips), 5) Khayshūm (nasal passage — ghunnah).',
        letters: ['جَوْف', 'حَلْق', 'لِسَان', 'شَفَتَان', 'خَيْشُوم'],
        example: '—',
        exampleRef: 'Foundational',
      ),
    ],
  ),
];
