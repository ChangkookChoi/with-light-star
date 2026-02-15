# with-light-star

별자리 관측/스토리 앱(Flutter) 프로젝트. 다른 에이전트가 빠르게 구조를 이해할 수 있도록 핵심 폴더만 요약합니다.

## 목표

- AR 기반 별자리 관측 경험 제공
- 현재 위치/시간 기반의 관측 가이드 제공
- 별자리 정보 및 스토리 확장

## 현재 개발 상태 (2026-02-09)

- 스플래시 화면 구현 및 메인 화면 전환(2.5초)
- 메인 관측 홈 화면 구현: 날짜/위치 표시, 가이드 배너, 추천 별자리 카드, AR 관측 진입 버튼
- 위치 권한 요청 및 현재 위치/주소 변환 흐름 구현
- iOS ARKit 관측 화면 구현: 별/별자리 선/라벨/달 3D 배치, 대기권 토글, 중앙 조준점
- 별자리/별 데이터 로더 및 모델 구현
- ARKit용 천문 계산 유틸(별 위치 변환, 달 위치 계산) 구현
- 네이티브 나침반 진북 스트림 채널 인터페이스만 정의(플랫폼 구현 필요)
- Android AR 및 센서 융합 기반 관측 화면은 미구현(의존성만 포함)

## 프로젝트 구조 요약

```
lib/
  main.dart                      # 앱 실행 진입점 (Splash -> 메인 화면)
  app.dart                       # 이전 라우팅/테마 설정 (현재 미사용)
  screens/
    splash_screen.dart           # 스플래시 화면
    observation_screen.dart      # 메인 관측 홈 화면
    arkit_camera_view_screen.dart# iOS ARKit 기반 3D 별자리 관측 화면
    ar/
      ar_scene_factory.dart      # ARKit 노드(별/선/라벨/달/지평선) 생성
      ar_utils.dart              # ARKit 좌표/달 위치 계산 유틸
  data/
    catalog_loader.dart          # 별/별자리 JSON 로드 및 캐시
    catalog_models.dart          # 별/별자리 데이터 모델 정의
  astro/
    types.dart                   # 천문 계산 공통 타입
    astro_math.dart              # RA/Dec → Alt/Az 변환
    projection.dart              # Alt/Az → 화면 좌표 투영
    attitude_math.dart           # 센서 쿼터니언 → 오일러 변환
    circular_math.dart           # 각도 보정용 원형 EMA 유틸
  services/
    true_heading_service.dart    # 진북 스트림 채널 인터페이스
  widgets/
    constellation_painter.dart   # 별자리 라인/라벨 오버레이 페인터
    arkit_sky_painter.dart       # ARKit용 별/달 오버레이 페인터
    arkit_debug_painter.dart     # ARKit 디버그용 보조 페인터

assets/
  data/
    constellation_lines.json
    constellation_lines_bk.json
    constellation_names.json
    stars_min.json
  images/
    moon_texture.jpg
    splash_image.png
```

## 패키지 현황

- `camera` ^0.11.0: 실시간 카메라 제어(현재 코드 미사용)
- `sensors_plus` ^6.1.1: 자이로/가속도 센서(현재 코드 미사용)
- `permission_handler` ^11.3.1: 카메라/위치 권한 요청
- `http` ^1.2.0: API 통신용(현재 코드 미사용)
- `flutter_compass` ^0.8.0: 나침반(현재 코드 미사용)
- `motion_sensors` ^0.1.0: 자세/방향 융합(현재 코드 미사용)
- `geolocator` ^12.0.0: 현재 위치(GPS)
- `geocoding` ^2.1.1: 좌표 → 주소 변환
- `intl` ^0.20.2: 날짜 포맷
- `arkit_plugin` (local path): iOS ARKit 렌더링
- `cupertino_icons` ^1.0.2: iOS 아이콘
- `flutter_lints` ^3.0.0: 코드 품질 관리(dev)

## Flutter assets 등록

- `assets/data/constellation_lines.json`
- `assets/data/constellation_lines_bk.json`
- `assets/data/constellation_names.json`
- `assets/data/stars_min.json`
- `assets/images/moon_texture.jpg`
- `assets/images/splash_image.png`


## Data 출처
```
아래 링크의 데이터를 원본으로 파싱하여 사용
```
- constellation_lines.json : https://github.com/Stellarium/stellarium-skycultures/blob/master/western/index.json
- star_min.json : https://github.com/astronexus/HYG-Database/blob/main/hyg/v3/hyg_v38.csv.gz
