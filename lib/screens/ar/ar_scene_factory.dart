import 'dart:math' as math;
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import '../../data/catalog_models.dart';
import 'ar_utils.dart'; // [체크] utils 경로가 맞는지 확인해주세요

class ArSceneFactory {
  // [전략] 거리 500m (원근감 확보)
  static const double starDistance = 500.0;
  static const double labelDistance = 500.0;

  /// [배경] 대기권 (위치 정보 불필요)
  static ARKitNode createAtmosphereNode() {
    return ARKitNode(
      geometry: ARKitSphere(
        radius: starDistance * 1.5,
        materials: [
          ARKitMaterial(
            diffuse: ARKitMaterialProperty.color(
                const Color(0xFF050510).withOpacity(0.2)),
            doubleSided: true,
            lightingModelName: ARKitLightingModel.constant,
          )
        ],
      ),
      position: v.Vector3.zero(),
      name: 'atmosphere',
    );
  }

  /// [지평선] Horizon & Compass (위치 정보 불필요)
  static List<ARKitNode> createHorizonNodes() {
    final List<ARKitNode> nodes = [];

    // 1. 지평선 링
    nodes.add(ARKitNode(
      geometry: ARKitTorus(
        ringRadius: starDistance,
        pipeRadius: 0.5,
        materials: [
          ARKitMaterial(
            diffuse:
                ARKitMaterialProperty.color(Colors.white.withOpacity(0.15)),
            lightingModelName: ARKitLightingModel.constant,
          )
        ],
      ),
      position: v.Vector3.zero(),
      eulerAngles: v.Vector3(math.pi / 2, 0, 0),
      name: 'horizon_ring',
    ));

    // 2. 방위표 (N, E, S, W) - 고정 위치
    final directions = {
      'N': v.Vector3(0, 0, -starDistance),
      'E': v.Vector3(starDistance, 0, 0),
      'S': v.Vector3(0, 0, starDistance),
      'W': v.Vector3(-starDistance, 0, 0),
    };

    directions.forEach((text, pos) {
      nodes.add(ARKitNode(
        geometry: ARKitText(
          text: text,
          extrusionDepth: 0.1,
          fontName: 'NanumGothicBold',
          materials: [
            ARKitMaterial(
              diffuse: ARKitMaterialProperty.color(
                  Colors.amberAccent.withOpacity(0.7)),
              lightingModelName: ARKitLightingModel.constant,
            )
          ],
        ),
        position: pos,
        scale: v.Vector3.all(10.0), // 방위표 크기
        isBillboard: true,
        name: 'direction_$text',
      ));
    });

    return nodes;
  }

  /// [별] Stars - (수정됨: Sphere -> Plane + Texture)
  static List<ARKitNode> createStarNodes(
      CatalogData catalog, Set<int> hipsInLines, double lat, double lon) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    // [핵심 변경 1] 텍스처 머티리얼 정의
    final starMaterial = ARKitMaterial(
      // 색상 대신 이미지를 사용
      diffuse: ARKitMaterialProperty.image('assets/images/star_glow.png'),

      // 스스로 빛나는 모드 (그림자 안 생김)
      lightingModelName: ARKitLightingModel.constant,

      // [중요] 투명한 부분이 뒤의 물체를 가리지 않게 함 (Glow 효과 필수 설정)
      writesToDepthBuffer: false,

      // 혹시 이미지가 약간 어둡다면 투명도를 조절 (1.0 = 불투명)
      transparency: 1.0,
    );

