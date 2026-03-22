/// Resolved surah + optional ayah for a named-verse alias.
class NamedVerseRef {
  const NamedVerseRef({required this.surah, this.ayah});

  final int surah;
  final int? ayah;
}

/// Canonical map of lowercase named-verse alias strings → [NamedVerseRef].
///
/// Used by both [IntentParser] and [AsrNormalizationPipeline] so that the
/// same aliases are recognised regardless of the entry point (typed text vs
/// ASR voice input).
const Map<String, NamedVerseRef> namedVerseMap = <String, NamedVerseRef>{
  // ── Ayatul Kursi ( 2:255 ) ─────────────────────────────────────────────────
  'ayatul kursi':            NamedVerseRef(surah: 2, ayah: 255),
  'ayat kursi':              NamedVerseRef(surah: 2, ayah: 255),
  'ayat ul kursi':           NamedVerseRef(surah: 2, ayah: 255),
  'ayatul kursiyy':          NamedVerseRef(surah: 2, ayah: 255),
  'ayatul kursy':            NamedVerseRef(surah: 2, ayah: 255),
  'ayat kursy':              NamedVerseRef(surah: 2, ayah: 255),
  'throne verse':            NamedVerseRef(surah: 2, ayah: 255),
  'verse of the throne':     NamedVerseRef(surah: 2, ayah: 255),
  'kursi':                   NamedVerseRef(surah: 2, ayah: 255),

  // ── Al-Fatiha ( 1 ) ────────────────────────────────────────────────────────
  'fatiha':                  NamedVerseRef(surah: 1),
  'al fatiha':               NamedVerseRef(surah: 1),
  'al-fatiha':               NamedVerseRef(surah: 1),
  'surah fatiha':            NamedVerseRef(surah: 1),
  'opening verse':           NamedVerseRef(surah: 1, ayah: 1),

  // ── Ayat An-Noor ( 24:35 ) ─────────────────────────────────────────────────
  'ayat noor':               NamedVerseRef(surah: 24, ayah: 35),
  'ayat al noor':            NamedVerseRef(surah: 24, ayah: 35),
  'verse of light':          NamedVerseRef(surah: 24, ayah: 35),
  'light verse':             NamedVerseRef(surah: 24, ayah: 35),

  // ── Last two verses of Al-Baqarah ( 2:285 ) ───────────────────────────────
  'last two verses of baqarah': NamedVerseRef(surah: 2, ayah: 285),
  'amana rasulu':            NamedVerseRef(surah: 2, ayah: 285),

  // ── Other well-known verses ────────────────────────────────────────────────
  'verse of hijab':          NamedVerseRef(surah: 33, ayah: 59),
  'verse of sword':          NamedVerseRef(surah: 9, ayah: 5),
  'ayat saif':               NamedVerseRef(surah: 9, ayah: 5),
};
