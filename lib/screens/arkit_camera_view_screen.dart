import 'dart:async';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart'; // [필수] 위치 정보 가져오기

import '../../data/catalog_loader.dart';
import '../../data/catalog_models.dart';
import 'ar/ar_scene_factory.dart';

class ArkitCameraViewScreen extends StatefulWidget {
  const ArkitCameraViewScreen({super.key});

  @override
  State<ArkitCameraViewScreen> createState() => _ArkitCameraViewScreenState();
}

class _ArkitCameraViewScreenState extends State<ArkitCameraViewScreen> {
  late ARKitController arkitController;
  CatalogData? _catalog;
  bool _isLoading = true;
  bool _showAtmosphere = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    arkitController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await [Permission.camera, Permission.location].request();
    final data = await CatalogLoader.loadOnce();

    if (mounted) {
      setState(() {
        _catalog = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body:
            Center(child: CircularProgressIndicator(color: Colors.amberAccent)),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          ARKitSceneView(
            onARKitViewCreated: onARKitViewCreated,
            // [중요] 나침반+중력 센서 사용
            worldAlignment: ARWorldAlignment.gravityAndHeading,
            configuration: ARKitConfiguration.worldTracking,
          ),
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            top: 50,
            right: 20,
            child: IconButton(
              icon: Icon(
                _showAtmosphere ? Icons.blur_on : Icons.blur_off,
                color: _showAtmosphere ? Colors.amberAccent : Colors.white54,
              ),
              onPressed: _toggleAtmosphere,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleAtmosphere() {
    setState(() {
      _showAtmosphere = !_showAtmosphere;
    });

    // [수정 전] opacity 조절 (동작 불안정)
    // arkitController.update('atmosphere', opacity: _showAtmosphere ? 0.3 : 0.0);

    // [수정 후] isHidden 속성 사용 (확실한 동작)
    // _showAtmosphere가 true면 -> isHidden은 false(보임)
    // _showAtmosphere가 false면 -> isHidden은 true(숨김)
    arkitController.update('atmosphere', isHidden: !_showAtmosphere);
  }

  void onARKitViewCreated(ARKitController arkitController) async {
    this.arkitController = arkitController;
    await _init3DScene();
  }

  Future<void> _init3DScene() async {
    if (_catalog == null) return;
    print("🌌 [AR] 3D 씬 구성 시작...");

    // [핵심] 현재 GPS 위치 가져오기
    // 이미 권한은 _loadData에서 요청했으므로 바로 가져옴
    // 실패 시 기본값(서울 시청) 사용 등 예외 처리 가능
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      print("❌ 위치 가져오기 실패, 기본값(서울) 사용: $e");
      position = Position(
          longitude: 126.9780,
          latitude: 37.5665,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0);
    }

    final double lat = position.latitude;
    final double lon = position.longitude;
    print("📍 내 위치: Lat $lat, Lon $lon");

    final List<ARKitNode> nodesToAdd = [];

    // 1. 배경/지평선 (위치 무관)
    nodesToAdd.add(ArSceneFactory.createAtmosphereNode());
    nodesToAdd.addAll(ArSceneFactory.createHorizonNodes());

    // 2. 별 데이터
    final hipsInLines = <int>{};
    for (final polyList in _catalog!.linesByCode.values) {
      for (final poly in polyList) hipsInLines.addAll(poly);
    }

    // 3. 노드 생성 (lat, lon 전달)
    nodesToAdd.addAll(
        ArSceneFactory.createStarNodes(_catalog!, hipsInLines, lat, lon));
    nodesToAdd.addAll(ArSceneFactory.createLineNodes(_catalog!, lat, lon));
    nodesToAdd.addAll(ArSceneFactory.createLabelNodes(_catalog!, lat, lon));

    // 4. 달 추가 (lat, lon 전달)
    final moonNode = ArSceneFactory.createMoonNode(lat, lon);
    if (moonNode != null) nodesToAdd.add(moonNode);

    // 5. 등록
    for (final node in nodesToAdd) {
      await arkitController.add(node);
    }

    print("✅ [AR] 씬 구성 완료!");
  }
}
