import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'catalog_models.dart';

class CatalogLoader {
  static CatalogData? _cache;

  static Future<CatalogData> loadOnce() async {
    if (_cache != null) return _cache!;

    final linesStr =
        await rootBundle.loadString('assets/data/constellation_lines.json');
    final namesStr =
        await rootBundle.loadString('assets/data/constellation_names.json');
    final starsStr = await rootBundle.loadString('assets/data/stars_min.json');

    final Map<String, dynamic> rawLines = jsonDecode(linesStr);
    final Map<String, dynamic> rawNames = jsonDecode(namesStr);
    final Map<String, dynamic> rawStars = jsonDecode(starsStr);

    final Map<String, List<List<int>>> linesByCode = {};
    rawLines.forEach((code, v) {
      final polylines = (v as List)
          .map((poly) => (poly as List).map((e) => (e as num).toInt()).toList())
          .toList();
      linesByCode[code] = polylines;
    });

    final Map<String, ConstellationName> namesByCode = {};
    rawNames.forEach((code, v) {
      namesByCode[code] = ConstellationName.fromJson(v as Map<String, dynamic>);
    });

    final Map<int, Star> starsByHip = {};
    rawStars.forEach((hipStr, v) {
      final hip = int.parse(hipStr);
      starsByHip[hip] = Star.fromJson(v as Map<String, dynamic>);
    });

    final data = CatalogData(
      linesByCode: linesByCode,
      namesByCode: namesByCode,
      starsByHip: starsByHip,
    );

    // 간단 검증 로그 (POC)
    debugPrint(
      '[CatalogLoader] lines=${data.linesByCode.length} '
      'names=${data.namesByCode.length} '
      'stars=${data.starsByHip.length}',
    );

    // 이름/라인 코드 불일치가 있는지 빠르게 확인
    final missingNames = data.linesByCode.keys
        .where((k) => !data.namesByCode.containsKey(k))
        .take(5)
        .toList();
    if (missingNames.isNotEmpty) {
      debugPrint('[CatalogLoader] ⚠ missing names for: $missingNames');
    }

    _cache = data;
    return data;
  }

  static void clearCacheForDebug() {
    if (kDebugMode) _cache = null;
  }
}
