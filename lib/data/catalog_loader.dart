import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'catalog_models.dart';

class CatalogLoader {
  static CatalogData? _cache;

  static Future<CatalogData> loadOnce() async {
    if (_cache != null) return _cache!;

    try {
      // 1. 에셋 파일 로드
      final linesStr =
          await rootBundle.loadString('assets/data/constellation_lines.json');
      final namesStr =
          await rootBundle.loadString('assets/data/constellation_names.json');
      final starsStr =
          await rootBundle.loadString('assets/data/stars_min.json');

      final Map<String, dynamic> rawLines = jsonDecode(linesStr);
      final Map<String, dynamic> rawNames = jsonDecode(namesStr);
      final Map<String, dynamic> rawStars = jsonDecode(starsStr);

      // 2. 별자리 선 데이터 파싱 (안전장치 추가!)
      final Map<String, List<List<int>>> linesByCode = {};

      rawLines.forEach((key, value) {
        final String upperKey = key.toUpperCase(); // "Ori" -> "ORI"

        final List<dynamic> polyList = value as List;
        final List<List<int>> polylines = [];

        for (final poly in polyList) {
          // [수정된 부분] 리스트 안의 값을 하나씩 검사해서 '정수(int)'인 것만 담습니다.
          // "thin" 같은 문자가 들어오면 무시합니다.
          final List<int> line = [];
          if (poly is List) {
            for (final item in poly) {
              if (item is int) {
                line.add(item);
              } else if (item is String) {
                // 혹시 문자로 된 숫자("123")가 있다면 변환 시도
                final parsed = int.tryParse(item);
                if (parsed != null) line.add(parsed);
              }
            }
          }

          if (line.isNotEmpty) {
            polylines.add(line);
          }
        }
        linesByCode[upperKey] = polylines;
      });

      // 3. 별자리 이름 파싱
      final Map<String, ConstellationName> namesByCode = {};
      rawNames.forEach((key, value) {
        final String upperKey = key.toUpperCase();
        namesByCode[upperKey] =
            ConstellationName.fromJson(value as Map<String, dynamic>);
      });

      // 4. 별 데이터 파싱
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

      debugPrint(
          '[CatalogLoader] 로드 완료: 선(${linesByCode.length}), 이름(${namesByCode.length}), 별(${starsByHip.length})');

      _cache = data;
      return data;
    } catch (e, stack) {
      debugPrint('❌ [CatalogLoader] 치명적 에러: $e');
      debugPrint(stack.toString());
      rethrow;
    }
  }

  static void clearCacheForDebug() {
    if (kDebugMode) _cache = null;
  }
}
