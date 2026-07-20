import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/gathering_model.dart';
import '../services/chat_service.dart';

// 💡 리스트 형태 UI를 위해 기존에 만든 위젯과 화면을 불러옵니다.
import '../widgets/meetup_card.dart';
import 'gathering_detail_screen.dart';

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

  bool _isAiLoading = false;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  LatLng _cameraCenter = const LatLng(37.9142, 127.1578); 
  final double _searchRadius = 5000; 

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
    _searchController.dispose();
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
          if (mapController == null) _cameraCenter = _currentP!; 
        });
      }
    });
  }

  Future<void> _polishTextWithAI(Function setSheetState) async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 가이드: 먼저 제목이나 키워드를 간략히 적어주세요!')));
      return;
    }
    setSheetState(() => _isAiLoading = true);
    try {
      final model = GenerativeModel(
        model: 'gemini-3-flash-preview',
        apiKey: 'YOUR_GEMINI_API_KEY_HERE', 
      );
      final prompt = """
      너는 동네 기반 번개 모임 앱의 친절한 AI 매니저야.
      [카테고리] : $_selectedCategory
      [사용자 입력] : ${_titleController.text} ${_noteController.text}
      반드시 아래 JSON 형식으로만 응답해줘. 군더더기 말은 하지마.
      {"title": "이모지 포함 제목", "description": "친절한 설명"}
      """;
      final response = await model.generateContent([Content.text(prompt)]);
      final responseText = response.text;
      if (responseText != null) {
        String cleanJson = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
        int titleStart = cleanJson.indexOf('"title": "') + 10;
        int titleEnd = cleanJson.indexOf('",', titleStart);
        int descStart = cleanJson.indexOf('"description": "') + 16;
        int descEnd = cleanJson.lastIndexOf('"');
        if (titleStart > 9 && titleEnd > 0 && descStart > 15 && descEnd > 0) {
          _titleController.text = cleanJson.substring(titleStart, titleEnd);
          _noteController.text = cleanJson.substring(descStart, descEnd).replaceAll('\\n', '\n');
        }
      }
    } catch (e) {
      print("AI 에러: $e");
    } finally {
      setSheetState(() => _isAiLoading = false);
    }
  }

  void _executeSearch(String query) {
    setState(() => _searchQuery = query);
    Navigator.pop(context); 
    
    if (query.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🔍 '$query' 검색 결과를 지도에 표시합니다.", style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('번개 모임 검색', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '검색할 키워드 (예: 피시방, 식사 등)',
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.search, color: Colors.green),
          ),
          onSubmitted: (value) => _executeSearch(value.trim()),
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() { _searchQuery = ''; _searchController.clear(); });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("검색 필터를 해제했습니다."), duration: Duration(seconds: 1)),
                );
              },
              child: const Text('검색 초기화', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => _executeSearch(_searchController.text.trim()),
            child: const Text('검색'),
          ),
        ],
      ),
    );
  }

  // 💡 [새로운 핵심 기능] 현재 필터링된 모임들을 리스트업 해주는 팝업창!
  void _showListBottomSheet(List<QueryDocumentSnapshot> filteredDocs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6, // 처음 올라오는 높이 (60%)
          minChildSize: 0.4,
          maxChildSize: 0.9, // 위로 끝까지 올리면 90%까지 확장
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // 손잡이 아이콘
                  Container(
                    width: 40, height: 5,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _searchQuery.isEmpty ? "내 주변 번개 모임" : "'$_searchQuery' 검색 결과",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "총 ${filteredDocs.length}건",
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 리스트뷰 영역
                  Expanded(
                    child: filteredDocs.isEmpty
                        ? const Center(child: Text("조건에 맞는 번개가 없어요 🥲", style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            controller: controller,
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredDocs.length,
                            itemBuilder: (context, index) {
                              final data = filteredDocs[index].data() as Map<String, dynamic>;
                              final docId = filteredDocs[index].id;
                              
                              // GatheringDetailScreen으로 넘기기 위해 데이터 변환
                              final gathering = Gathering(
                                title: data['title'] ?? '제목 없음',
                                location: data['location'] ?? "지도 표시 지점",
                                date: data['time'] ?? '시간 미정',
                                description: data['description'] ?? "지도에서 등록된 번개 모임입니다.",
                              );

                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => GatheringDetailScreen(gathering: gathering)),
                                  );
                                },
                                // 기존에 만들어둔 MeetupCard 컴포넌트를 그대로 재활용!
                                child: MeetupCard(meetupData: data),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _onMarkerTapped(String docId, Map<String, dynamic> data) {
    setState(() => _isSheetOpen = true);
    int current = data['currentParticipants'] ?? 1;
    int max = data['maxParticipants'] ?? 4;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
              child: Text(data['category'] ?? '기타', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(height: 10),
            Text(data['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 10),
            Text(data['description'] ?? '상세 설명이 없습니다.', style: const TextStyle(fontSize: 16, color: Colors.black54, height: 1.4)),
            const Divider(height: 40, thickness: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.people_outline, color: Colors.grey, size: 20), SizedBox(width: 6),
                    Text("참여 인원", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Text("$current / $max 명", style: TextStyle(color: current >= max ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: current / max, backgroundColor: Colors.grey[100], color: current >= max ? Colors.redAccent : Colors.green, minHeight: 12,
              ),
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.orange, size: 18), const SizedBox(width: 6),
                Text("⏰ 오늘 ${data['time']} 까지 모여요!", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                onPressed: current < max
                    ? () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          await _firestore.collection('meetings').doc(docId).update({
                            'currentParticipants': FieldValue.increment(1),
                            'participants': FieldValue.arrayUnion([user.uid]),
                          });
                          final latestDoc = await _firestore.collection('meetings').doc(docId).get();
                          await ChatService().joinRoom(meetingId: docId, meetingData: latestDoc.data() ?? data);
                          if (mounted) Navigator.pop(context);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: current < max ? Colors.amber[400] : Colors.grey[300],
                  foregroundColor: Colors.black87, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(current < max ? "⚡ 이 번개 참여하기" : "아쉽지만 인원이 꽉 찼어요", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    ).then((_) => setState(() => _isSheetOpen = false));
  }

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: Text('⚡ 새로운 번개 만들기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                const SizedBox(height: 20),
                const Text('어떤 모임인가요?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: _categories.map((category) {
                    return ChoiceChip(
                      label: Text(category), selected: _selectedCategory == category, selectedColor: Colors.green[200],
                      onSelected: (bool selected) { setSheetState(() { if (selected) _selectedCategory = category; }); },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 15),
                TextField(controller: _titleController, decoration: const InputDecoration(labelText: '제목 또는 핵심 키워드')),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _isAiLoading ? null : () => _polishTextWithAI(setSheetState),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.purple, side: const BorderSide(color: Colors.purple, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: _isAiLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple)) : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(_isAiLoading ? 'AI 작성 중...' : 'AI 문장 다듬기 🪄', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                TextField(controller: _noteController, maxLines: 3, decoration: const InputDecoration(labelText: '상세 설명')),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("모집 정원: $_maxParticipants 명", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        IconButton(onPressed: () => setSheetState(() { if (_maxParticipants > 2) _maxParticipants--; }), icon: const Icon(Icons.remove_circle_outline, color: Colors.red)),
                        IconButton(onPressed: () => setSheetState(() { if (_maxParticipants < 20) _maxParticipants++; }), icon: const Icon(Icons.add_circle_outline, color: Colors.green)),
                      ],
                    ),
                  ],
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_selectedTime == null ? "마감 시간 선택" : "마감: ${_selectedTime!.format(context)}"),
                  trailing: const Icon(Icons.access_time, color: Colors.green),
                  onTap: () async {
                    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (picked != null) setSheetState(() => _selectedTime = picked);
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_titleController.text.isNotEmpty && _selectedTime != null) {
                        final now = DateTime.now();
                        final d = DateTime(now.year, now.month, now.day, _selectedTime!.hour, _selectedTime!.minute);
                        final expireTime = d.add(const Duration(days: 3));
                        final user = FirebaseAuth.instance.currentUser;
                        final meetingData = {
                          'title': _titleController.text, 'category': _selectedCategory, 'description': _noteController.text,
                          'time': _selectedTime!.format(context), 'lat': pos.latitude, 'lng': pos.longitude,
                          'currentParticipants': 1, 'maxParticipants': _maxParticipants, 'deadline': Timestamp.fromDate(d),
                          'expireAt': Timestamp.fromDate(expireTime), 'creatorId': user?.uid ?? '', 'participants': user != null ? [user.uid] : [],
                        };
                        final meetingRef = await _firestore.collection('meetings').add(meetingData);
                        await ChatService().createRoomForMeeting(meetingId: meetingRef.id, meetingData: meetingData);
                        _titleController.clear(); _noteController.clear();
                        if (mounted) Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("번개 생성", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
    setState(() { _isSheetOpen = false; _tempMarker = null; });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('meetings').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final now = DateTime.now();
        final markers = <Marker>{};
        
        // 💡 화면 안의 필터링된 모임 문서들을 저장할 리스트
        final List<QueryDocumentSnapshot> filteredDocs = []; 

        if (_currentP != null) {
          markers.add(
            Marker(
              markerId: const MarkerId("me"), position: _currentP!,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              rotation: _currentHeading, anchor: const Offset(0.5, 0.5), zIndex: 5,
            ),
          );
        }

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          
          if (data['deadline'] != null) {
            DateTime deadline = (data['deadline'] as Timestamp).toDate();
            if (now.isAfter(deadline)) continue;
          }

          if (_searchQuery.isNotEmpty) {
            final title = (data['title'] ?? '').toString().toLowerCase();
            final description = (data['description'] ?? '').toString().toLowerCase();
            final query = _searchQuery.toLowerCase();
            if (!title.contains(query) && !description.contains(query)) continue; 
          }

          double distanceInMeters = Geolocator.distanceBetween(
            _cameraCenter.latitude, _cameraCenter.longitude,
            data['lat'], data['lng']
          );

          if (distanceInMeters > _searchRadius) {
            continue; 
          }

          // 모든 필터를 통과한 모임만 마커로 찍고, 리스트에도 추가!
          markers.add(
            Marker(
              markerId: MarkerId(doc.id), position: LatLng(data['lat'], data['lng']),
              icon: _boltIcon ?? BitmapDescriptor.defaultMarker,
              onTap: () => _onMarkerTapped(doc.id, data),
            ),
          );
          filteredDocs.add(doc); 
        }

        // 전체 화면 레이아웃 반환 (GoogleMap + UI 요소들)
        return Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _cameraCenter, zoom: 14),
              onMapCreated: (controller) => mapController = controller,
              onCameraMove: (CameraPosition position) {
                _cameraCenter = position.target;
              },
              onCameraIdle: () {
                setState(() {}); 
              },
              markers: {...markers, if (_tempMarker != null) _tempMarker!},
              onLongPress: (LatLng tappedPoint) {
                setState(() => _tempMarker = Marker(markerId: const MarkerId("temp"), position: tappedPoint, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)));
                _showInputSheet(tappedPoint);
              },
              scrollGesturesEnabled: !_isSheetOpen,
              myLocationEnabled: true, myLocationButtonEnabled: true,
              zoomControlsEnabled: true, mapToolbarEnabled: false, compassEnabled: true,
            ),

            Positioned(
              top: 50, left: 20, right: 20,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _showSearchDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(30),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _searchQuery.isEmpty ? "동네 주변 번개 모임 찾기" : "검색어: '$_searchQuery'",
                              style: TextStyle(color: _searchQuery.isEmpty ? Colors.grey : Colors.green[800], fontWeight: _searchQuery.isEmpty ? FontWeight.normal : FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty) 
                            GestureDetector(
                              onTap: () {
                                setState(() { _searchQuery = ''; _searchController.clear(); });
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("검색 필터를 해제했습니다."), duration: Duration(seconds: 1)));
                              },
                              child: const Icon(Icons.cancel, color: Colors.grey, size: 20),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _searchQuery.isEmpty ? Colors.black.withOpacity(0.6) : Colors.green.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _searchQuery.isEmpty 
                          ? "📍 화면 중심 기준 5km 이내 번개" 
                          : "🔍 '$_searchQuery' 검색 결과 (화면 중심 5km)",
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              bottom: 120, right: 20,
              child: FloatingActionButton(
                heroTag: "myLocationBtn", mini: true, backgroundColor: Colors.white,
                onPressed: () {
                  if (mapController != null && _currentP != null) {
                    mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentP!, 16));
                  }
                },
                child: const Icon(Icons.my_location, color: Colors.blue),
              ),
            ),

            // 💡 [새로 추가된 하단 중앙 '목록 보기' 버튼]
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () => _showListBottomSheet(filteredDocs),
                  icon: const Icon(Icons.list, color: Colors.white, size: 20),
                  label: Text(
                    '목록 보기 (${filteredDocs.length})', 
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 6,
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