import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MapScreen(),
  ));
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Set<Marker> _markers = {};
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  
  // 커스텀 아이콘을 담을 변수
  BitmapDescriptor? customIcon;

  @override
  void initState() {
    super.initState();
    _setCustomMarker(); // 앱 시작 시 커스텀 아이콘 로드
    _fetchMarkers();    // 앱 시작 시 서버 데이터 로드
  }

  // 1. 커스텀 마커 아이콘 설정 함수
  void _setCustomMarker() async {
    // assets 폴더에 marker_bolt.png 파일이 있어야 합니다.
    // 파일이 없다면 일단 기본 노란색 마커로 대체되도록 설정했습니다.
    try {
      customIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(50, 50)),
        'assets/marker_bolt.png',
      );
      setState(() {});
    } catch (e) {
      // 이미지 로드 실패 시 노란색 기본 마커 사용
      debugPrint("아이콘 로드 에러: $e");
      customIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
  }

  // 2. 서버(Firestore)에서 실시간으로 데이터를 읽어오는 함수
  void _fetchMarkers() {
    FirebaseFirestore.instance
        .collection('meetings')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _markers.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          _markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(data['lat'], data['lng']),
              icon: customIcon ?? BitmapDescriptor.defaultMarker, // 커스텀 아이콘 적용
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

  // 3. 서버(Firebase)에 저장하는 함수
  Future<void> _saveToFirebase(LatLng pos) async {
    try {
      await FirebaseFirestore.instance.collection('meetings').add({
        'title': _titleController.text,
        'time': _timeController.text,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint("서버 저장 에러: $e");
    }
  }

  // 4. 지도를 눌렀을 때 입력창을 띄우는 함수
  void _showInputSheet(LatLng pos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20, left: 20, right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚡ 새로운 번개 모임 만들기', 
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              TextField(
                controller: _titleController, 
                decoration: const InputDecoration(labelText: '모임 제목 (예: 농구하실 분!)')
              ),
              TextField(
                controller: _timeController, 
                decoration: const InputDecoration(labelText: '모임 시간 (예: 오늘 저녁 8시)')
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_titleController.text.isNotEmpty) {
                    await _saveToFirebase(pos);
                    
                    if (!mounted) return; // 비동기 작업 후 안전 체크
                    _titleController.clear();
                    _timeController.clear();
                    Navigator.pop(context);
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('번개 모임이 등록되었습니다!'))
                    );
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
        title: const Text('Hyper-Local 번개 모임'), 
        backgroundColor: Colors.green
      ),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(37.5665, 126.9780), 
          zoom: 14
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        markers: _markers,
        onTap: _showInputSheet,
      ),
    );
  }
}