class Star {
  /// Right ascension in degrees (0..360)
  final double raDeg;

  /// Declination in degrees (-90..+90)
  final double decDeg;

  /// Apparent magnitude (optional)
  final double? mag;

  const Star({
    required this.raDeg,
    required this.decDeg,
    this.mag,
  });

  factory Star.fromJson(Map<String, dynamic> j) => Star(
        raDeg: (j['ra_deg'] as num).toDouble(),
        decDeg: (j['dec_deg'] as num).toDouble(),
        mag: (j['mag'] == null) ? null : (j['mag'] as num).toDouble(),
      );
}

class ConstellationName {
  final String english;
  final String nativeName;
  final String byname;

  const ConstellationName({
    required this.english,
    required this.nativeName,
    required this.byname,
  });

  factory ConstellationName.fromJson(Map<String, dynamic> j) =>
      ConstellationName(
        english: (j['english'] ?? '').toString(),
        nativeName: (j['native'] ?? '').toString(),
        byname: (j['byname'] ?? '').toString(),
      );

  /// POC: 표시 우선순위 (native -> english -> byname)
  String displayName() {
    final n = nativeName.trim();
    if (n.isNotEmpty) return n;

    final e = english.trim();
    if (e.isNotEmpty) return e;

    final b = byname.trim();
    if (b.isNotEmpty) return b;

    return '';
  }
}

class CatalogData {
  /// "Ori" -> [ [hip, hip, ...], [hip, hip, ...], ... ]
  final Map<String, List<List<int>>> linesByCode;

  /// "Ori" -> name info
  final Map<String, ConstellationName> namesByCode;

  /// hip -> Star(ra/dec/mag)
  final Map<int, Star> starsByHip;

  const CatalogData({
    required this.linesByCode,
    required this.namesByCode,
    required this.starsByHip,
  });
}
