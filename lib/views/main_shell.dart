import 'package:flutter/material.dart';
import 'map_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0; // 현재 선택된 탭 번호

  final GlobalKey<MapScreenState> _mapKey = GlobalKey();

  // 🚀 표시할 화면들 (팀원들이 각자 만들면 여기에 하나씩 추가)
  late final List<Widget> _screens = [
    MapScreen(key: _mapKey),
    const MapScreen(), // 0번: 팀장님의 지도 화면
    const Center(child: Text("리스트 화면 (준비중)")), // 1번
    const Center(child: Text("채팅 화면 (준비중)")), // 2번
    const Center(child: Text("내 정보 (준비중)")), // 3번
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🚀 IndexedStack을 쓰면 지도가 초기화되지 않고 상태가 유지됩니다!
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),

      // 🚀 플로팅 액션 버튼 (번개 만들기)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_selectedIndex == 0) {
            _mapKey.currentState?.openCreationSheet();
          } else {
            setState(() => _selectedIndex = 0);
          }
          // TODO: 지도 화면의 모임 생성 함수와 연결 예정
          print("번개 모임 생성 버튼 클릭!");
        },
        label: const Text("번개 열기", style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.bolt),
        backgroundColor: Colors.amber,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

      // 🚀 하단 네비게이션 바
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed, // 아이콘 4개 이상일 때 필수
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '지도'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '목록'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: '채팅'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: '내 정보'),
        ],
      ),
    );
  }
}