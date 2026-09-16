import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'map_screen.dart';
import 'gathering_list_screen.dart'; 
import '../screens/my_meetups_screen.dart'; 
import 'chat_list_screen.dart';
import '../services/chat_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  
  // 💡 화면 상단에 알림 팝업을 띄우기 위한 플러그인
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  final List<Widget> _screens = [
    const MapScreen(), 
    GatheringListScreen(), 
    ChatListScreen(), 
    const MyMeetupsScreen(), 
  ];

  @override
  void initState() {
    super.initState();
    _setupPushNotifications(); // 💡 앱이 켜지면 푸시 알림 세팅 시작
  }

  Future<void> _setupPushNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. 내 스마트폰의 고유 주소(토큰)를 가져와서 DB에 저장
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      _saveTokenToDB(user.uid, token);
    }

    // 2. 시간이 지나 토큰이 만료/변경되면 자동으로 DB 업데이트
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _saveTokenToDB(user.uid, newToken);
    });

    // 3. 앱을 켜고 보고 있을 때(포그라운드) 알림을 화면에 띄우기 위한 초기화
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);
    
    // 💡 [수정 1] 최신 버전에 맞게 이름표(initializationSettings:) 추가
    await _localNotifications.initialize(settings: initSettings); 

    // 4. 앱 사용 중 알림 메시지가 날아오면 즉시 화면 상단에 팝업 띄우기
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        // 💡 [수정 2] 최신 버전에 맞게 이름표(id:, title:, body:, notificationDetails:) 추가
        _localNotifications.show(
          id: message.hashCode,
          title: message.notification!.title,
          body: message.notification!.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'lightning_app_channel', 
              '번개 모임 알림',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      }
    });
  }

  // 💡 users 컬렉션에 fcmToken 저장 (기존 데이터를 보존하며 덮어쓰기)
  void _saveTokenToDB(String uid, String token) {
    FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '지도'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: '모임 목록'),
          BottomNavigationBarItem(icon: _ChatTabIcon(), label: '채팅'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '내 정보'),
        ],
      ),
    );
  }
}

class _ChatTabIcon extends StatelessWidget {
  const _ChatTabIcon();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: ChatService().totalUnreadCountStream(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.chat),
            if (count > 0)
              Positioned(
                right: -8,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}