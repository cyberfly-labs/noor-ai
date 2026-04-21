class Dua {
  final String category;
  final String title;
  final String arabic;
  final String transliteration;
  final String translation;
  final String? reference;
  const Dua({
    required this.category,
    required this.title,
    required this.arabic,
    required this.transliteration,
    required this.translation,
    this.reference,
  });
}

const List<Dua> duas = [
  Dua(
    category: 'Daily',
    title: 'Upon waking up',
    arabic:
        'الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ',
    transliteration:
        'Alhamdu lillahil-ladhi ahyana ba\'da ma amatana wa ilayhin-nushur',
    translation:
        'All praise is for Allah, who gave us life after having taken it from us, and unto Him is the resurrection.',
    reference: 'Bukhari',
  ),
  Dua(
    category: 'Daily',
    title: 'Before sleeping',
    arabic: 'بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا',
    transliteration: 'Bismika Allahumma amutu wa ahya',
    translation: 'In Your name, O Allah, I die and I live.',
    reference: 'Bukhari',
  ),
  Dua(
    category: 'Daily',
    title: 'Before eating',
    arabic: 'بِسْمِ اللَّهِ',
    transliteration: 'Bismillah',
    translation: 'In the name of Allah.',
    reference: 'Abu Dawud',
  ),
  Dua(
    category: 'Daily',
    title: 'After eating',
    arabic:
        'الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنِي هَذَا وَرَزَقَنِيهِ مِنْ غَيْرِ حَوْلٍ مِنِّي وَلَا قُوَّةٍ',
    transliteration:
        'Alhamdu lillahil-ladhi at\'amani hadha wa razaqanihi min ghayri hawlin minni wa la quwwah',
    translation:
        'All praise is for Allah who fed me this and provided it for me, without any might or power from myself.',
    reference: 'Abu Dawud',
  ),
  Dua(
    category: 'Daily',
    title: 'Entering the home',
    arabic:
        'بِسْمِ اللَّهِ وَلَجْنَا وَبِسْمِ اللَّهِ خَرَجْنَا وَعَلَى اللَّهِ رَبِّنَا تَوَكَّلْنَا',
    transliteration:
        'Bismillahi walajna, wa bismillahi kharajna, wa \'ala Allahi rabbina tawakkalna',
    translation:
        'In the name of Allah we enter, in the name of Allah we leave, and upon Allah our Lord we place our trust.',
    reference: 'Abu Dawud',
  ),
  Dua(
    category: 'Daily',
    title: 'Leaving the home',
    arabic:
        'بِسْمِ اللَّهِ، تَوَكَّلْتُ عَلَى اللَّهِ، وَلَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ',
    transliteration:
        'Bismillah, tawakkaltu \'ala Allah, wa la hawla wa la quwwata illa billah',
    translation:
        'In the name of Allah, I trust in Allah; there is no might or power except with Allah.',
    reference: 'Abu Dawud',
  ),
  Dua(
    category: 'Travel',
    title: 'Travel dua',
    arabic:
        'سُبْحَانَ الَّذِي سَخَّرَ لَنَا هَذَا وَمَا كُنَّا لَهُ مُقْرِنِينَ وَإِنَّا إِلَى رَبِّنَا لَمُنْقَلِبُونَ',
    transliteration:
        'Subhanal-ladhi sakhkhara lana hadha wa ma kunna lahu muqrinin, wa inna ila rabbina lamunqalibun',
    translation:
        'Glory to Him who has placed this at our service, for we would not have had the strength, and to our Lord we will surely return.',
    reference: 'Quran 43:13-14',
  ),
  Dua(
    category: 'Anxiety',
    title: 'For anxiety and sorrow',
    arabic:
        'اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْهَمِّ وَالْحَزَنِ، وَالْعَجْزِ وَالْكَسَلِ، وَالْبُخْلِ وَالْجُبْنِ، وَضَلَعِ الدَّيْنِ، وَغَلَبَةِ الرِّجَالِ',
    transliteration:
        'Allahumma inni a\'udhu bika minal-hammi wal-hazan, wal-\'ajzi wal-kasal, wal-bukhli wal-jubn, wa dala\'id-dayn, wa ghalabatir-rijal',
    translation:
        'O Allah, I seek refuge in You from anxiety and sorrow, weakness and laziness, miserliness and cowardice, the burden of debts, and from being overpowered by men.',
    reference: 'Bukhari',
  ),
  Dua(
    category: 'Protection',
    title: 'Morning & evening refuge',
    arabic:
        'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ',
    transliteration:
        'A\'udhu bi-kalimatil-lahit-tammati min sharri ma khalaq',
    translation:
        'I seek refuge in the perfect words of Allah from the evil of what He has created.',
    reference: 'Muslim',
  ),
  Dua(
    category: 'Forgiveness',
    title: 'Sayyid al-Istighfar',
    arabic:
        'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ',
    transliteration:
        'Allahumma anta Rabbi la ilaha illa anta, khalaqtani wa ana \'abduka…',
    translation:
        'O Allah, You are my Lord, none has the right to be worshipped except You. You created me and I am Your servant, and I abide to Your covenant and promise as best I can… forgive me, for none can forgive sins except You.',
    reference: 'Bukhari',
  ),
  Dua(
    category: 'Rizq',
    title: 'For provision',
    arabic:
        'اللَّهُمَّ اكْفِنِي بِحَلَالِكَ عَنْ حَرَامِكَ، وَأَغْنِنِي بِفَضْلِكَ عَمَّنْ سِوَاكَ',
    transliteration:
        'Allahumma ikfini bi-halalika \'an haramika, wa aghnini bi-fadlika \'amman siwak',
    translation:
        'O Allah, suffice me with what You have made lawful from what You have forbidden, and enrich me with Your bounty from needing anyone besides You.',
    reference: 'Tirmidhi',
  ),
  Dua(
    category: 'Guidance',
    title: 'For knowledge',
    arabic: 'رَبِّ زِدْنِي عِلْمًا',
    transliteration: 'Rabbi zidni \'ilma',
    translation: 'My Lord, increase me in knowledge.',
    reference: 'Quran 20:114',
  ),
  Dua(
    category: 'Guidance',
    title: 'Expansion of the heart',
    arabic:
        'رَبِّ اشْرَحْ لِي صَدْرِي وَيَسِّرْ لِي أَمْرِي وَاحْلُلْ عُقْدَةً مِنْ لِسَانِي يَفْقَهُوا قَوْلِي',
    transliteration:
        'Rabbi-shrah li sadri, wa yassir li amri, wahlul \'uqdatam-min lisani yafqahu qawli',
    translation:
        'My Lord, expand for me my chest, and ease for me my task, and untie the knot from my tongue that they may understand my speech.',
    reference: 'Quran 20:25-28',
  ),
  Dua(
    category: 'Parents',
    title: 'For parents',
    arabic:
        'رَبِّ ارْحَمْهُمَا كَمَا رَبَّيَانِي صَغِيرًا',
    transliteration: 'Rabbi-rhamhuma kama rabbayani saghira',
    translation:
        'My Lord, have mercy upon them as they brought me up when I was small.',
    reference: 'Quran 17:24',
  ),
];
