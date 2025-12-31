import 'package:flutter/material.dart';
import 'screens/observation_screen.dart'; // 분리한 화면 호출

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '나의 별 이야기',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        primaryColor: Colors.amberAccent,
      ),
      home: const MainObservationScreen(),
    );
  }
}
