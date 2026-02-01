import 'dart:math' as math;
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import '../../data/catalog_models.dart';
import 'ar_utils.dart';

class ArSceneFactory {
  // 거리 설정
  static const double starDistance = 450.0;
  static const double labelDistance = 450.0;

  /// [가상 배경]
  static ARKitNode createAtmosphereNode() {
    return ARKitNode(
      geometry: ARKitSphere(
        radius: 600.0,
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
        pipeRadius: 3.0,
        materials: [
          ARKitMaterial(
            diffuse: ARKitMaterialProperty.color(Colors.cyanAccent),
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
      // [삭제] 더 이상 수학 계산 필요 없음!
      // final rotation = ArUtils.calculateSimpleLookAt(pos);

      final textGeo = ARKitText(
        text: text,
        extrusionDepth: 2.0,
        materials: [
          ARKitMaterial(
            diffuse: ARKitMaterialProperty.color(Colors.cyanAccent),
            lightingModelName: ARKitLightingModel.constant,
          )
        ],
      );

      nodes.add(ARKitNode(
        geometry: textGeo,
        position: pos,
        scale: v.Vector3.all(40.0),

        // [핵심] 우리가 뚫어놓은 기능 사용!
        isBillboard: true,

        // [삭제] rotation 넣으면 충돌날 수 있으니 제거
        // eulerAngles: rotation,
      ));
    });

    return nodes;
  }

  /// [별]
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

    for (final entry in catalog.starsByHip.entries) {
      final star = entry.value;
      final mag = star.mag ?? 99;

      if (mag > 4.5) continue;

      final pos = ArUtils.calculatePosition(
          star.raDeg, star.decDeg, nowUtc, starDistance);
      if (pos == null) continue;

      double radius;
      if (mag < 0.0)
        radius = 0.7;
      else if (mag < 1.5)
        radius = 0.5;
      else if (mag < 3.0)
        radius = 0.3;
      else
        radius = 0.15;

      if (hipsInLines.contains(entry.key)) radius *= 1.3;

      nodes.add(ARKitNode(
          geometry: ARKitSphere(radius: radius, materials: [coreMaterial]),
          position: pos));

      if (mag < 2.0) {
        nodes.add(ARKitNode(
            geometry:
                ARKitSphere(radius: radius * 4.0, materials: [haloMaterial]),
            position: pos));
      }
    }
    return nodes;
  }

  /// [별자리 선]
  static List<ARKitNode> createLineNodes(CatalogData catalog) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    final lineMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white.withOpacity(0.2)),
      lightingModelName: ARKitLightingModel.constant,
    );

    for (final entry in catalog.linesByCode.entries) {
      for (final poly in entry.value) {
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

  /// [라벨]
  static List<ARKitNode> createLabelNodes(CatalogData catalog) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    for (final code in catalog.linesByCode.keys) {
      final name = catalog.namesByCode[code]?.displayName() ?? '';
      if (name.isEmpty) continue;

      int? alphaStarHip;
      double minMag = 999.0;
      for (final poly in catalog.linesByCode[code]!) {
        for (final hip in poly) {
          final star = catalog.starsByHip[hip];
          if (star != null && (star.mag ?? 99) < minMag) {
            minMag = star.mag ?? 99;
            alphaStarHip = hip;
          }
        }
      }
      if (alphaStarHip == null) continue;
      final alphaStar = catalog.starsByHip[alphaStarHip];
      if (alphaStar == null) continue;

      final labelPos = ArUtils.calculatePosition(
          alphaStar.raDeg, alphaStar.decDeg, nowUtc, labelDistance,
          allowBelowHorizon: true);
      if (labelPos == null) continue;

      // [삭제] 수학 계산 안녕!
      // final rotation = ArUtils.calculateSimpleLookAt(labelPos);

      final textGeo = ARKitText(
        text: name,
        extrusionDepth: 0.01,
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
        scale: v.Vector3.all(1.5),

        // [핵심] 우리가 만든 그 기능!
        isBillboard: true,

        name: 'label_$code',
      ));
    }
    return nodes;
  }
}
