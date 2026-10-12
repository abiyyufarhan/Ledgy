/// Stable metadata codes shared by all devices; labels are presentation copy.
enum SaverProfile {
  conservative(
    'conservative',
    'Konservatif',
    'Konservatif / Pasif',
    'Mengutamakan stabilitas dan rasa aman.',
  ),
  moderate(
    'moderate',
    'Moderat',
    'Moderat / Terencana',
    'Menyeimbangkan kebutuhan saat ini dan rencana masa depan.',
  ),
  aggressive(
    'aggressive',
    'Agresif',
    'Agresif / Frugal',
    'Menabung dengan disiplin untuk mengejar target.',
  ),
  opportunistic(
    'opportunistic',
    'Oportunistik',
    'Oportunistik / Situasional',
    'Menabung sesuai situasi dan kesempatan.',
  ),
  impulsive(
    'impulsive',
    'Impulsif',
    'Penabung Impulsif',
    'Menabung secara spontan ketika ada dorongan.',
  );

  const SaverProfile(this.code, this.shortLabel, this.label, this.description);
  final String code;
  final String shortLabel;
  final String label;
  final String description;

  static SaverProfile? fromCode(Object? code) {
    for (final profile in values) {
      if (profile.code == code) return profile;
    }
    return null;
  }
}
