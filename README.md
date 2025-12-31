# with_light_star

별자리 관측/스토리 앱(Flutter) 프로젝트. 다른 에이전트가 빠르게 구조를 이해할 수 있도록 핵심 폴더만 요약합니다.

## 프로젝트 구조 요약

```
lib/
  main.dart                 # 앱 엔트리 포인트
  app.dart                  # 최상위 앱 위젯
  features/
    observation/
      screens/
        observation_screen.dart  # 관측 메인 화면
        camera_view_screen.dart  # 카메라/센서 기반 관측 화면

assets/
  data/
    constellation_lines.json
    constellation_names.json
    stars_min.json
    meta.json
    required_hips.json
    stars_meta.json
    stars_missing.json

android/ ios/ macos/ linux/ windows/ web/  # 플랫폼별 빌드 타깃
build/                                     # 로컬 빌드 산출물
```

## 의존성/리소스 요약

- 주요 의존성: `camera`, `sensors_plus`, `geolocator`, `permission_handler`, `http`, `flutter_compass`
- Flutter assets 등록: `assets/data/constellation_lines.json`, `assets/data/constellation_names.json`, `assets/data/stars_min.json`
