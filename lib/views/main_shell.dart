import 'package:flutter/material.dart';
import 'map_screen.dart'; 
import 'gathering_list_screen.dart'; // 💡 팀원이 새로 만든 목록 화면 가져오기

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  // 💡 팀장님의 4개 탭 구조를 유지하되, 1번 인덱스에 팀원의 목록 화면을 매핑합니다.
  final List<Widget> _screens = [
    const MapScreen(),                    // 0번 탭: 지도
    GatheringListScreen(),                // 1번 탭: 모임 목록 (팀원 코드)
    const Center(child: Text('채팅 내역')), // 2번 탭: 채팅
    const Center(child: Text('내 정보')),  // 3번 탭: 내 정보
  ];

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
          BottomNavigationBarItem(icon: Icon(Icons.list), label: '모임 목록'), // 💡 탭 메뉴 추가
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '채팅'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '내 정보'),
        ],
      ),
    );
  }
}