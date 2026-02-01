import 'dart:async';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';

import '../data/catalog_loader.dart';
import '../data/catalog_models.dart';
import 'ar/ar_scene_factory.dart';
import 'ar/ar_utils.dart';

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

  // 가상 배경 켜짐/꺼짐 상태 (기본값: 켜짐)
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

  void _onARKitViewCreated(ARKitController controller) {
    _arkit = controller;
    if (!_isStabilizing && _catalog != null) _init3DScene();
  }

  void _init3DScene() {
    if (_arkit == null || _catalog == null) return;

    // 1. 가상 배경 추가
    if (_isAtmosphereOn) {
      _arkit!.add(ArSceneFactory.createAtmosphereNode());
    }

    // [추가됨] 2. 지평선 및 방위표 추가
    // 이 부분이 빠져있어서 지평선이 안 보였습니다.
    final horizonNodes = ArSceneFactory.createHorizonNodes();
    for (var node in horizonNodes) _arkit!.add(node);

    // 3. 별 추가
    final starNodes = ArSceneFactory.createStarNodes(_catalog!, _hipsInLines);
    for (var node in starNodes) _arkit!.add(node);

    // 4. 별자리 선 추가
    final lineNodes = ArSceneFactory.createLineNodes(_catalog!);
    for (var node in lineNodes) _arkit!.add(node);

    // 5. 라벨 추가
    final labelNodes = ArSceneFactory.createLabelNodes(_catalog!);
    for (var node in labelNodes) _arkit!.add(node);
  }

  // 가상 배경 토글
  void _toggleAtmosphere() {
    if (_arkit == null) return;

    setState(() {
      _isAtmosphereOn = !_isAtmosphereOn;
    });

    if (_isAtmosphereOn) {
      _arkit!.add(ArSceneFactory.createAtmosphereNode());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🌌 가상 배경 켜짐"),
          duration: Duration(milliseconds: 500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      _arkit!.remove('atmosphere_node');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("OFF 가상 배경 꺼짐"),
          duration: Duration(milliseconds: 500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _reloadScreen() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, anim1, anim2) => const ArkitCameraViewScreen(),
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
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. AR View
          ARKitSceneView(
            onARKitViewCreated: _onARKitViewCreated,
            configuration: ARKitConfiguration.worldTracking,
            worldAlignment: ARWorldAlignment.gravityAndHeading,
            autoenablesDefaultLighting: false,
          ),

          // 2. 안정화 인디케이터
          if (_isStabilizing)
            Container(
                color: Colors.black87,
                child: const Center(
                    child: Text("안정화 중...",
                        style: TextStyle(color: Colors.white)))),

          // 3. UI 버튼들
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context)),
                    Row(
                      children: [
                        // 가상 배경 토글 버튼
                        IconButton(
                          icon: Icon(
                              _isAtmosphereOn ? Icons.blur_on : Icons.blur_off,
                              color: _isAtmosphereOn
                                  ? Colors.amberAccent
                                  : Colors.white54,
                              size: 28),
                          onPressed: _toggleAtmosphere,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                            icon: const Icon(Icons.refresh,
                                color: Colors.white, size: 28),
                            onPressed: () => _reloadScreen()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
