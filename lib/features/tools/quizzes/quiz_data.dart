class QuizQuestion {
  final String category;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const QuizQuestion({
    required this.category,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

const List<QuizQuestion> kQuizBank = [
  // Qur'an
  QuizQuestion(
    category: 'Qur\'an',
    question: 'How many surahs are in the Qur\'an?',
    options: ['110', '114', '120', '99'],
    correctIndex: 1,
    explanation: 'The Qur\'an has 114 surahs in total.',
  ),
  QuizQuestion(
    category: 'Qur\'an',
    question: 'Which surah is known as "the heart of the Qur\'an"?',
    options: ['Al-Fātiḥah', 'Yā-Sīn', 'Al-Baqarah', 'Al-Kahf'],
    correctIndex: 1,
    explanation:
        'The Prophet ﷺ described Sūrah Yā-Sīn as the heart of the Qur\'an.',
  ),
  QuizQuestion(
    category: 'Qur\'an',
    question:
        'Which is the only surah that does not begin with the Basmalah?',
    options: ['At-Tawbah', 'An-Nās', 'Al-Fātiḥah', 'Al-Ikhlāṣ'],
    correctIndex: 0,
    explanation: 'Sūrah At-Tawbah (Barāʾah) is the only surah that does not begin with Bismillāh.',
  ),
  QuizQuestion(
    category: 'Qur\'an',
    question: 'How many ayahs are in Sūrah Al-Fātiḥah?',
    options: ['5', '6', '7', '8'],
    correctIndex: 2,
    explanation: 'Al-Fātiḥah consists of 7 ayahs.',
  ),
  QuizQuestion(
    category: 'Qur\'an',
    question: 'Which surah is equivalent to a third of the Qur\'an?',
    options: ['Al-Falaq', 'Al-Ikhlāṣ', 'An-Nās', 'Al-Kāfirūn'],
    correctIndex: 1,
    explanation:
        'The Prophet ﷺ said Al-Ikhlāṣ equals a third of the Qur\'an.',
  ),
  QuizQuestion(
    category: 'Qur\'an',
    question: 'How many juzʾ (paras) is the Qur\'an divided into?',
    options: ['28', '30', '32', '40'],
    correctIndex: 1,
    explanation: 'The Qur\'an is divided into 30 equal parts (juzʾ).',
  ),
  QuizQuestion(
    category: 'Qur\'an',
    question: 'Which surah does the Prophet ﷺ recommend reciting every Friday?',
    options: ['Al-Mulk', 'Al-Kahf', 'Yā-Sīn', 'Ar-Raḥmān'],
    correctIndex: 1,
    explanation:
        'Reciting Sūrah Al-Kahf on Friday brings light between the two Fridays.',
  ),

  // Pillars / Fiqh
  QuizQuestion(
    category: 'Pillars',
    question: 'How many pillars of Islam are there?',
    options: ['3', '4', '5', '6'],
    correctIndex: 2,
    explanation:
        'Five: Shahādah, Ṣalāh, Zakāh, Ṣawm, and Ḥajj.',
  ),
  QuizQuestion(
    category: 'Pillars',
    question: 'How many articles of faith (arkān al-īmān) are there?',
    options: ['5', '6', '7', '10'],
    correctIndex: 1,
    explanation:
        'Six: belief in Allah, angels, books, messengers, the Last Day, and divine decree.',
  ),
  QuizQuestion(
    category: 'Pillars',
    question: 'How many rakʿahs is the Fajr prayer (farḍ)?',
    options: ['2', '3', '4', '1'],
    correctIndex: 0,
    explanation: 'Fajr farḍ is 2 rakʿahs, preceded by 2 sunnah.',
  ),
  QuizQuestion(
    category: 'Pillars',
    question: 'What is the minimum niṣāb for zakāh on gold?',
    options: ['50g', '85g', '200g', '300g'],
    correctIndex: 1,
    explanation:
        'The niṣāb is approximately 85 grams of gold (20 mithqāl).',
  ),
  QuizQuestion(
    category: 'Pillars',
    question: 'What is the standard rate of zakāh on wealth?',
    options: ['1%', '2.5%', '5%', '10%'],
    correctIndex: 1,
    explanation: '2.5% of qualifying wealth held for a lunar year.',
  ),

  // Prophets
  QuizQuestion(
    category: 'Prophets',
    question: 'Who is called Khalīlullāh (the friend of Allah)?',
    options: ['Mūsā ﷺ', 'Ibrāhīm ﷺ', 'Nūḥ ﷺ', 'Dāwūd ﷺ'],
    correctIndex: 1,
    explanation:
        'Ibrāhīm ﷺ was taken by Allah as Khalīl — an intimate friend.',
  ),
  QuizQuestion(
    category: 'Prophets',
    question: 'Which prophet could understand the speech of birds and ants?',
    options: ['Yūsuf ﷺ', 'Sulaymān ﷺ', 'Dāwūd ﷺ', 'ʿĪsā ﷺ'],
    correctIndex: 1,
    explanation:
        'Sulaymān ﷺ was given the language of the birds and ants.',
  ),
  QuizQuestion(
    category: 'Prophets',
    question: 'Which prophet was swallowed by a whale?',
    options: ['Yūnus ﷺ', 'Ayyūb ﷺ', 'Idrīs ﷺ', 'Hūd ﷺ'],
    correctIndex: 0,
    explanation:
        'Yūnus ﷺ (Jonah) was saved after praying from the belly of the whale.',
  ),
  QuizQuestion(
    category: 'Prophets',
    question: 'Who is the final Messenger of Allah?',
    options: ['ʿĪsā ﷺ', 'Muḥammad ﷺ', 'Mūsā ﷺ', 'Ādam ﷺ'],
    correctIndex: 1,
    explanation:
        'Muḥammad ﷺ is Khātam al-Nabiyyīn — the seal of the prophets.',
  ),
  QuizQuestion(
    category: 'Prophets',
    question: 'Which prophet built the Kaʿbah with his son Ismāʿīl?',
    options: ['Ādam ﷺ', 'Ibrāhīm ﷺ', 'Nūḥ ﷺ', 'Isḥāq ﷺ'],
    correctIndex: 1,
    explanation:
        'Ibrāhīm ﷺ and Ismāʿīl raised the foundations of the Kaʿbah.',
  ),

  // History / Seerah
  QuizQuestion(
    category: 'Seerah',
    question: 'In which cave did the Prophet ﷺ receive the first revelation?',
    options: ['Ḥirāʾ', 'Thawr', 'Al-Kahf', 'Ṣafā'],
    correctIndex: 0,
    explanation:
        'The first revelation came in the Cave of Ḥirāʾ on Jabal al-Nūr.',
  ),
  QuizQuestion(
    category: 'Seerah',
    question: 'In which year did the Hijrah to Madīnah take place (CE)?',
    options: ['610', '622', '632', '570'],
    correctIndex: 1,
    explanation:
        'The Hijrah occurred in 622 CE; year 1 of the Islamic calendar.',
  ),
  QuizQuestion(
    category: 'Seerah',
    question: 'Who was the first Muslim among men?',
    options: [
      'ʿUmar ibn al-Khaṭṭāb',
      'ʿAlī ibn Abī Ṭālib',
      'Abū Bakr al-Ṣiddīq',
      'ʿUthmān ibn ʿAffān'
    ],
    correctIndex: 2,
    explanation:
        'Abū Bakr al-Ṣiddīq was the first free adult man to accept Islam.',
  ),
  QuizQuestion(
    category: 'Seerah',
    question: 'Who was the Prophet\'s ﷺ first wife?',
    options: ['ʿĀʾishah', 'Ḥafṣah', 'Khadījah', 'Zaynab'],
    correctIndex: 2,
    explanation:
        'Khadījah bint Khuwaylid was the Prophet\'s ﷺ first wife and first female believer.',
  ),
  QuizQuestion(
    category: 'Seerah',
    question: 'In what year did the Battle of Badr take place (AH)?',
    options: ['1', '2', '5', '8'],
    correctIndex: 1,
    explanation:
        'Badr took place in Ramaḍān of the 2nd year after Hijrah.',
  ),

  // General
  QuizQuestion(
    category: 'General',
    question: 'How many names of Allah are traditionally enumerated?',
    options: ['33', '77', '99', '100'],
    correctIndex: 2,
    explanation:
        'The Prophet ﷺ said Allah has 99 names; whoever enumerates them enters Paradise.',
  ),
  QuizQuestion(
    category: 'General',
    question: 'What does "Tawḥīd" mean?',
    options: [
      'Fasting',
      'The oneness of Allah',
      'Charity',
      'Pilgrimage'
    ],
    correctIndex: 1,
    explanation:
        'Tawḥīd is the affirmation of Allah\'s absolute oneness.',
  ),
  QuizQuestion(
    category: 'General',
    question: 'In which month was the Qur\'an first revealed?',
    options: ['Muḥarram', 'Rajab', 'Ramaḍān', 'Shawwāl'],
    correctIndex: 2,
    explanation:
        'The Qur\'an was sent down in the month of Ramaḍān (Al-Baqarah 2:185).',
  ),
  QuizQuestion(
    category: 'General',
    question: 'What is Laylat al-Qadr better than?',
    options: [
      'A month',
      'A year',
      'A thousand months',
      'Ten years'
    ],
    correctIndex: 2,
    explanation:
        'Sūrah Al-Qadr: "Laylat al-Qadr is better than a thousand months."',
  ),
  QuizQuestion(
    category: 'General',
    question:
        'Which direction do Muslims face in ṣalāh?',
    options: ['Jerusalem', 'Makkah (the Kaʿbah)', 'Madīnah', 'Any direction'],
    correctIndex: 1,
    explanation:
        'The qiblah is the Kaʿbah in Masjid al-Ḥarām, Makkah.',
  ),
];
