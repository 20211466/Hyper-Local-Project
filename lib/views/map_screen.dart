import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
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
  
  // 🚀 인원 설정 변수 복구
  int _maxParticipants = 4; 
  final List<String> _categories = ['운동', '식사', '공부', '게임', '산책', '기타'];

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

  // 🚀 [참여하기 창] 현재 인원 / 제한 인원 시각화
  void _onMarkerTapped(String docId, Map<String, dynamic> data) {
    setState(() => _isSheetOpen = true);
    int current = data['currentParticipants'] ?? 1;
    int max = data['maxParticipants'] ?? 4;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['title'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(data['description'] ?? '', style: const TextStyle(fontSize: 16)),
            const Divider(height: 30),
            
            // 🚀 인원수 표시 및 상태 바 추가
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("참여 현황", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("$current / $max 명", style: TextStyle(
                  color: current >= max ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                )),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: current / max,
              backgroundColor: Colors.grey[200],
              color: current >= max ? Colors.red : Colors.green,
              minHeight: 10,
            ),
            
            const SizedBox(height: 20),
            Text("⏰ 마감 시간: ${data['time']}", style: const TextStyle(color: Colors.orange)),
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                onPressed: current < max ? () async {
                  await _firestore.collection('meetings').doc(docId).update({'currentParticipants': FieldValue.increment(1)});
                  if (mounted) Navigator.pop(context);
                } : null, // 인원 가득 차면 비활성화
                style: ElevatedButton.styleFrom(
                  backgroundColor: current < max ? Colors.amber : Colors.grey,
                ),
                child: Text(current < max ? "참여하기" : "인원 초과"),
              ),
            ),
          ],
        ),
      ),
    ).then((_) => setState(() => _isSheetOpen = false));
  }

  // 🚀 [모임 생성 창] 인원 설정 기능 복구
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
                
                // 🚀 인원 설정 UI 복구
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
                        'currentParticipants': 1, // 방장은 기본 1명
                        'maxParticipants': _maxParticipants, // 설정한 인원 저장
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
    setState(() => _isSheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Hyper-Local 번개 모임"), backgroundColor: Colors.green, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
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
            markers: markers,
            onLongPress: _showInputSheet,
            scrollGesturesEnabled: !_isSheetOpen,
          );
        },
      ),
    );
  }
}