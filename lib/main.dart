import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
<<<<<<< Updated upstream
import 'views/main_shell.dart'; // 새로 만든 쉘을 불러옵니다.
=======
import 'views/gathering_list_screen.dart';
// import 'views/map_screen.dart'; // 만약 MapScreen을 별도 파일로 뺐다면 활성화
>>>>>>> Stashed changes

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
<<<<<<< Updated upstream

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Hyper-Local',
    theme: ThemeData(
      primarySwatch: Colors.green,
      useMaterial3: true, // 최신 UI 스타일 적용
    ),
    home: const MainShell(), // 입구를 MainShell로 변경합니다.
  ));
}
=======
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainHolder(), // 탭 바가 있는 메인 홀더로 시작
    ),
  );
}

// --- [추가] 탭 바를 관리하는 메인 홀더 ---
class MainHolder extends StatefulWidget {
  const MainHolder({super.key});

  @override
  State<MainHolder> createState() => _MainHolderState();
}

class _MainHolderState extends State<MainHolder> {
  int _selectedIndex = 0; // 현재 선택된 탭 인덱스

  // 보여줄 화면 리스트
  final List<Widget> _screens = [
    const MapScreen(), // 0번 탭: 지도
    GatheringListScreen(), // 1번 탭: 목록
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex], // 선택된 화면 표시
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index; // 탭 클릭 시 화면 전환
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '지도'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: '목록'),
        ],
      ),
    );
  }
}

// --- [기존] MapScreen 클래스 (그대로 유지) ---
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Set<Marker> _markers = {};
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  BitmapDescriptor? customIcon;

  @override
  void initState() {
    super.initState();
    _setCustomMarker();
    _fetchMarkers();
  }

  void _setCustomMarker() async {
    try {
      customIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(50, 50)),
        'assets/marker_bolt.png',
      );
      setState(() {});
    } catch (e) {
      customIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueYellow,
      );
    }
  }

  void _fetchMarkers() {
    FirebaseFirestore.instance.collection('meetings').snapshots().listen((
      snapshot,
    ) {
      if (!mounted) return;
      setState(() {
        _markers.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          _markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(data['lat'], data['lng']),
              icon: customIcon ?? BitmapDescriptor.defaultMarker,
              infoWindow: InfoWindow(
                title: data['title'],
                snippet: "시간: ${data['time']}",
              ),
            ),
          );
        }
      });
    });
  }

  // main.dart 파일 내의 _saveToFirebase 함수
  Future<void> _saveToFirebase(LatLng pos) async {
    try {
      await FirebaseFirestore.instance.collection('meetings').add({
        'title': _titleController.text,
        'time': _timeController.text,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'createdAt': Timestamp.now(),
        'participants': [], // 👈 이 줄을 추가해서 빈 명단을 생성합니다.
      });
    } catch (e) {
      debugPrint("서버 저장 에러: $e");
    }
  }

  void _showInputSheet(LatLng pos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '⚡ 새로운 번개 모임 만들기',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '모임 제목'),
              ),
              TextField(
                controller: _timeController,
                decoration: const InputDecoration(labelText: '모임 시간'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_titleController.text.isNotEmpty) {
                    await _saveToFirebase(pos);
                    _titleController.clear();
                    _timeController.clear();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('등록되었습니다!')));
                  }
                },
                child: const Text('번개 만들기'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hyper-Local 번개 지도'),
        backgroundColor: Colors.green,
      ),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(37.5665, 126.9780),
          zoom: 14,
        ),
        myLocationEnabled: true,
        markers: _markers,
        onTap: _showInputSheet,
      ),
    );
  }
}
>>>>>>> Stashed changes
