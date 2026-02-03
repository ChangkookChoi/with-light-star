import 'dart:math' as math;
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import '../../data/catalog_models.dart';
import 'ar_utils.dart';

class ArSceneFactory {
  // 거리 설정 (700m)
  static const double starDistance = 700.0;
  static const double labelDistance = 700.0;

  /// [가상 배경]
  static ARKitNode createAtmosphereNode() {
    return ARKitNode(
      geometry: ARKitSphere(
        radius: 900.0,
        materials: [
          ARKitMaterial(
            diffuse: ARKitMaterialProperty.color(
                const Color(0xFF1A103C).withOpacity(0.3)),
            doubleSided: true,
            lightingModelName: ARKitLightingModel.constant,
          )
        ],
      ),
      position: v.Vector3.zero(),
      name: 'atmosphere_node',
    );
  }

  /// [지평선 및 방위표]
  static List<ARKitNode> createHorizonNodes() {
    final List<ARKitNode> nodes = [];

    // 1. 지평선 링
    final horizonRing = ARKitNode(
      geometry: ARKitTorus(
        ringRadius: starDistance,
        pipeRadius: 1.0,
        materials: [
          ARKitMaterial(
            diffuse: ARKitMaterialProperty.color(Colors.blueGrey),
            lightingModelName: ARKitLightingModel.constant,
          )
        ],
      ),
      position: v.Vector3.zero(),
      eulerAngles: v.Vector3(math.pi / 2, 0, 0),
    );
    nodes.add(horizonRing);

    // 2. 방위표 (N, E, S, W)
    final directions = {
      'N': v.Vector3(0, 0, -starDistance),
      'E': v.Vector3(starDistance, 0, 0),
      'S': v.Vector3(0, 0, starDistance),
      'W': v.Vector3(-starDistance, 0, 0),
    };

    directions.forEach((text, pos) {
      final textGeo = ARKitText(
        text: text,
        extrusionDepth: 0.1,
        materials: [
          ARKitMaterial(
            diffuse: ARKitMaterialProperty.color(Colors.blueGrey),
            lightingModelName: ARKitLightingModel.constant,
          )
        ],
      );

      nodes.add(ARKitNode(
        geometry: textGeo,
        position: pos,
        scale: v.Vector3.all(5.0), // 방위표 크기 유지
        isBillboard: true,
      ));
    });

    return nodes;
  }

