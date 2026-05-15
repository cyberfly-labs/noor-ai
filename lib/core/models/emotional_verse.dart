class EmotionalVerse {
  final String verseKey;
  final String category;
  final String emotion;
  final String translationText;
  final String? arabicText;

  const EmotionalVerse({
    required this.verseKey,
    required this.category,
    required this.emotion,
    required this.translationText,
    this.arabicText,
  });
}

/// Pre-defined emotional verses for seeding the vector store
const kEmotionalVerses = <EmotionalVerse>[
  EmotionalVerse(
    verseKey: '2:286',
    category: 'comfort_relief',
    emotion: 'hardship relief anxiety worry stress overwhelmed burden resilience',
    translationText: 'Allah does not burden a soul beyond that it can bear.',
  ),
  EmotionalVerse(
    verseKey: '94:5',
    category: 'comfort_relief',
    emotion: 'hardship relief sadness difficulty hope ease struggle',
    translationText: 'For indeed, with hardship will be ease.',
  ),
  EmotionalVerse(
    verseKey: '94:6',
    category: 'comfort_relief',
    emotion: 'hardship relief sadness difficulty hope ease struggle',
    translationText: 'Indeed, with hardship will be ease.',
  ),
  EmotionalVerse(
    verseKey: '9:51',
    category: 'comfort_relief',
    emotion: 'hardship decree trust acceptance trial relief surrender',
    translationText: 'Nothing will happen to us except what Allah has decreed for us.',
  ),
  EmotionalVerse(
    verseKey: '94:7-8',
    category: 'comfort_relief',
    emotion: 'hardship worship renewal longing devotion recovery',
    translationText: 'So when you have finished your duties, then stand up for worship. And to your Lord direct your longing.',
  ),
  EmotionalVerse(
    verseKey: '13:28',
    category: 'calm_peace',
    emotion: 'anxiety calm peace heart rest remembrance worry stress',
    translationText: 'Verily, in the remembrance of Allah do hearts find rest.',
  ),
  EmotionalVerse(
    verseKey: '89:27-30',
    category: 'calm_peace',
    emotion: 'peace calm tranquil soul contentment return serenity',
    translationText: 'O tranquil soul, return to your Lord, well-pleased and pleasing.',
  ),
  EmotionalVerse(
    verseKey: '2:152',
    category: 'calm_peace',
    emotion: 'peace remembrance closeness calm heart gratitude',
    translationText: 'So remember Me; I will remember you.',
  ),
  EmotionalVerse(
    verseKey: '39:53',
    category: 'hope_trust',
    emotion: 'hope trust mercy despair guilt regret sin forgiveness',
    translationText: 'O My servants who have transgressed against themselves, do not despair of the mercy of Allah. Indeed, Allah forgives all sins.',
  ),
  EmotionalVerse(
    verseKey: '65:3',
    category: 'hope_trust',
    emotion: 'hope trust reliance uncertainty tawakkul relief provision',
    translationText: 'And whoever relies upon Allah, then He is sufficient for him.',
  ),
  EmotionalVerse(
    verseKey: '12:87',
    category: 'hope_trust',
    emotion: 'hope despair relief hopelessness trust',
    translationText: 'Indeed, no one despairs of relief from Allah except the disbelieving people.',
  ),
  EmotionalVerse(
    verseKey: '7:156',
    category: 'mercy_forgiveness',
    emotion: 'mercy forgiveness compassion hope healing',
    translationText: 'My mercy encompasses all things.',
  ),
  EmotionalVerse(
    verseKey: '4:110',
    category: 'mercy_forgiveness',
    emotion: 'guilt regret forgiveness repentance mercy sin',
    translationText: 'Whoever does a wrong or wrongs himself but then seeks forgiveness of Allah will find Allah Forgiving and Merciful.',
  ),
  EmotionalVerse(
    verseKey: '6:54',
    category: 'mercy_forgiveness',
    emotion: 'mercy compassion hope repentance',
    translationText: 'Your Lord has decreed upon Himself mercy.',
  ),
  EmotionalVerse(
    verseKey: '14:7',
    category: 'gratitude_blessings',
    emotion: 'gratitude thankful blessings increase favor abundance',
    translationText: 'If you are grateful, I will surely increase you.',
  ),
  EmotionalVerse(
    verseKey: '16:18',
    category: 'gratitude_blessings',
    emotion: 'gratitude blessings favors abundance reflection',
    translationText: 'If you tried to count Allah’s favors, you could never enumerate them.',
  ),
  EmotionalVerse(
    verseKey: '2:172',
    category: 'gratitude_blessings',
    emotion: 'gratitude provision blessing thankfulness',
    translationText: 'Eat from the good things We have provided for you and be grateful to Allah.',
  ),
  EmotionalVerse(
    verseKey: '2:153',
    category: 'patience_strength',
    emotion: 'patience strength endurance struggle prayer resilience',
    translationText: 'Indeed, Allah is with the patient.',
  ),
  EmotionalVerse(
    verseKey: '3:139',
    category: 'patience_strength',
    emotion: 'patience strength sadness courage hope grief',
    translationText: 'Do not lose hope nor be sad.',
  ),
  EmotionalVerse(
    verseKey: '29:69',
    category: 'patience_strength',
    emotion: 'patience striving strength guidance perseverance',
    translationText: 'Those who strive for Us, We will surely guide them to Our ways.',
  ),
  EmotionalVerse(
    verseKey: '93:3',
    category: 'hope_trust',
    emotion: 'abandoned forsaken alone lonely reassurance',
    translationText: 'Your Lord has not taken leave of you, nor has He detested you.',
  ),
  EmotionalVerse(
    verseKey: '9:40',
    category: 'calm_peace',
    emotion: 'fear lonely alone calm reassurance',
    translationText: 'Do not grieve; indeed Allah is with us.',
  ),
  EmotionalVerse(
    verseKey: '3:173',
    category: 'hope_trust',
    emotion: 'fear trust safety reliance protection',
    translationText: 'Sufficient for us is Allah, and He is the best Disposer of affairs.',
  ),
];
