class AyahModel {
  final int suraId;

  final int ayaId;

  final String suraName;

  final String text;

  const AyahModel({
    required this.suraId,
    required this.ayaId,
    required this.suraName,
    required this.text,
  });

  factory AyahModel.fromMap(Map<String, dynamic> map) {
    final suraId =
        map['sura_id'] ?? map['sura'] ?? map['surah'] ?? map['chapter'] ?? 1;

    final ayaId =
        map['aya_id'] ?? map['aya'] ?? map['ayah'] ?? map['verse'] ?? 1;

    final suraName = map['sura_name'] ??
        map['sura_name_ar'] ??
        map['surah_name'] ??
        map['name'] ??
        'Unknown';

    final text = map['text'] ??
        map['content'] ??
        map['aya_text'] ??
        map['ayah_text'] ??
        '';

    return AyahModel(
      suraId: int.tryParse(suraId.toString()) ?? 1,
      ayaId: int.tryParse(ayaId.toString()) ?? 1,
      suraName: suraName.toString(),
      text: text.toString(),
    );
  }

  @override
  String toString() {
    return 'AyahModel(sura: $suraName [$suraId], aya: $ayaId, text: $text)';
  }
}
