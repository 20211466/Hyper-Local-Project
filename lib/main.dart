import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 👈 dotenv 임포트 확인!
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; 
import 'firebase_options.dart';

import 'views/main_shell.dart';
import 'screens/login_screen.dart';


// 💡 앱이 꺼져있거나 화면을 내린 상태일 때 알림을 받아주는 함수
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("백그라운드 메시지 수신: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 💡 [핵심 추가] 파이어베이스나 앱 화면을 그리기 전에 무조건 가장 먼저 .env(비밀 금고)를 열어옵니다!
  await dotenv.load(fileName: ".env");
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 백그라운드 알림 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 알림 권한 요청 팝업 띄우기
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.white,
        // 💡 [UI 업그레이드] 앱 전체의 스낵바를 공중에 띄우고 둥글게 만듭니다!
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), 
          elevation: 4,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// 로그인 상태에 따라 알아서 화면을 바꿔주는 문지기 위젯
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return const MainShell(); 
        }
        return const LoginScreen(); 
      },
    );
  }
}