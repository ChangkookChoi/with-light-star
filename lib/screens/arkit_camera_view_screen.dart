import 'dart:async';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// [중요] 사용자의 폴더 구조에 맞춘 Import 경로
import '../../data/catalog_loader.dart';
import '../../data/catalog_models.dart';
import 'ar/ar_scene_factory.dart';

class ArkitCameraViewScreen extends StatefulWidget {
  const ArkitCameraViewScreen({super.key});

  @override
  State<ArkitCameraViewScreen> createState() => _ArkitCameraViewScreenState();
}

class _ArkitCameraViewScreenState extends State<ArkitCameraViewScreen> {
  ARKitController? _arkit;
  CatalogData? _catalog;

  bool _loading = true;
  bool _isStabilizing = true;
  bool _isAtmosphereOn = true;

  Set<int> _hipsInLines = {};

  @override
  void initState() {
    super.initState();
    _loadCatalog();

    // 안정화 타이머 (1.5초)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _isStabilizing = false);
        if (_arkit != null && _catalog != null) _init3DScene();
      }
    });
  }

  @override
  void dispose() {
    _arkit?.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() => _loading = true);

    try {
      // CatalogLoader 호출
      final data = await CatalogLoader.loadOnce();

      // 별 강조용 ID 추출
      final hips = <int>{};
      for (final lines in data.linesByCode.values) {
        for (final poly in lines) {
          hips.addAll(poly);
        }
      }

      if (mounted) {
        setState(() {
          _catalog = data;
          _hipsInLines = hips;
          _loading = false; // 로딩 해제
        });

        // 이미 AR 뷰가 만들어졌다면 씬 그리기
        if (_arkit != null && !_isStabilizing) {
          _init3DScene();
        }
      }
    } catch (e) {
      debugPrint("❌ AR Screen 로딩 에러: $e");
      if (mounted) {
        setState(() => _loading = false); // 에러나면 로딩 끄기
        _showErrorDialog(e.toString());
      }
    }
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("데이터 로딩 실패"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("확인"),
          )
        ],
      ),
    );
  }

  void _onARKitViewCreated(ARKitController controller) {
    _arkit = controller;
    if (!_loading && !_isStabilizing && _catalog != null) {
      _init3DScene();
    }
  }

  void _init3DScene() {
    if (_arkit == null || _catalog == null) return;

    // 1. 가상 배경
    if (_isAtmosphereOn) {
      _arkit!.add(ArSceneFactory.createAtmosphereNode());
    }

    // 2. 지평선
    final horizonNodes = ArSceneFactory.createHorizonNodes();
    for (var node in horizonNodes) _arkit!.add(node);

    // 3. 별
    final starNodes = ArSceneFactory.createStarNodes(_catalog!, _hipsInLines);
    for (var node in starNodes) _arkit!.add(node);

    // 4. 별자리 선
    final lineNodes = ArSceneFactory.createLineNodes(_catalog!);
    for (var node in lineNodes) _arkit!.add(node);

    // 5. 라벨
    final labelNodes = ArSceneFactory.createLabelNodes(_catalog!);
    for (var node in labelNodes) _arkit!.add(node);
  }

  void _toggleAtmosphere() {
    if (_arkit == null) return;
    setState(() => _isAtmosphereOn = !_isAtmosphereOn);

    if (_isAtmosphereOn) {
      _arkit!.add(ArSceneFactory.createAtmosphereNode());
    } else {
      _arkit!.remove('atmosphere_node');
    }
  }

  void _reloadScreen() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, a1, a2) => const ArkitCameraViewScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

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
                child:
                    Text("위치 안정화 중...", style: TextStyle(color: Colors.white)),
              ),
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
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isAtmosphereOn ? Icons.blur_on : Icons.blur_off,
                      color: Colors.white),
                  onPressed: _toggleAtmosphere,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _reloadScreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
