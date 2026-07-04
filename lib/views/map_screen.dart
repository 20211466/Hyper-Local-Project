import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import '../models/gathering_model.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
  Marker? _tempMarker;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isSheetOpen = false;
  LatLng? _currentP;
  double _currentHeading = 0.0;
  StreamSubscription<Position>? _positionStream;

  BitmapDescriptor? _boltIcon; 

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _selectedCategory = '기타';
  TimeOfDay? _selectedTime;
  
  int _maxParticipants = 4; 
  final List<String> _categories = ['운동', '식사', '공부', '게임', '산책', '기타'];

  void openCreationSheet() {
    LatLng targetPos = _currentP ?? const LatLng(37.9142, 127.1578);
    _showInputSheet(targetPos);
  }

  @override
  void initState() {
    super.initState();
    _loadBoltIcon(); 
    _determinePosition();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadBoltIcon() async {
    try {
      final Uint8List markerIcon = await getBytesFromAsset('assets/lightning_icon.png', 50);
      setState(() {
        _boltIcon = BitmapDescriptor.fromBytes(markerIcon);
      });
    } catch (e) {
      setState(() {
        _boltIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      });
    }
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentP = LatLng(position.latitude, position.longitude);
          _currentHeading = position.heading;
        });
      }
    });
  }

  // 🚀 [참여하기 창] 상용 앱 감성 디자인 적용 완료본
  void _onMarkerTapped(String docId, Map<String, dynamic> data) {
    setState(() => _isSheetOpen = true);
    int current = data['currentParticipants'] ?? 1;
    int max = data['maxParticipants'] ?? 4;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 드래그 핸들 바
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 카테고리 뱃지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                data['category'] ?? '기타',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),

            // 제목과 설명
            Text(data['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 10),
            Text(data['description'] ?? '상세 설명이 없습니다.', style: const TextStyle(fontSize: 16, color: Colors.black54, height: 1.4)),
            
            const Divider(height: 40, thickness: 1),
            
            // 인원 현황 영역
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.people_outline, color: Colors.grey, size: 20),
                    SizedBox(width: 6),
                    Text("참여 인원", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Text("$current / $max 명", style: TextStyle(
                  color: current >= max ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                )),
              ],
            ),
            const SizedBox(height: 12),
            
            // 게이지 바
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: current / max,
                backgroundColor: Colors.grey[100],
                color: current >= max ? Colors.redAccent : Colors.green,
                minHeight: 12, 
              ),
            ),
            const SizedBox(height: 25),
            
            // 마감 시간 안내
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.orange, size: 18),
                const SizedBox(width: 6),
                Text("⏰ 오늘 ${data['time']} 까지 모여요!", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 25),
            
            // 참여하기 버튼
            SizedBox(
              width: double.infinity, 
              height: 55,
              child: ElevatedButton(
                onPressed: current < max ? () async {
                  await _firestore.collection('meetings').doc(docId).update({'currentParticipants': FieldValue.increment(1)});
                  if (mounted) Navigator.pop(context);
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: current < max ? Colors.amber[400] : Colors.grey[300],
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(
                  current < max ? "⚡ 이 번개 참여하기" : "아쉽지만 인원이 꽉 찼어요", 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    ).then((_) => setState(() => _isSheetOpen = false));
  }

  // 🚀 [모임 생성 창] 기존 로직 완벽 유지
  void _showInputSheet(LatLng pos) async {
    if (_isSheetOpen) return;
    setState(() => _isSheetOpen = true);
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚡ 새로운 번개 만들기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                TextField(controller: _titleController, decoration: const InputDecoration(labelText: '제목')),
                TextField(controller: _noteController, decoration: const InputDecoration(labelText: '설명')),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("모집 정원: $_maxParticipants 명", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => setSheetState(() { if (_maxParticipants > 2) _maxParticipants--; }),
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        ),
                        IconButton(
                          onPressed: () => setSheetState(() { if (_maxParticipants < 20) _maxParticipants++; }),
                          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                        ),
                      ],
                    ),
                  ],
                ),
                ListTile(
                  title: Text(_selectedTime == null ? "마감 시간 선택" : "마감: ${_selectedTime!.format(context)}"),
                  trailing: const Icon(Icons.access_time, color: Colors.green), 
                  onTap: () async {
                    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (picked != null) setSheetState(() => _selectedTime = picked);
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    if (_titleController.text.isNotEmpty && _selectedTime != null) {
                      final now = DateTime.now();
                      final d = DateTime(now.year, now.month, now.day, _selectedTime!.hour, _selectedTime!.minute);
                      await _firestore.collection('meetings').add({
                        'title': _titleController.text,
                        'category': _selectedCategory,
                        'description': _noteController.text,
                        'time': _selectedTime!.format(context),
                        'lat': pos.latitude,
                        'lng': pos.longitude,
                        'currentParticipants': 1, 
                        'maxParticipants': _maxParticipants, 
                        'deadline': Timestamp.fromDate(d),
                      });
                      _titleController.clear(); _noteController.clear();
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text("번개 생성"),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
    setState(() {
      _isSheetOpen = false;
      _tempMarker = null;
    });
  }

  // 🚀 [빌드 영역] Scaffold는 없애고 Stack으로 감싸서 리턴합니다!
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. 구글 지도 레이어
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('meetings').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final now = DateTime.now();
            final markers = <Marker>{};

            if (_currentP != null) {
              markers.add(Marker(
                markerId: const MarkerId("me"),
                position: _currentP!,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                rotation: _currentHeading,
                anchor: const Offset(0.5, 0.5),
                zIndex: 5,
              ));
            }

            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (data['deadline'] != null) {
                DateTime deadline = (data['deadline'] as Timestamp).toDate();
                if (now.isAfter(deadline)) continue;
              }

              markers.add(Marker(
                markerId: MarkerId(doc.id),
                position: LatLng(data['lat'], data['lng']),
                icon: _boltIcon ?? BitmapDescriptor.defaultMarker, 
                onTap: () => _onMarkerTapped(doc.id, data),
              ));
            }

            return GoogleMap(
              initialCameraPosition: const CameraPosition(target: LatLng(37.9142, 127.1578), zoom: 14),
              onMapCreated: (controller) => mapController = controller,
              markers: {
                ...markers,
                if (_tempMarker != null) _tempMarker!,
              },
              onLongPress: (LatLng tappedPoint) {
                setState(() {
                  _tempMarker = Marker(
                    markerId: const MarkerId("temp_marker"),
                    position: tappedPoint,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  );
                });
                _showInputSheet(tappedPoint);
              },
              scrollGesturesEnabled: !_isSheetOpen,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true, 
              mapToolbarEnabled: false,
              compassEnabled: true,
            );
          },
        ),
        
        // 2. 상단 검색바 느낌의 UI 레이어 (상용 앱 감성 한 스푼 추가)
        Positioned(
          top: 50, left: 20, right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
            ),
            child: const Row(
              children: [
                Icon(Icons.search, color: Colors.green),
                SizedBox(width: 10),
                Text("동네 주변 번개 모임 찾기", style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          ),
        ),
        
        // 3. 내 위치로 이동 버튼
        Positioned(
          bottom: 120,
          right: 20,
          child: FloatingActionButton(
            heroTag: "myLocationBtn",
            mini: true,
            backgroundColor: Colors.white,
            onPressed: () {
              if(mapController != null && _currentP != null) {
                mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(_currentP!, 16),
                );
              } else {
                print("위치 정보를 아직 못 찾았어요");
              }
            },
            child: const Icon(Icons.my_location, color: Colors.blue),
          ),
        ),
      ],
    );
  }
}