    for (final hip in hipsInLines) {
      final star = catalog.starsByHip[hip];
      if (star == null) continue;

      final mag = star.mag ?? 99.0;
      if (mag > 5.5) continue;

      final pos = ArUtils.calculatePosition(
          star.raDeg, star.decDeg, nowUtc, starDistance, lat, lon,
          allowBelowHorizon: true);

      if (pos == null) continue;

      // [핵심 변경 2] 크기(Size) 로직 조정
      // 구체(반지름)일 때보다 Plane(가로/세로)일 때 조금 더 커야 빛 번짐이 예쁩니다.
      // 500m 거리 기준
      double size = 2.5;

      if (mag < 0.0)
        size = 8.0; // 시리우스 (가장 큼)
      else if (mag < 1.5)
        size = 6.0; // 1등성
      else if (mag < 3.0)
        size = 4.5; // 2~3등성
      else
        size = 2.5; // 그 외

      nodes.add(ARKitNode(
        // [핵심 변경 3] Sphere -> Plane으로 교체
        geometry: ARKitPlane(
          width: size,
          height: size,
          materials: [starMaterial],
        ),
        position: pos,

        // [필수] 별이 항상 카메라를 바라봐야 동그랗게 보임
        isBillboard: true,

        name: 'star_$hip',
      ));
    }
    return nodes;
  }

  /// [선] Lines - (lat, lon 파라미터 추가됨)
  static List<ARKitNode> createLineNodes(
      CatalogData catalog, double lat, double lon) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    final lineMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white.withOpacity(0.2)),
      lightingModelName: ARKitLightingModel.constant,
    );

    int lineCount = 0;
    for (final entry in catalog.linesByCode.entries) {
      final code = entry.key;
      for (final poly in entry.value) {
        for (var i = 0; i < poly.length - 1; i++) {
          final s1 = catalog.starsByHip[poly[i]];
          final s2 = catalog.starsByHip[poly[i + 1]];

          if (s1 != null && s2 != null) {
            // [수정] lat, lon 전달
            final p1 = ArUtils.calculatePosition(
                s1.raDeg, s1.decDeg, nowUtc, starDistance, lat, lon,
                allowBelowHorizon: true);
            final p2 = ArUtils.calculatePosition(
                s2.raDeg, s2.decDeg, nowUtc, starDistance, lat, lon,
                allowBelowHorizon: true);

            if (p1 != null && p2 != null) {
              nodes.add(ARKitNode(
                geometry: ARKitLine(
                  fromVector: p1,
                  toVector: p2,
                  materials: [lineMaterial],
                ),
                name: 'line_${code}_${lineCount++}',
              ));
            }
          }
        }
      }
    }
    return nodes;
  }

  /// [라벨] Labels - (lat, lon 파라미터 추가됨)
  static List<ARKitNode> createLabelNodes(
      CatalogData catalog, double lat, double lon) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    final textMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.amberAccent.withOpacity(0.9)),
      lightingModelName: ARKitLightingModel.constant,
    );

    for (final code in catalog.linesByCode.keys) {
      final nameData = catalog.namesByCode[code];
      final displayName = nameData?.displayName() ?? code;

      double sumRa = 0.0;
      double sumDec = 0.0;
      int count = 0;
      final visitedHips = <int>{};

      if (catalog.linesByCode[code] == null) continue;

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

      // [수정] lat, lon 전달
      final labelPos = ArUtils.calculatePosition(
          sumRa / count, sumDec / count, nowUtc, labelDistance, lat, lon,
          allowBelowHorizon: true);

      if (labelPos == null) continue;

      nodes.add(ARKitNode(
        geometry: ARKitText(
          text: displayName,
          extrusionDepth: 0.1,
          fontName: 'NanumGothicBold',
          materials: [textMaterial],
        ),
        position: labelPos,
        scale: v.Vector3.all(6.0), // 별자리 이름 크기
        isBillboard: true,
        name: 'label_$code',
      ));
    }
    return nodes;
  }

  /// [달] Moon - (lat, lon 파라미터 추가됨)
  static ARKitNode? createMoonNode(double lat, double lon) {
    final nowUtc = DateTime.now().toUtc();
    final moonCoords = ArUtils.calculateMoonRaDec(nowUtc);

    // [수정] lat, lon 전달
    final pos = ArUtils.calculatePosition(moonCoords['ra']!, moonCoords['dec']!,
        nowUtc, starDistance * 0.9, lat, lon,
        allowBelowHorizon: true);

    if (pos == null) return null;

    return ARKitNode(
      geometry: ARKitSphere(
        radius: 8.0,
        materials: [
          ARKitMaterial(
            diffuse:
                ARKitMaterialProperty.image('assets/images/moon_texture.jpg'),
            lightingModelName: ARKitLightingModel.constant,
          ),
        ],
      ),
      position: pos,
      name: 'moon_node',
    );
  }
}