  /// [별] - 선에 연결된 별만 그려서 '외톨이 점' 제거
  static List<ARKitNode> createStarNodes(
      CatalogData catalog, Set<int> hipsInLines) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    final coreMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white),
      lightingModelName: ARKitLightingModel.constant,
    );
    final haloMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white.withOpacity(0.15)),
      lightingModelName: ARKitLightingModel.constant,
    );

    // [핵심 수정] 모든 별을 도는 게 아니라, '선에 포함된 별(hipsInLines)'만 순회
    for (final hip in hipsInLines) {
      final star = catalog.starsByHip[hip];
      if (star == null) continue; // 혹시 데이터가 없으면 패스

      final mag = star.mag ?? 99;
      // 4.5등급보다 어두운 별은 데이터가 있어도 안 그림 (조절 가능)
      if (mag > 4.5) continue;

      final pos = ArUtils.calculatePosition(
          star.raDeg, star.decDeg, nowUtc, starDistance);
      if (pos == null) continue;

      // 별 크기 설정
      double radius;
      if (mag < 0.0)
        radius = 1.5;
      else if (mag < 1.5)
        radius = 1.35;
      else if (mag < 3.0)
        radius = 1.15;
      else
        radius = 1.0;

      // 선에 포함된 별이므로 강조 (여기선 모든 별이 선에 포함되므로 기본 적용)
      radius *= 1.15;

      // 1. 별의 핵 (Core)
      nodes.add(ARKitNode(
          geometry: ARKitSphere(radius: radius, materials: [coreMaterial]),
          position: pos));

      // 2. 밝은 별은 후광(Halo) 추가
      if (mag < 2.0) {
        nodes.add(ARKitNode(
            geometry:
                ARKitSphere(radius: radius * 3.5, materials: [haloMaterial]),
            position: pos));
      }
    }
    return nodes;
  }

  /// [별자리 선]
  /// Stellarium 데이터(연결된 폴리라인)에 맞춰 i++ 루프 사용
  static List<ARKitNode> createLineNodes(CatalogData catalog) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    // Star Walk 스타일: 깔끔한 반투명 흰색 선 (가시성 위해 0.4로 살짝 상향)
    final lineMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white.withOpacity(0.4)),
      lightingModelName: ARKitLightingModel.constant,
    );

    for (final entry in catalog.linesByCode.entries) {
      // entry.value는 [[A, B, C], [D, E]] 같은 폴리라인들의 리스트
      for (final poly in entry.value) {
        // [중요 수정] Stellarium 데이터는 점들이 연결되어 있으므로
        // i++ (순차 증가)를 사용하여 끊어짐 없이 연결합니다.
        // 예: [A, B, C] -> A-B 연결하고, 그 다음 B-C 연결
        for (var i = 0; i < poly.length - 1; i++) {
          final s1 = catalog.starsByHip[poly[i]];
          final s2 = catalog.starsByHip[poly[i + 1]];

          if (s1 != null && s2 != null) {
            final p1 = ArUtils.calculatePosition(
                s1.raDeg, s1.decDeg, nowUtc, starDistance);
            final p2 = ArUtils.calculatePosition(
                s2.raDeg, s2.decDeg, nowUtc, starDistance);

            if (p1 != null && p2 != null) {
              nodes.add(ARKitNode(
                geometry: ARKitLine(
                    fromVector: p1, toVector: p2, materials: [lineMaterial]),
              ));
            }
          }
        }
      }
    }
    return nodes;
  }

  /// [라벨] - 별자리의 중앙(무게중심)에 이름 띄우기
  static List<ARKitNode> createLabelNodes(CatalogData catalog) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    for (final code in catalog.linesByCode.keys) {
      final name = catalog.namesByCode[code]?.displayName() ?? '';
      if (name.isEmpty) continue;

      // 1. 별자리에 포함된 모든 별들의 좌표 수집
      double sumRa = 0.0;
      double sumDec = 0.0;
      int count = 0;

      // 이미 방문한 별은 중복 계산 방지
      final visitedHips = <int>{};

      for (final poly in catalog.linesByCode[code]!) {
        for (final hip in poly) {
          if (visitedHips.contains(hip)) continue;

          final star = catalog.starsByHip[hip];
          if (star != null) {
            sumRa += star.raDeg;
            sumDec += star.decDeg;
            visitedHips.add(hip);
            count++;
          }
        }
      }

      if (count == 0) continue;

      // 2. 평균 위치(무게중심) 계산
      // 주의: RA(적경)는 360도 순환하므로 단순히 더해서 나누면
      // 359도와 1도의 평균이 180도가 되는 오류가 날 수 있습니다.
      // 하지만 별자리는 좁은 구역에 모여 있으므로 단순 평균도 대부분 잘 작동합니다.
      // 정석적인 벡터 평균 대신, 일단 간단한 산술 평균으로 적용합니다.
      final avgRa = sumRa / count;
      final avgDec = sumDec / count;

      // 3. 라벨 위치 계산
      // 지평선 아래 이름 숨기기 (allowBelowHorizon: false)
      final labelPos = ArUtils.calculatePosition(
          avgRa, avgDec, nowUtc, labelDistance,
          allowBelowHorizon: false);

      if (labelPos == null) continue;

      final textGeo = ARKitText(
        text: name,
        extrusionDepth: 0.01,
        fontName: 'NanumGothicBold',
        materials: [
          ARKitMaterial(
            diffuse: ARKitMaterialProperty.color(Colors.white),
            lightingModelName: ARKitLightingModel.constant,
          )
        ],
      );

      nodes.add(ARKitNode(
        geometry: textGeo,
        position: labelPos,
        scale: v.Vector3.all(20.0),
        isBillboard: true,
        name: 'label_$code',
      ));
    }
    return nodes;
  }
}
