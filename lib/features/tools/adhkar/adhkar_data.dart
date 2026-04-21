class Adhkar {
  final String title;
  final String arabic;
  final String transliteration;
  final String translation;
  final int count;
  final String? reference;
  const Adhkar({
    required this.title,
    required this.arabic,
    required this.transliteration,
    required this.translation,
    required this.count,
    this.reference,
  });
}

const List<Adhkar> morningAdhkar = [
  Adhkar(
    title: 'Ayat al-Kursi',
    arabic:
        'اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ…',
    transliteration: 'Allahu la ilaha illa huwa al-hayyu al-qayyum…',
    translation:
        'Allah! There is no deity except Him, the Ever-Living, the Sustainer of all existence…',
    count: 1,
    reference: 'Quran 2:255',
  ),
  Adhkar(
    title: 'Three Quls',
    arabic:
        'قُلْ هُوَ اللَّهُ أَحَدٌ • قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ • قُلْ أَعُوذُ بِرَبِّ النَّاسِ',
    transliteration: 'Qul huwa Allahu ahad • Qul a\'udhu bi-Rabbil-falaq • Qul a\'udhu bi-Rabbin-nas',
    translation: 'Recite Surahs Al-Ikhlas, Al-Falaq, and An-Nas.',
    count: 3,
    reference: 'Abu Dawud, Tirmidhi',
  ),
  Adhkar(
    title: 'Master of seeking forgiveness',
    arabic:
        'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ خَلَقْتَنِي وَأَنَا عَبْدُكَ…',
    transliteration:
        'Allahumma anta rabbi la ilaha illa anta khalaqtani wa ana \'abduka…',
    translation:
        'O Allah, You are my Lord, none has the right to be worshipped except You… forgive me, for none forgives sins but You.',
    count: 1,
    reference: 'Bukhari',
  ),
  Adhkar(
    title: 'Morning greeting',
    arabic:
        'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ…',
    transliteration:
        'Asbahna wa asbahal-mulku lillah, walhamdu lillah…',
    translation:
        'We have reached the morning and the kingdom belongs to Allah; all praise is for Allah.',
    count: 1,
    reference: 'Muslim',
  ),
  Adhkar(
    title: 'Pleased with Allah',
    arabic:
        'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ ﷺ نَبِيًّا',
    transliteration:
        'Raditu billahi rabba, wa bil-islami dina, wa bi-Muhammadin nabiyya',
    translation:
        'I am pleased with Allah as my Lord, Islam as my religion, and Muhammad ﷺ as my prophet.',
    count: 3,
    reference: 'Abu Dawud, Tirmidhi',
  ),
  Adhkar(
    title: 'Refuge in perfect words',
    arabic:
        'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ',
    transliteration:
        'A\'udhu bi-kalimatillahit-tammati min sharri ma khalaq',
    translation:
        'I seek refuge in the perfect words of Allah from the evil of what He has created.',
    count: 3,
    reference: 'Muslim',
  ),
  Adhkar(
    title: 'SubhanAllah wa bihamdihi',
    arabic: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ',
    transliteration: 'Subhan-Allahi wa bihamdihi',
    translation: 'Glory is to Allah and praise is to Him.',
    count: 100,
    reference: 'Muslim',
  ),
  Adhkar(
    title: 'La ilaha illa Allah',
    arabic:
        'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ',
    transliteration:
        'La ilaha illa Allah, wahdahu la sharika lah, lahul-mulku wa lahul-hamdu wa huwa \'ala kulli shay\'in qadir',
    translation:
        'There is no deity except Allah, alone without partner; to Him belongs the dominion and praise, and He is over all things capable.',
    count: 10,
    reference: 'Bukhari, Muslim',
  ),
  Adhkar(
    title: 'Hasbiya Allah',
    arabic:
        'حَسْبِيَ اللَّهُ لَا إِلَهَ إِلَّا هُوَ عَلَيْهِ تَوَكَّلْتُ وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ',
    transliteration:
        'Hasbiyallahu la ilaha illa hu, \'alayhi tawakkaltu wa huwa rabbul \'arshil-\'azim',
    translation:
        'Allah is sufficient for me; none has the right to be worshipped except Him. Upon Him I rely and He is Lord of the Magnificent Throne.',
    count: 7,
    reference: 'Abu Dawud',
  ),
];

const List<Adhkar> eveningAdhkar = [
  Adhkar(
    title: 'Ayat al-Kursi',
    arabic:
        'اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ…',
    transliteration: 'Allahu la ilaha illa huwa al-hayyu al-qayyum…',
    translation:
        'Allah! There is no deity except Him, the Ever-Living, the Sustainer of all existence…',
    count: 1,
    reference: 'Quran 2:255',
  ),
  Adhkar(
    title: 'Three Quls',
    arabic:
        'قُلْ هُوَ اللَّهُ أَحَدٌ • قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ • قُلْ أَعُوذُ بِرَبِّ النَّاسِ',
    transliteration: 'Qul huwa Allahu ahad • Qul a\'udhu bi-Rabbil-falaq • Qul a\'udhu bi-Rabbin-nas',
    translation: 'Recite Surahs Al-Ikhlas, Al-Falaq, and An-Nas.',
    count: 3,
    reference: 'Abu Dawud, Tirmidhi',
  ),
  Adhkar(
    title: 'Evening greeting',
    arabic:
        'أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ…',
    transliteration:
        'Amsayna wa amsal-mulku lillah, walhamdu lillah…',
    translation:
        'We have reached the evening and the kingdom belongs to Allah; all praise is for Allah.',
    count: 1,
    reference: 'Muslim',
  ),
  Adhkar(
    title: 'Refuge in perfect words (evening)',
    arabic:
        'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ',
    transliteration:
        'A\'udhu bi-kalimatillahit-tammati min sharri ma khalaq',
    translation:
        'I seek refuge in the perfect words of Allah from the evil of what He has created.',
    count: 3,
    reference: 'Muslim',
  ),
  Adhkar(
    title: 'SubhanAllah wa bihamdihi',
    arabic: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ',
    transliteration: 'Subhan-Allahi wa bihamdihi',
    translation: 'Glory is to Allah and praise is to Him.',
    count: 100,
    reference: 'Muslim',
  ),
  Adhkar(
    title: 'Astaghfirullah',
    arabic: 'أَسْتَغْفِرُ اللَّهَ وَأَتُوبُ إِلَيْهِ',
    transliteration: 'Astaghfirullaha wa atubu ilayh',
    translation: 'I seek forgiveness from Allah and repent to Him.',
    count: 100,
    reference: 'Bukhari',
  ),
];
