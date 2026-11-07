import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'views/main_shell.dart';
import 'screens/login_screen.dart';
import 'screens/verify_identity_screen.dart';

// 앱이 백그라운드에 있을 때 FCM 메시지를 처리하는 핸들러
// 웹에서는 Firebase Messaging 백그라운드 핸들러를 등록하지 않습니다.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('백그라운드 메시지 수신: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 로드 실패가 앱 전체 실행을 막지 않도록 처리합니다.
  // 단, .env가 로드되지 않으면 Gemini 기능은 API 키를 읽지 못할 수 있습니다.
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('[초기화] .env 로드 완료');
  } catch (e, stackTrace) {
    debugPrint('[초기화 경고] .env 로드 실패: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  // Firebase는 웹과 모바일 모두에서 초기화합니다.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[초기화] Firebase 초기화 완료');

  // FCM 백그라운드 등록과 알림 권한 요청은 네이티브 앱에서만 수행합니다.
  // iPhone Safari의 일반 웹페이지에서는 푸시 알림 권한 요청이 제한될 수 있고,
  // 시연에 필요한 Firestore 실시간 채팅에는 이 권한이 필요하지 않습니다.
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[초기화] FCM 알림 권한 요청 완료');
    } catch (e, stackTrace) {
      // 알림 권한 요청 실패가 앱 화면 실행을 막지 않게 합니다.
      debugPrint('[초기화 경고] FCM 알림 권한 요청 실패: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  } else {
    debugPrint('[초기화] 웹 환경이므로 FCM 권한 요청을 건너뜁니다.');
  }

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
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 4,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// 로그인 상태와 본인인증 상태에 따라 시작 화면을 결정합니다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        return FutureBuilder<void>(
          future: FirebaseAuth.instance.currentUser?.reload(),
          builder: (context, reloadSnapshot) {
            if (reloadSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (reloadSnapshot.hasError) {
              debugPrint('[인증 확인 오류] ${reloadSnapshot.error}');
            }

            final user = FirebaseAuth.instance.currentUser;
            final isVerified =
                (user?.emailVerified ?? false) ||
                (user?.phoneNumber != null);

            if (!isVerified) {
              return const VerifyIdentityScreen();
            }

            return const MainShell();
          },
        );
      },
    );
  }
}
