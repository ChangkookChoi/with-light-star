import 'dart:async';
import 'dart:math' as math;

import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;

import '../astro/astro_math.dart';
import '../astro/types.dart';
import '../data/catalog_loader.dart';
import '../data/catalog_models.dart';

class ArkitCameraViewScreen extends StatefulWidget {
  const ArkitCameraViewScreen({super.key});

  @override
  State<ArkitCameraViewScreen> createState() => _ArkitCameraViewScreenState();
}

class _ArkitCameraViewScreenState extends State<ArkitCameraViewScreen>
    with WidgetsBindingObserver {
  ARKitController? _arkit;
  CatalogData? _catalog;

  bool _loading = true;
  bool _isStabilizing = true;

  Size? _cameraImageSize;

  // ===== 3D 거리 설정 =====
  final double _maxMagForBackground = 4.5;

  static const double _starDistance = 150.0; // 별
  static const double _labelDistance = 140.0; // 이름 (별보다 10m 앞)
  static const double _moonDistance = 130.0;
  static const double _sunDistance = 300.0;

  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  ARKitNode? _moonNode;
  ARKitNode? _lightNode;
  ARKitNode? _horizonNode;

  List<ARKitNode> _labelNodes = [];
  int _frameCount = 0;

  Set<int> _hipsInLines = {};

  final double _latDeg = 37.5665;
  final double _lonDeg = 126.9780;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCatalog();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isStabilizing = false;
        });
        if (_arkit != null && _catalog != null) {
          _init3DScene();
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arkit?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadScreen();
    }
  }

  void _reloadScreen() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation1, animation2) =>
            const ArkitCameraViewScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _loadCatalog() async {
    setState(() => _loading = true);
    final data = await CatalogLoader.loadOnce();

    final hips = <int>{};
    for (final v in data.linesByCode.values) {
      for (final poly in v) {
        hips.addAll(poly);
      }
    }

    if (mounted) {
      setState(() {
        _catalog = data;
        _hipsInLines = hips;
        _loading = false;
      });
    }
  }

  void _onARKitViewCreated(ARKitController controller) async {
    _arkit = controller;
    try {
      _cameraImageSize = await controller.getCameraImageResolution();
    } catch (_) {
      _cameraImageSize = null;
    }

    if (!_isStabilizing && _catalog != null) {
      _init3DScene();
    }

    controller.updateAtTime = (_) => _tick();
  }

  void _init3DScene() {
    if (_arkit == null || _catalog == null) return;

    _addHorizonGuide(_arkit!);
    _addStars3D(_arkit!, _catalog!);
    _addLines3D(_arkit!, _catalog!);
    _addLabels3D(_arkit!, _catalog!);
  }

  void _tick() {
    if (!mounted || _loading || _catalog == null || _arkit == null) return;
    if (_isStabilizing) return;

    final now = DateTime.now();
    if (now.difference(_lastUpdate).inMilliseconds < 16) return;
    _lastUpdate = now;

    // 천체 위치 업데이트
    _updateMoonNode(_arkit!, now, _latDeg, _lonDeg);
    _updateSunLight(_arkit!, now, _latDeg, _lonDeg);

    // 화면 포커스 로직 (크기 조절)
    _frameCount++;
    if (_frameCount % 5 == 0) {
      _checkLabelFocus(_arkit!);
    }
  }

  Future<void> _checkLabelFocus(ARKitController c) async {
    final size = MediaQuery.of(context).size;
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    for (final node in _labelNodes) {
      final screenPoint = await c.projectPoint(node.position);

      if (screenPoint != null) {
        final dist = math.sqrt(math.pow(screenPoint.x - centerX, 2) +
            math.pow(screenPoint.y - centerY, 2));

        // 중앙 150px 이내면 보이고, 멀어지면 작아짐
        double targetScale;
        if (dist < 150) {
          targetScale = 0.5; // 원래 크기
        } else if (dist < 300) {
          targetScale = 0.5 * (1.0 - ((dist - 150) / 150));
        } else {
          targetScale = 0.0;
        }

        if (targetScale < 0.01) targetScale = 0.0;
        node.scale = v.Vector3(targetScale, targetScale, targetScale);
      }
    }
  }

  // ====================================================
  // [Labels] 별자리 이름 (정석 LookAt 행렬 방식)
  // ====================================================
  void _addLabels3D(ARKitController c, CatalogData catalog) {
    final nowUtc = DateTime.now().toUtc();
    _labelNodes.clear();

    for (final code in catalog.linesByCode.keys) {
      final name = catalog.namesByCode[code]?.displayName() ?? '';
      if (name.isEmpty) continue;

      // 대표 별 찾기
      double minMag = 999.0;
      int? alphaStarHip;
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

      // 위치 계산: 별보다 10m 앞 (140m)
      final labelPos = _calculatePosition(
          alphaStar.raDeg, alphaStar.decDeg, nowUtc, _labelDistance);
      if (labelPos == null) continue;

      // [핵심 수정] LookAt 행렬 계산
      // 1. 내 위치(pos)에서 원점(0,0,0)을 바라보는 회전 각도를 구함
      // 2. 단, '위쪽(Up)'은 반드시 하늘(0,1,0)을 향해야 함 (그래야 눕지 않음)
      final euler = _calculateLookAtEuler(labelPos, v.Vector3(0, 0, 0));

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

      final node = ARKitNode(
        geometry: textGeo,
        position: labelPos,
        scale: v.Vector3(0, 0, 0), // 초기엔 안 보임
        eulerAngles: euler, // [수정] 행렬로 계산된 정확한 각도 적용
        name: 'label_$code',
      );

      c.add(node);
      _labelNodes.add(node);
    }
  }

  // [신규 헬퍼 함수] LookAt 행렬을 만들고 Euler Angle로 변환
  v.Vector3 _calculateLookAtEuler(v.Vector3 position, v.Vector3 target) {
    // 1. Forward Vector (내가 바라보는 방향: 나 -> 타겟)
    // ARKit 텍스트는 기본적으로 +Z를 앞면으로 함. 따라서 타겟 쪽이 +Z가 되도록 설정.
    final forward = (target - position).normalized();

    // 2. Up Vector (하늘 방향)
    // 기본적으로 World Y(0,1,0)를 사용하지만, 만약 머리 위(Zenith)라서
    // Forward와 Up이 평행하면 계산이 깨지므로 예외 처리
    v.Vector3 up = v.Vector3(0, 1, 0);
    if ((forward.dot(up)).abs() > 0.99) {
      up = v.Vector3(0, 0, -1); // 임시 축 변경
    }

    // 3. Right Vector (오른쪽 방향 = Up x Forward)
    final right = up.cross(forward).normalized();

    // 4. Real Up Vector (진짜 위쪽 = Forward x Right)
    // 이렇게 다시 계산해야 직각이 보장됨
    final realUp = forward.cross(right).normalized();

    // 5. 회전 행렬 생성 (Basis Vectors)
    // ARKitNode의 로컬 좌표계: Right(X), RealUp(Y), Forward(Z)
    final rotationMatrix = v.Matrix4(
      right.x,
      right.y,
      right.z,
      0,
      realUp.x,
      realUp.y,
      realUp.z,
      0,
      forward.x,
      forward.y,
      forward.z,
      0,
      0,
      0,
      0,
      1,
    );

    // 6. 행렬에서 Euler Angles (Pitch, Yaw, Roll) 추출
    // Z-Y-X 순서 추출 (일반적인 3D 그래픽스 표준)
    final r11 = rotationMatrix.entry(0, 0);
    final r21 = rotationMatrix.entry(1, 0);
    final r31 = rotationMatrix.entry(2, 0);
    final r32 = rotationMatrix.entry(2, 1);
    final r33 = rotationMatrix.entry(2, 2);

    final pitch = math.atan2(r32, r33); // X축 회전
    final yaw = math.atan2(-r31, math.sqrt(r32 * r32 + r33 * r33)); // Y축 회전
    final roll = math.atan2(r21, r11); // Z축 회전

    return v.Vector3(pitch, yaw, roll);
  }

  // ... (기존 _calculatePosition, _addStars3D 등 나머지 함수들은 동일) ...

  v.Vector3? _calculatePosition(
      double ra, double dec, DateTime utc, double distance) {
    final altAz = raDecToAltAz(
        raDeg: ra, decDeg: dec, latDeg: _latDeg, lonDeg: _lonDeg, utc: utc);
    if (altAz.altDeg <= -5) return null;
    final azRad = altAz.azDeg * math.pi / 180;
    final altRad = altAz.altDeg * math.pi / 180;
    final x = math.sin(azRad) * math.cos(altRad);
    final y = math.sin(altRad);
    final z = -math.cos(azRad) * math.cos(altRad);
    return v.Vector3(x, y, z) * distance;
  }

  // 나머지 함수들 (_addStars3D, _addLines3D, _addHorizonGuide, _updateMoonNode, _updateSunLight 등)
  // 기존 코드 그대로 유지해주세요.

  void _addStars3D(ARKitController c, CatalogData catalog) {
    final coreMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white),
      lightingModelName: ARKitLightingModel.constant,
    );
    final haloMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white.withOpacity(0.15)),
      lightingModelName: ARKitLightingModel.constant,
    );
    final nowUtc = DateTime.now().toUtc();

    for (final entry in catalog.starsByHip.entries) {
      final hip = entry.key;
      final star = entry.value;
      final mag = star.mag ?? 99;
      bool isConstellationStar = _hipsInLines.contains(hip);
      if (!isConstellationStar && mag > _maxMagForBackground) continue;

      final pos =
          _calculatePosition(star.raDeg, star.decDeg, nowUtc, _starDistance);
      if (pos == null) continue;

      double coreRadius;
      if (mag < 0.0)
        coreRadius = 0.5;
      else if (mag < 1.5)
        coreRadius = 0.35;
      else if (mag < 3.0)
        coreRadius = 0.2;
      else
        coreRadius = 0.08;

      if (isConstellationStar && coreRadius < 0.12) coreRadius = 0.12;

      final coreNode = ARKitNode(
        geometry: ARKitSphere(radius: coreRadius, materials: [coreMaterial]),
        position: pos,
      );
      c.add(coreNode);

      if (mag < 2.5) {
        final haloNode = ARKitNode(
          geometry:
              ARKitSphere(radius: coreRadius * 4.0, materials: [haloMaterial]),
          position: pos,
        );
        c.add(haloNode);
      }
    }
  }

  void _addLines3D(ARKitController c, CatalogData catalog) {
    final nowUtc = DateTime.now().toUtc();
    final lineMaterial = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(Colors.white.withOpacity(0.2)),
      lightingModelName: ARKitLightingModel.constant,
    );

    for (final entry in catalog.linesByCode.entries) {
      for (final poly in entry.value) {
        for (var i = 0; i < poly.length - 1; i++) {
          final hip1 = poly[i];
          final hip2 = poly[i + 1];
          final star1 = catalog.starsByHip[hip1];
          final star2 = catalog.starsByHip[hip2];
          if (star1 == null || star2 == null) continue;
          final pos1 = _calculatePosition(
              star1.raDeg, star1.decDeg, nowUtc, _starDistance);
          final pos2 = _calculatePosition(
              star2.raDeg, star2.decDeg, nowUtc, _starDistance);
          if (pos1 == null || pos2 == null) continue;
          final line = ARKitLine(
              fromVector: pos1, toVector: pos2, materials: [lineMaterial]);
          c.add(ARKitNode(geometry: line));
        }
      }
    }
  }

  void _addHorizonGuide(ARKitController c) {
    final ring = ARKitTorus(
      ringRadius: _starDistance,
      pipeRadius: 0.2,
      materials: [
        ARKitMaterial(
          diffuse: ARKitMaterialProperty.color(
              Colors.lightBlueAccent.withOpacity(0.3)),
          lightingModelName: ARKitLightingModel.constant,
        )
      ],
    );
    _horizonNode = ARKitNode(
      geometry: ring,
      position: v.Vector3(0, 0, 0),
      eulerAngles: v.Vector3(math.pi / 2, 0, 0),
    );
    c.add(_horizonNode!);
  }

  void _updateMoonNode(
      ARKitController c, DateTime now, double lat, double lon) {
    final moonRaDec = AstroMath.getMoonRaDec(now.toUtc());
    final pos = _calculatePosition(
        moonRaDec.ra, moonRaDec.dec, now.toUtc(), _moonDistance);
    if (pos == null) {
      if (_moonNode != null) {
        c.remove(_moonNode!.name);
        _moonNode = null;
      }
      return;
    }
    final moonPos = pos;
    if (_moonNode == null) {
      final material = ARKitMaterial(
        diffuse: ARKitMaterialProperty.image('assets/images/moon_texture.jpg'),
        lightingModelName: ARKitLightingModel.physicallyBased,
        roughness: ARKitMaterialProperty.value(1.0),
        metalness: ARKitMaterialProperty.value(0.0),
      );
      final sphere = ARKitSphere(radius: 8.0, materials: [material]);
      _moonNode =
          ARKitNode(geometry: sphere, position: moonPos, name: 'moon_node');
      c.add(_moonNode!);
    } else {
      _moonNode!.position = moonPos;
    }
  }

  void _updateSunLight(
      ARKitController c, DateTime now, double lat, double lon) {
    final sunRaDec = AstroMath.getSunRaDec(now.toUtc());
    final sunPos = _calculatePosition(
        sunRaDec.ra, sunRaDec.dec, now.toUtc(), _sunDistance);
    if (sunPos == null) return;

    if (_lightNode == null) {
      final light = ARKitLight(
        type: ARKitLightType.omni,
        intensity: 5000,
        temperature: 6500,
        color: Colors.white,
      );
      _lightNode = ARKitNode(light: light, position: sunPos, name: 'sun_light');
      c.add(_lightNode!);
    } else {
      _lightNode!.position = sunPos;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ARKitSceneView(
            onARKitViewCreated: _onARKitViewCreated,
            configuration: ARKitConfiguration.worldTracking,
            worldAlignment: ARWorldAlignment.gravityAndHeading,
            autoenablesDefaultLighting: false,
          ),
          if (_isStabilizing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text("나침반 보정 중...",
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: IconButton(
                  icon:
                      const Icon(Icons.refresh, color: Colors.white, size: 28),
                  onPressed: () {
                    _reloadScreen();
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: 60,
            left: 20,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text("AR Mode | Corrected LookAt",
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
