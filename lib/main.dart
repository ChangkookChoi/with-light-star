import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart'; // [필수] 이 패키지 import

import 'screens/splash_screen.dart'; // 스플래시 화면 import

void main() async {
  // [필수] async 추가
  WidgetsFlutterBinding.ensureInitialized(); // [필수] 플러터 엔진 초기화 보장

  // [핵심] 한국어 날짜 데이터 초기화
  await initializeDateFormatting('ko_KR', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'With Light Star',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'NanumGothic', // 폰트 설정 (pubspec.yaml에 등록된 이름)
      ),
      home: const SplashScreen(), // 스플래시 화면으로 시작
      debugShowCheckedModeBanner: false, // 디버그 띠 제거
    );
  }
}
