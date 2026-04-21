class ProphetStory {
  final String title;
  final String subtitle;
  final List<String> surahs;
  final String body;

  const ProphetStory({
    required this.title,
    required this.subtitle,
    required this.surahs,
    required this.body,
  });
}

const List<ProphetStory> kProphetStories = [
  ProphetStory(
    title: 'Adam ﷺ',
    subtitle: 'The first human',
    surahs: ['Al-Baqarah', 'Al-Aʿrāf', 'Ṭā-Hā'],
    body:
        'Allah created Adam ﷺ from clay, breathed into him His spirit, taught him the names of all things, and commanded the angels to prostrate. Iblīs refused out of arrogance and was cast out. Adam and his wife Ḥawwāʾ were placed in Paradise and warned against a single tree. Iblīs deceived them; they ate from it, realized their mistake, and turned to Allah in sincere repentance. Allah accepted their repentance and sent them to earth with guidance for their descendants.',
  ),
  ProphetStory(
    title: 'Nūḥ ﷺ',
    subtitle: 'The great flood',
    surahs: ['Hūd', 'Nūḥ', 'Al-Qamar'],
    body:
        'Nūḥ ﷺ called his people to worship Allah alone for 950 years. Only a few believed. Commanded by Allah, he built the Ark far from water while his people mocked him. When the flood came, the believers and pairs of every creature were saved. His own son rejected faith and was drowned. The story teaches patience in calling to truth and that true salvation lies in faith, not lineage.',
  ),
  ProphetStory(
    title: 'Ibrāhīm ﷺ',
    subtitle: 'The friend of Allah',
    surahs: ['Al-Anʿām', 'Al-Anbiyāʾ', 'Aṣ-Ṣāffāt'],
    body:
        'Ibrāhīm ﷺ reasoned his way to tawḥīd, rejecting the idols of his people. He broke their idols and was cast into a fire that Allah made cool and peaceful. He left his wife Hājar and infant Ismāʿīl in the valley of Makkah by Allah’s command; there Zamzam sprang forth. Later, he saw in a dream that he was sacrificing his son — both submitted, and Allah ransomed Ismāʿīl with a great ram. Together they raised the foundations of the Kaʿbah.',
  ),
  ProphetStory(
    title: 'Yūsuf ﷺ',
    subtitle: 'Patience and forgiveness',
    surahs: ['Yūsuf'],
    body:
        'Yūsuf ﷺ saw a dream of eleven stars, the sun, and the moon prostrating to him. His brothers envied him and threw him into a well. He was sold as a slave in Egypt, resisted the seduction of the governor’s wife, and was imprisoned unjustly. He interpreted the king’s dream of seven fat and seven lean cows, was raised to authority, and forgave his brothers when they came seeking food. He said: “No blame upon you today — may Allah forgive you.”',
  ),
  ProphetStory(
    title: 'Mūsā ﷺ',
    subtitle: 'Against Pharaoh',
    surahs: ['Ṭā-Hā', 'Al-Qaṣaṣ', 'Al-Aʿrāf'],
    body:
        'Born under Pharaoh’s decree to kill Israelite sons, Mūsā ﷺ was placed in a basket by his mother and floated down the Nile. He was raised in Pharaoh’s own palace. After fleeing to Madyan, he met Allah at the sacred valley of Ṭuwā and received prophethood. With his brother Hārūn ﷺ, he challenged Pharaoh. The sea was split for the Children of Israel, and Pharaoh and his army were drowned. Mūsā also spoke with Allah on Mount Ṭūr and received the Tawrāh.',
  ),
  ProphetStory(
    title: 'Dāwūd & Sulaymān ﷺ',
    subtitle: 'Kings and prophets',
    surahs: ['An-Naml', 'Ṣād', 'Al-Anbiyāʾ'],
    body:
        'Dāwūd ﷺ slew the tyrant Jālūt (Goliath) with a single stone, was given the Zabūr, and iron was softened in his hands. His son Sulaymān ﷺ was granted a kingdom unmatched: the jinn, the wind, and the language of birds and ants obeyed him. The Queen of Sabaʾ (Sheba) came to him and embraced faith. His throne reminded him that all authority belongs to Allah alone.',
  ),
  ProphetStory(
    title: 'Maryam & ʿĪsā ﷺ',
    subtitle: 'A sign to the worlds',
    surahs: ['Āl ʿImrān', 'Maryam'],
    body:
        'Maryam — the only woman named in the Qur’an — was a chaste servant of Allah raised by Zakariyyā ﷺ in the sanctuary. The angel Jibrīl announced to her a word from Allah: a son named ʿĪsā. She gave birth alone by a date palm, and the infant spoke from the cradle defending her honor. ʿĪsā ﷺ performed miracles by Allah’s leave, called to pure monotheism, and was raised up to Allah; he was not crucified, as the Qur’an teaches.',
  ),
  ProphetStory(
    title: 'Yūnus ﷺ',
    subtitle: 'The prayer in the whale',
    surahs: ['Yūnus', 'Aṣ-Ṣāffāt', 'Al-Anbiyāʾ'],
    body:
        'Yūnus ﷺ left his people before Allah’s permission. A great fish swallowed him in the depths of the sea. There, in three darknesses, he called out: "Lā ilāha illā anta, subḥānaka, innī kuntu min aẓ-ẓālimīn" — "There is no god but You, glory be to You; I was among the wrongdoers." Allah saved him and restored him to his people, who all believed. No supplication is made with these words except that Allah answers it.',
  ),
  ProphetStory(
    title: 'Aṣḥāb al-Kahf',
    subtitle: 'The people of the cave',
    surahs: ['Al-Kahf'],
    body:
        'A group of young believers fled a tyrannical city rather than abandon their faith. They took refuge in a cave with their dog, and Allah caused them to sleep for 309 years. When they awoke, they sent one to buy food with an outdated coin — and discovered that a believing generation now ruled. They are a sign that Allah protects those who hold firm to tawḥīd in times of trial.',
  ),
  ProphetStory(
    title: 'Muḥammad ﷺ',
    subtitle: 'The final messenger',
    surahs: ['Al-ʿAlaq', 'Al-Muddaththir', 'Al-Fatḥ'],
    body:
        'In the Cave of Ḥirāʾ, Jibrīl brought the first revelation: "Iqraʾ — Read in the name of your Lord who created." For thirteen years in Makkah, the Prophet ﷺ called to tawḥīd amid persecution. He migrated to Madīnah, built the first community of faith, and returned victorious to Makkah, entering with his head lowered in humility. He delivered his farewell sermon on ʿArafah, proclaimed the perfection of the religion, and passed away having conveyed the full trust of revelation.',
  ),
];
