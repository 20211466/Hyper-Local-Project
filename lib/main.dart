import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 👈 dotenv 임포트 확인!
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; 
import 'firebase_options.dart';

import 'views/main_shell.dart';
import 'screens/login_screen.dart'; // 💡 팀원이 만든 로그인 화면
import 'screens/verify_identity_screen.dart'; // 💡 팀원이 추가한 본인인증 화면

// 💡 앱이 꺼져있거나 화면을 내린 상태일 때 알림을 받아주는 함수 (팀장님 코드)
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
        
        // 💡 팀원분이 작성한 디테일한 로그인 + 본인인증 체크 로직 (팀원 코드 수용)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 1. 로그인 데이터가 없으면 (로그아웃 상태) -> 팀원이 만든 로그인 화면으로 이동!
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // 2. 로그인은 했지만 본인인증(이메일 인증 또는 휴대폰 인증)이 안 됐다면
        //    -> 본인인증 화면으로 이동! (Google 로그인 유저는 이메일이 이미 인증된 상태로 취급됩니다)
        return FutureBuilder<void>(
          future: FirebaseAuth.instance.currentUser?.reload(),
          builder: (context, reloadSnapshot) {
            if (reloadSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final user = FirebaseAuth.instance.currentUser;
            final isVerified = (user?.emailVerified ?? false) || (user?.phoneNumber != null);

            if (!isVerified) {
              return const VerifyIdentityScreen();
            }

            // 3. 로그인 + 본인인증까지 완료 -> 원래 보려던 MainShell(지도 등) 화면으로 이동!
            return const MainShell();
          },
        );
      },
    );
  }
}