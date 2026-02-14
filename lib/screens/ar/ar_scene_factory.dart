import 'dart:math' as math;
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import '../../data/catalog_models.dart';
import 'ar_utils.dart';

class ArSceneFactory {
  static const double starDistance = 700.0;
  static const double labelDistance = 700.0;

  /// [배경]
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
      name: 'atmosphere',
    );
  }

  /// [지평선]
  static List<ARKitNode> createHorizonNodes() {
    final List<ARKitNode> nodes = [];

    nodes.add(ARKitNode(
      geometry: ARKitTorus(
        ringRadius: starDistance,
        pipeRadius: 2.0,
        materials: [
          ARKitMaterial(
            diffuse:
                ARKitMaterialProperty.color(Colors.blueGrey.withOpacity(0.5)),
            lightingModelName: ARKitLightingModel.constant,
          )
        ],
      ),
      position: v.Vector3.zero(),
      eulerAngles: v.Vector3(math.pi / 2, 0, 0),
      name: 'horizon_ring',
    ));

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
          extrusionDepth: 1.0,
          materials: [
            ARKitMaterial(
              diffuse: ARKitMaterialProperty.color(Colors.amber),
              lightingModelName: ARKitLightingModel.constant,
            )
          ],
        ),
        position: pos,
        scale: v.Vector3.all(8.0),
        isBillboard: true, // 사용자 커스텀 기능
        name: 'direction_$text',
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

    for (final hip in hipsInLines) {
      final star = catalog.starsByHip[hip];
      if (star == null) continue;

      final mag = star.mag ?? 99.0;
      if (mag > 4.5) continue;

      final pos = ArUtils.calculatePosition(
          star.raDeg, star.decDeg, nowUtc, starDistance,
          allowBelowHorizon: true);
      if (pos == null) continue;

      double radius = 1.0;
      if (mag < 0.0)
        radius = 1.5;
      else if (mag < 1.5)
        radius = 1.35;
      else if (mag < 3.0) radius = 1.15;
      radius *= 1.2;

      nodes.add(ARKitNode(
        geometry: ARKitSphere(radius: radius, materials: [coreMaterial]),
        position: pos,
        name: 'star_$hip',
      ));
    }
    return nodes;
  }

  /// [선]
  static List<ARKitNode> createLineNodes(CatalogData catalog) {
    final List<ARKitNode> nodes = [];
    final nowUtc = DateTime.now().toUtc();

    final lineMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white.withOpacity(0.5)),
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
            final p1 = ArUtils.calculatePosition(
                s1.raDeg, s1.decDeg, nowUtc, starDistance,
                allowBelowHorizon: true);
            final p2 = ArUtils.calculatePosition(
                s2.raDeg, s2.decDeg, nowUtc, starDistance,
                allowBelowHorizon: true);

            if (p1 != null && p2 != null) {
              nodes.add(ARKitNode(
                geometry: ARKitLine(
                    fromVector: p1, toVector: p2, materials: [lineMaterial]),
                name: 'line_${code}_${lineCount++}',
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
      final nameData = catalog.namesByCode[code];
      final displayName = nameData?.displayName() ?? code;

      double sumRa = 0.0;
      double sumDec = 0.0;
      int count = 0;
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

      final labelPos = ArUtils.calculatePosition(
          sumRa / count, sumDec / count, nowUtc, labelDistance,
          allowBelowHorizon: true);

      if (labelPos == null) continue;

      nodes.add(ARKitNode(
        geometry: ARKitText(
          text: displayName,
          extrusionDepth: 0.01,
          fontName: 'NanumGothicBold', // [복구] 기존에 잘 작동하던 폰트 설정 유지
          materials: [
            ARKitMaterial(
              diffuse: ARKitMaterialProperty.color(Colors.white),
              lightingModelName: ARKitLightingModel.constant,
            )
          ],
        ),
        position: labelPos,
        scale: v.Vector3.all(25.0),
        isBillboard: true, // 사용자 커스텀 기능
        name: 'label_$code',
      ));
    }
    return nodes;
  }

  /// [달]
  static ARKitNode? createMoonNode() {
    final nowUtc = DateTime.now().toUtc();
    final moonCoords = ArUtils.calculateMoonRaDec(nowUtc);

    final pos = ArUtils.calculatePosition(
        moonCoords['ra']!, moonCoords['dec']!, nowUtc, starDistance * 0.9,
        allowBelowHorizon: true);

    if (pos == null) return null;

    return ARKitNode(
      geometry: ARKitSphere(
        radius: 20.0,
        materials: [
          ARKitMaterial(
            diffuse:
                ARKitMaterialProperty.image('assets/images/moon_texture.jpg'),
            lightingModelName: ARKitLightingModel.constant,
            transparency: 1.0,
          ),
        ],
      ),
      position: pos,
      name: 'moon_node',
    );
  }
}
