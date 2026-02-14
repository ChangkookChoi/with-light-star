import 'dart:async';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:permission_handler/permission_handler.dart';

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

  // [위치 캐시] 노드 제어용 (여기서는 위치 업데이트용이 아니라 목록 관리용으로 사용)
  final Map<String, v.Vector3> _nodePositions = {};

  // [상태 캐시] 중복 업데이트 방지
  final Map<String, double> _cachedOpacity = {};
  final Map<String, bool> _cachedHidden = {};

  bool _showAtmosphere = true;
  Timer? _interactionTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _interactionTimer?.cancel();
    arkitController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await [Permission.camera, Permission.location].request();
    try {
      final data = await CatalogLoader.loadOnce();
      if (mounted) {
        setState(() {
          _catalog = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("데이터 로드 실패: $e");
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
            worldAlignment: ARWorldAlignment.gravityAndHeading,
            configuration: ARKitConfiguration.worldTracking,
          ),

          // 뒤로가기 버튼
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // 대기권 버튼
          Positioned(
            top: 50,
            right: 20,
            child: IconButton(
              icon: Icon(
                _showAtmosphere ? Icons.blur_on : Icons.blur_off,
                color: _showAtmosphere ? Colors.amberAccent : Colors.white54,
                size: 30,
              ),
              onPressed: _toggleAtmosphere,
            ),
          ),

          // 중앙 조준점
          Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withOpacity(0.7), width: 1.5),
              ),
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
    // 대기권 업데이트 (여기는 로직 유지)
    arkitController.update('atmosphere', opacity: _showAtmosphere ? 0.3 : 0.0);
  }

  void onARKitViewCreated(ARKitController arkitController) async {
    this.arkitController = arkitController;
    await _init3DScene();
    _startInteractionLoop();
  }

  Future<void> _init3DScene() async {
    if (_catalog == null) return;

    print("🌌 [AR] 노드 생성 및 배치 시작...");

    final List<ARKitNode> nodesToAdd = [];

    // 배경 및 지평선
    nodesToAdd.add(ArSceneFactory.createAtmosphereNode());
    nodesToAdd.addAll(ArSceneFactory.createHorizonNodes());

    // 별 데이터 추출
    final hipsInLines = <int>{};
    for (final polyList in _catalog!.linesByCode.values) {
      for (final poly in polyList) hipsInLines.addAll(poly);
    }

    // 천체 노드 생성 (별, 선, 라벨, 달)
    nodesToAdd.addAll(ArSceneFactory.createStarNodes(_catalog!, hipsInLines));
    nodesToAdd.addAll(ArSceneFactory.createLineNodes(_catalog!));
    nodesToAdd.addAll(ArSceneFactory.createLabelNodes(_catalog!));

    final moonNode = ArSceneFactory.createMoonNode();
    if (moonNode != null) nodesToAdd.add(moonNode);

    // 노드 등록
    for (final node in nodesToAdd) {
      await arkitController.add(node);

      // 관리 대상 등록
      if (node.name != null) {
        _nodePositions[node.name!] = node.position;
        // 초기 상태: 보임(false), 불투명(1.0)
        _cachedOpacity[node.name!] = 1.0;
        _cachedHidden[node.name!] = false;
      }
    }
    print("✅ [AR] 모든 노드 배치 완료.");
  }

  void _startInteractionLoop() {
    _interactionTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!mounted) return;

      // 카메라 정보 가져오기는 유지 (추후 필요할 수 있으므로 구조는 남겨둠)
      final cameraPose = await arkitController.cameraProjectionMatrix();
      if (cameraPose == null) return;

      // 모든 노드에 대해 상태 업데이트 수행
      _nodePositions.forEach((name, position) {
        _updateNodeState(name);
      });
    });
  }

  // [수정됨] 조건 로직 제거 -> 항상 보이고 선명하게 유지
  void _updateNodeState(String name) {
    // 1. 대기권이나 방위표는 건드리지 않음
    if (name == 'atmosphere' || name.startsWith('direction_')) return;

    // 2. [변경 사항] 모든 별, 선, 라벨, 달에 대해 "항상 보임", "투명도 1.0" 강제 설정
    // 지평선 아래 필터링 제거됨
    // 다이내믹 포커스 제거됨

    bool shouldShow = true; // 무조건 보임
    double targetOpacity = 1.0; // 무조건 선명함

    // 3. 최적화 (값이 변하지 않았으면 업데이트 안 함 - 브릿지 부하 방지)
    double currentOpacity = _cachedOpacity[name] ?? 1.0;
    bool currentHidden = _cachedHidden[name] ?? false;

    // shouldShow가 true이면 hidden은 false여야 함.
    bool isHiddenChanged = (currentHidden == shouldShow);
    bool isOpacityChanged = (currentOpacity - targetOpacity).abs() > 0.05;

    if (!isHiddenChanged && !isOpacityChanged) return;

    // 캐시 업데이트
    _cachedHidden[name] = !shouldShow;
    _cachedOpacity[name] = targetOpacity;

    // 네이티브 업데이트 요청
    arkitController.update(
      name,
      isHidden: !shouldShow, // false (보임)
      opacity: targetOpacity, // 1.0 (선명)
    );
  }
}
