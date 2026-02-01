# with-light-star

별자리 관측/스토리 앱(Flutter) 프로젝트. 다른 에이전트가 빠르게 구조를 이해할 수 있도록 핵심 폴더만 요약합니다.

## 프로젝트 구조 요약

```
lib/
  main.dart                      # 앱 실행 진입점 (runApp 호출)
  app.dart                       # MaterialApp 및 테마 설정, 홈 화면 라우팅
  screens/
    observation_screen.dart      # 관측 메인 UI (카드/가이드/내비게이션)
    camera_view_screen.dart      # 카메라+센서 기반 관측/오버레이 화면
    arkit_camera_view_screen.dart# iOS ARKit 기반 3D 별자리 관측 화면
    real_horizon_screen.dart     # 실제 지평선 가이드/나침반 보조 화면
  widgets/
    constellation_painter.dart   # 별자리 라인/라벨 오버레이 커스텀 페인터
    arkit_sky_painter.dart       # ARKit용 별/달 오버레이 페인터
    arkit_debug_painter.dart     # ARKit 디버그용 보조 페인터
  data/
    catalog_loader.dart          # 별/별자리 JSON 로드 및 캐시
    catalog_models.dart          # 별/별자리 데이터 모델 정의
  astro/
    types.dart                   # 천문 계산 공통 타입(AltAz, ScreenPoint)
    astro_math.dart              # RA/Dec → Alt/Az 변환, 시간/각도 보정
    projection.dart              # Alt/Az → 화면 좌표 투영
    attitude_math.dart           # 센서 쿼터니언 → 오일러 변환
    circular_math.dart           # 각도 보정용 원형 EMA 유틸
  services/
    true_heading_service.dart    # 나침반/자북→진북 보정 서비스

assets/
  data/
    constellation_lines.json     # 별자리 선 연결 정보
    constellation_names.json     # 별자리 명칭/별칭
    stars_min.json               # 별 RA/Dec/등급 최소 데이터
  images/
    moon_texture.jpg             # 달 텍스처(ARKit)

android/ ios/ macos/ linux/ windows/ web/  # 플랫폼별 빌드 타깃
build/                                     # 로컬 빌드 산출물
```

## 의존성/리소스 요약

- 주요 의존성: `camera`, `sensors_plus`, `geolocator`, `permission_handler`, `http`, `flutter_compass`, `motion_sensors`, `arkit_plugin`
- Flutter assets 등록:
  - `assets/data/constellation_lines.json`
  - `assets/data/constellation_names.json`
  - `assets/data/stars_min.json`
  - `assets/images/moon_texture.jpg`
