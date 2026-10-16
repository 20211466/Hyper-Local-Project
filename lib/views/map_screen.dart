import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async'; 
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert'; 

import 'package:url_launcher/url_launcher.dart'; // 💡 외부 지도(카카오/네이버) 실행용

import '../models/gathering_model.dart';
import '../services/chat_service.dart';
import '../widgets/meetup_card.dart';
import 'gathering_detail_screen.dart';

import 'package:geocoding/geocoding.dart'; 
import '../screens/all_meetup_board.dart'; 

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  late Stream<QuerySnapshot> _meetingsStream;
  late Stream<QuerySnapshot> _safeZonesStream;

  bool? _hasLocationPermission;
  
  GoogleMapController? mapController;
  Marker? _tempMarker;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isSheetOpen = false;
  LatLng? _currentP;
  double _currentHeading = 0.0;
  StreamSubscription<Position>? _positionStream;
  
  bool _isFirstLocationFetched = false;
  Timer? _debounce;
  BitmapDescriptor? _boltIcon;

  // 🛡️ 안심지킴이집 방패 마커 아이콘 저장 변수
  BitmapDescriptor? _safeZoneIcon;

  final Map<String, BitmapDescriptor> _categoryIcons = {};
  final Map<String, BitmapDescriptor> _urgentCategoryIcons = {};

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
  
  double _currentRadius = 1500.0; 
  String _selectedTransport = '도보'; 

  final List<Map<String, dynamic>> _transportOptions = [
    {'label': '도보', 'icon': Icons.directions_walk, 'radius': 1500.0},
    {'label': '자전거', 'icon': Icons.directions_bike, 'radius': 3000.0},
    {'label': '대중교통', 'icon': Icons.directions_bus, 'radius': 5000.0},
    {'label': '자동차', 'icon': Icons.directions_car, 'radius': 8000.0},
  ];

  void openCreationSheet() {
    LatLng targetPos = _currentP ?? const LatLng(37.9142, 127.1578);
    _showInputSheet(targetPos);
  }

  @override
  void initState() {
    super.initState();

    _meetingsStream = _firestore.collection('meetings').snapshots();
    _safeZonesStream = _firestore.collection('safe_zones').snapshots();

    _loadBoltIcon();
    _loadAllCustomMarkers();
    _loadSafeZoneIcon(); 
    _checkPermissionAndFetchLocation(); 
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _titleController.dispose();
    _noteController.dispose();
    _searchController.dispose();
    _debounce?.cancel(); 
    super.dispose();
  }

  // 🛡️ 안심지킴이집 전용 커스텀 마커(방패 모양) 생성 함수 (크기 축소 버전)
  Future<void> _loadSafeZoneIcon() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 50;

    final Offset center = const Offset(size / 2, size / 2);
    
    final bgPaint = Paint()..color = Colors.blueAccent;
    canvas.drawCircle(center, size / 2.5, bgPaint);

    final borderPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5;
    canvas.drawCircle(center, size / 2.5, borderPaint);

    const IconData safeIcon = Icons.security;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(safeIcon.codePoint),
      style: TextStyle(fontSize: 22, fontFamily: safeIcon.fontFamily, package: safeIcon.fontPackage, color: Colors.white),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2));

    final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    
    if (mounted) {
      setState(() {
        _safeZoneIcon = BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
      });
    }
  }

  Future<BitmapDescriptor> _createCategoryMarker(String category, bool isUrgent) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    
    const double size = 110; 

    IconData categoryIcon = Icons.bolt;
    Color baseColor = Colors.green;
    
    switch (category) {
      case '운동': categoryIcon = Icons.directions_run; baseColor = Colors.blue; break;
      case '식사': categoryIcon = Icons.restaurant; baseColor = Colors.orange; break;
      case '공부': categoryIcon = Icons.menu_book; baseColor = Colors.purple; break;
      case '게임': categoryIcon = Icons.sports_esports; baseColor = Colors.indigo; break;
      case '산책': categoryIcon = Icons.pets; baseColor = Colors.teal; break;
      case '기타': categoryIcon = Icons.bolt; baseColor = Colors.green; break;
    }

    if (isUrgent) {
      baseColor = Colors.redAccent; 
    }

    final double circleRadius = size / 3.5; 
    final Offset circleCenter = const Offset(size / 2, size / 2 + 10);

    final shadowPaint = Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawCircle(circleCenter, circleRadius, shadowPaint);

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(circleCenter, circleRadius, bgPaint);

    final borderPaint = Paint()..color = baseColor..style = PaintingStyle.stroke..strokeWidth = 6.0;
    canvas.drawCircle(circleCenter, circleRadius, borderPaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(categoryIcon.codePoint),
      style: TextStyle(
        fontSize: 28,
        fontFamily: categoryIcon.fontFamily,
        package: categoryIcon.fontPackage,
        color: baseColor,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size - textPainter.width) / 2, (size / 2 + 10) - textPainter.height / 2));

    if (isUrgent) {
      final badgePaint = Paint()..color = Colors.redAccent;
      final Rect badgeRect = Rect.fromCenter(center: const Offset(size / 2, 18), width: 70, height: 26);
      canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(12)), badgePaint);

      final badgeText = TextPainter(textDirection: TextDirection.ltr);
      badgeText.text = const TextSpan(
        text: '마감 임박!', 
        style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)
      );
      badgeText.layout();
      badgeText.paint(canvas, Offset((size - badgeText.width) / 2, 18 - badgeText.height / 2));
    }

    final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<void> _loadAllCustomMarkers() async {
    for (var cat in _categories) {
      _categoryIcons[cat] = await _createCategoryMarker(cat, false);
      _urgentCategoryIcons[cat] = await _createCategoryMarker(cat, true);
    }
    if (mounted) setState(() {});
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

  Future<void> _checkPermissionAndFetchLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _hasLocationPermission = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _hasLocationPermission = false);
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      setState(() => _hasLocationPermission = false);
      return;
    }

    setState(() => _hasLocationPermission = true);

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentP = LatLng(position.latitude, position.longitude);
          _currentHeading = position.heading;
          
          if (!_isFirstLocationFetched && mapController != null) {
            _cameraCenter = _currentP!;
            mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentP!, 13));
            _isFirstLocationFetched = true;
          } else if (mapController == null) {
            _cameraCenter = _currentP!; 
          }
        });
      }
    });
  }

  // 🚨 [핵심 기능] 내 현재 위치에서 가장 가까운 대피소를 찾아 즉시 길안내 실행
  Future<void> _findNearestSafeZoneAndLaunch() async {
    if (_currentP == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('현재 위치를 찾을 수 없습니다.')));
      return;
    }

    // 로딩 다이얼로그
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.red)),
    );

    try {
      QuerySnapshot safeZoneSnapshot = await _firestore.collection('safe_zones').get();
      
      double minDistance = double.infinity;
      Map<String, dynamic>? closestZone;

      // 전체 안심지킴이집 중 현재 내 위치(GPS)와 가장 가까운 곳 1개 찾기
      for (var doc in safeZoneSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        double lat = data['lat'] ?? 0.0;
        double lng = data['lng'] ?? 0.0;
        
        double distance = Geolocator.distanceBetween(_currentP!.latitude, _currentP!.longitude, lat, lng);
        if (distance < minDistance) {
          minDistance = distance;
          closestZone = data;
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // 로딩 닫기

      if (closestZone != null) {
        double destLat = closestZone['lat'];
        double destLng = closestZone['lng'];
        String destName = closestZone['name'] ?? '안심지킴이집';

        // 💡 [디버깅용 꿀팁] 가장 가까운 안심지킴이집 정보를 터미널에 출력합니다!
        print("🚨 [디버그] 가장 가까운 대피소 탐색 완료! 이름: $destName, 거리: ${minDistance.toStringAsFixed(1)}m, 좌표: $destLat,$destLng");

        // 3가지 지도 앱 외부 실행 URL Scheme 구성
        final Uri kakaoMapUrl = Uri.parse('kakaomap://route?ep=$destLat,$destLng&by=WALK');
        final Uri naverMapUrl = Uri.parse('nmap://route/walk?dlat=$destLat&dlng=$destLng&dname=$destName');
        final Uri googleMapUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=walking');

        try {
          // 카카오맵 시도 -> 네이버지도 시도 -> 구글맵 시도
          if (await canLaunchUrl(kakaoMapUrl)) {
            await launchUrl(kakaoMapUrl, mode: LaunchMode.externalApplication);
          } else if (await canLaunchUrl(naverMapUrl)) {
            await launchUrl(naverMapUrl, mode: LaunchMode.externalApplication);
          } else {
            await launchUrl(googleMapUrl, mode: LaunchMode.externalApplication);
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지도 앱을 켤 수 없습니다.')));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('대피소 정보를 불러올 수 없습니다.')));
      }
    }
  }

  Future<void> _polishTextWithAI(Function setSheetState) async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('💡 AI 가이드: 먼저 제목이나 키워드를 간략히 적어주세요!'))
      );
      return;
    }
    
    setSheetState(() => _isAiLoading = true);
    
    try {
      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      );
      
      final prompt = """
      너는 동네 기반 번개 모임 앱의 친절한 AI 매니저야.
      [카테고리] : $_selectedCategory
      [사용자 입력] : ${_titleController.text}${_noteController.text}
      
      규칙:
      1. [중요] 시스템 폰트 오류가 발생하므로 이모지(이모티콘)나 특수기호는 절대 사용하지 말고, 오직 한글과 영문 텍스트로만 매력적인 제목과 상세 설명을 작성해.
      2. 마크다운(` ```json ` 등)이나 부가 설명, 인삿말은 절대 금지. 오직 순수한 JSON 객체 하나만 반환해.
      3. 반드시 아래의 JSON Key 포맷을 정확히 지켜.
      {"title": "여기에 제목", "description": "여기에 설명"}
      """;

      final response = await model.generateContent([Content.text(prompt)]).timeout(
        const Duration(seconds: 10),
      );

      final responseText = response.text;
      if (responseText != null) {
        String cleanJson = responseText.trim();
        if (cleanJson.startsWith('```json')) cleanJson = cleanJson.replaceFirst('```json', '');
        if (cleanJson.startsWith('```')) cleanJson = cleanJson.replaceFirst('```', '');
        if (cleanJson.endsWith('```')) cleanJson = cleanJson.substring(0, cleanJson.length - 3);
        cleanJson = cleanJson.trim();

        final Map<String, dynamic> parsedData = jsonDecode(cleanJson);
        
        if (parsedData.containsKey('title') && parsedData.containsKey('description')) {
          _titleController.text = parsedData['title'];
          _noteController.text = parsedData['description'];
        } else {
           throw const FormatException('JSON Key 불일치');
        }
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏳ AI 서버가 혼잡하여 시간이 초과되었습니다. 직접 작성해주세요!'), 
          backgroundColor: Colors.orange
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 에러 원인: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setSheetState(() => _isAiLoading = false);
      }
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

  void _showListBottomSheet(List<QueryDocumentSnapshot> filteredDocs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
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
                  Expanded(
                    child: filteredDocs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.bolt_rounded, size: 50, color: Colors.green),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "주변에 진행 중인 번개가 없어요!",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "지도를 길게 눌러 첫 번째 번개를 만들어보세요.",
                                  style: TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context); 
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  ),
                                  child: const Text("지도에서 직접 만들기", style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredDocs.length,
                            itemBuilder: (context, index) {
                              final data = filteredDocs[index].data() as Map<String, dynamic>;
                              
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
                                    MaterialPageRoute(
                                      builder: (context) => GatheringDetailScreen(
                                        gathering: gathering,
                                        meetupData: data, 
                                      ),
                                    ),
                                  );
                                },
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
                          if (user == null) return;

                          DocumentSnapshot myDoc = await _firestore.collection('users').doc(user.uid).get();
                          String myMbti = (myDoc.data() as Map<String, dynamic>?)?['mbti'] ?? 'ENFP';
                          
                          String creatorId = data['creatorId'] ?? '';
                          String creatorMbti = 'ISTJ'; 
                          if (creatorId.isNotEmpty) {
                            DocumentSnapshot creatorDoc = await _firestore.collection('users').doc(creatorId).get();
                            creatorMbti = (creatorDoc.data() as Map<String, dynamic>?)?['mbti'] ?? 'ISTJ';
                          }

                          bool isExtremeMatch = (myMbti.startsWith('E') && creatorMbti.startsWith('I')) || 
                                                (myMbti.startsWith('I') && creatorMbti.startsWith('E'));

                          if (!mounted) return;

                          if (isExtremeMatch) {
                            bool? proceed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: const Row(
                                  children: [
                                    Text("🚨 앗, 잠깐만요!", style: TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: Text(
                                  "방장님은 [$creatorMbti]이고\n회원님은 [$myMbti]네요!\n\n텐션이 너무 달라서 기가 빨릴 수도 있는데, 그래도 용기 내서 참여하시겠어요? 😆",
                                  style: const TextStyle(fontSize: 16, height: 1.4),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false), 
                                    child: const Text("다음에 할게요 💦", style: TextStyle(color: Colors.grey)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                    onPressed: () => Navigator.pop(context, true), 
                                    child: const Text("도전할게요! 🔥"),
                                  ),
                                ],
                              ),
                            );

                            if (proceed != true) return;
                          }

                          await _firestore.collection('meetings').doc(docId).update({
                            'currentParticipants': FieldValue.increment(1),
                            'participants': FieldValue.arrayUnion([user.uid]),
                          });
                          final latestDoc = await _firestore.collection('meetings').doc(docId).get();
                          await ChatService().joinRoom(meetingId: docId, meetingData: latestDoc.data() ?? data);
                          
                          if (mounted) {
                            Navigator.pop(context); 
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('🎉 번개 모임에 성공적으로 합류했습니다!')),
                            );
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

  // 🛡️ 인근 안심지킴이집(100m 이내) 확인 함수
  Future<Map<String, dynamic>> _checkNearestSafeZone(double meetupLat, double meetupLng) async {
    try {
      QuerySnapshot safeZoneSnapshot = await FirebaseFirestore.instance.collection('safe_zones').get();
      
      for (var doc in safeZoneSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        double zoneLat = data['lat'] ?? 0.0;
        double zoneLng = data['lng'] ?? 0.0;
        String storeName = data['name'] ?? '안심지킴이집';

        double distanceInMeters = Geolocator.distanceBetween(meetupLat, meetupLng, zoneLat, zoneLng);

        if (distanceInMeters <= 100.0) {
          return {
            'isSafe': true,
            'storeName': storeName,
            'distance': distanceInMeters.toInt(),
          };
        }
      }
    } catch (e) {
      print("안심지킴이집 확인 중 에러: $e");
    }
    return {'isSafe': false, 'storeName': '', 'distance': 0};
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
                      onSelected: (bool selected) { 
                        setSheetState(() { 
                          if (selected && _selectedCategory != category) { 
                            _selectedCategory = category; 
                            _titleController.clear();
                            _noteController.clear();
                            _maxParticipants = 4;
                            _selectedTime = null;
                          } 
                        }); 
                      },
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
                        
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(child: CircularProgressIndicator()),
                          );

                          try {
                          String savedRegion = '전체';
                          String savedDong = '동네 미상';

                          // 💡 주소 변환(Geocoding) 실패 시 앱이 터지지 않도록 예외 처리
                          try {
                            List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
                            if (placemarks.isNotEmpty) {
                              Placemark place = placemarks[0];
                              String adminArea = place.administrativeArea ?? '';
                              
                              if (adminArea.contains('서울')) savedRegion = '서울';
                              else if (adminArea.contains('경기')) savedRegion = '경기';
                              else if (adminArea.contains('인천')) savedRegion = '인천';
                              else if (adminArea.contains('강원')) savedRegion = '강원';
                              else if (adminArea.contains('충청') || adminArea.contains('충북') || adminArea.contains('충남')) savedRegion = '충청';
                              else if (adminArea.contains('전라') || adminArea.contains('전북') || adminArea.contains('전남')) savedRegion = '전라';
                              else if (adminArea.contains('경상') || adminArea.contains('경북') || adminArea.contains('경남')) savedRegion = '경상';
                              else if (adminArea.contains('제주')) savedRegion = '제주';
                              else savedRegion = adminArea;

                              savedDong = place.subLocality ?? place.thoroughfare ?? '동네 미상';
                              if (savedDong.isEmpty) savedDong = '동네 미상';
                            }
                          } catch (geoError) {
                            print("주소 변환 실패(기본값 사용): $geoError");
                          }

                          // 🛡️ 안심지킴이집 거리 검사 수행
                          Map<String, dynamic> safeCheck = await _checkNearestSafeZone(pos.latitude, pos.longitude);

                          final now = DateTime.now();
                          final d = DateTime(now.year, now.month, now.day, _selectedTime!.hour, _selectedTime!.minute);
                          final expireTime = d.add(const Duration(days: 3));
                          final user = FirebaseAuth.instance.currentUser;
                          
                          final meetingData = {
                            'title': _titleController.text, 
                            'category': _selectedCategory, 
                            'description': _noteController.text,
                            'time': _selectedTime!.format(context), 
                            'lat': pos.latitude, 
                            'lng': pos.longitude,
                            'region': savedRegion, 
                            'dong': savedDong,     
                            'isSafeZone': safeCheck['isSafe'],             // 🛡️ 안심 구역 여부
                            'safeZoneName': safeCheck['storeName'],        // 편의점 이름
                            'safeZoneDistance': safeCheck['distance'],     // 거리 (미터)
                            'currentParticipants': 1, 
                            'maxParticipants': _maxParticipants, 
                            'deadline': Timestamp.fromDate(d),
                            'expireAt': Timestamp.fromDate(expireTime), 
                            'creatorId': user?.uid ?? '', 
                            'participants': user != null ? [user.uid] : [],
                            'createdAt': FieldValue.serverTimestamp(),
                          };
                          
                          final meetingRef = await _firestore.collection('meetings').add(meetingData);
                          await ChatService().createRoomForMeeting(meetingId: meetingRef.id, meetingData: meetingData);
                          
                          _titleController.clear(); 
                          _noteController.clear();
                          
                          if (mounted) {
                            Navigator.pop(context); // 로딩 닫기
                            Navigator.pop(context); // 시트 닫기
                          }
                        } catch (e) {
                          Navigator.pop(context); 
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('번개 생성 실패: $e')));
                        }
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

  Widget _buildTransportFilter() {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _transportOptions.length,
        itemBuilder: (context, index) {
          final option = _transportOptions[index];
          final isSelected = _selectedTransport == option['label'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(
                option['icon'], 
                size: 16, 
                color: isSelected ? Colors.white : Colors.green[800]
              ),
              label: Text(
                '${option['label']} ${(option['radius'] / 1000).toInt()}km',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              selected: isSelected,
              selectedColor: Colors.green,
              backgroundColor: Colors.white.withOpacity(0.95),
              elevation: isSelected ? 4 : 1,
              showCheckmark: false, 
              onSelected: (bool selected) {
                if (selected) {
                  setState(() {
                    _selectedTransport = option['label'];
                    _currentRadius = option['radius'];
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasLocationPermission == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    if (_hasLocationPermission == false) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off_rounded, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 20),
              const Text(
                '동네 번개를 찾으려면\n위치 권한이 꼭 필요해요!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                '스마트폰 설정에서 위치 권한을 허용해 주세요.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () => Geolocator.openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('설정으로 이동하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 🛡️ MultiStreamBuilder를 통해 모임 데이터와 안심지킴이집 데이터를 모두 불러옵니다.
    return MultiStreamBuilder(
      streams: [
        _meetingsStream, 
        _safeZonesStream, 
      ],
      builder: (context, snapshots) {
        if (!snapshots[0].hasData || !snapshots[1].hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.green));
        }

        final meetingDocs = snapshots[0].data!.docs;
        final safeZoneDocs = snapshots[1].data!.docs;

        final now = DateTime.now();
        final markers = <Marker>{};
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

        // 🛡️ 안심지킴이집(방패 마커) 상시 노출
        for (var doc in safeZoneDocs) {
          final data = doc.data() as Map<String, dynamic>;
          double lat = data['lat'] ?? 0.0;
          double lng = data['lng'] ?? 0.0;
          if (lat == 0.0 && lng == 0.0) continue;

          // 렌더링 최적화를 위해 현재 반경 + 1km 내에 있는 방패 마커만 띄웁니다.
          double distance = Geolocator.distanceBetween(_cameraCenter.latitude, _cameraCenter.longitude, lat, lng);
          if (distance <= _currentRadius + 1000) { 
            markers.add(
              Marker(
                markerId: MarkerId('safe_${doc.id}'),
                position: LatLng(lat, lng),
                icon: _safeZoneIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                zIndex: 1, // 번개 모임보다 밑에 깔리게 Z축 설정
                infoWindow: InfoWindow(
                  title: '🛡️ ${data['name']}', 
                  snippet: data['address']
                ),
              ),
            );
          }
        }

        // ⚡ 기존 모임(번개) 마커 추가 로직
        for (var doc in meetingDocs) {
          final data = doc.data() as Map<String, dynamic>? ?? {}; 
          final category = data['category'] ?? '기타';
          bool isUrgent = false; 
          
          if (data['deadline'] != null) {
            DateTime deadline = (data['deadline'] as Timestamp).toDate();
            if (now.isAfter(deadline)) continue;

            final diff = deadline.difference(now);
            if (diff.inMinutes <= 10 && diff.inMinutes > 0) {
              isUrgent = true;
            }
          }

          if (_searchQuery.isNotEmpty) {
            final title = (data['title'] ?? '').toString().toLowerCase();
            final description = (data['description'] ?? '').toString().toLowerCase();
            final query = _searchQuery.toLowerCase();
            if (!title.contains(query) && !description.contains(query)) continue; 
          }

          double lat = data['lat'] ?? 0.0;
          double lng = data['lng'] ?? 0.0;
          if (lat == 0.0 && lng == 0.0) continue; 

          double distanceInMeters = Geolocator.distanceBetween(
            _cameraCenter.latitude, _cameraCenter.longitude,
            lat, lng
          );

          if (distanceInMeters > _currentRadius) {
            continue; 
          }

          BitmapDescriptor markerIcon = isUrgent 
              ? (_urgentCategoryIcons[category] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed))
              : (_categoryIcons[category] ?? _boltIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen));

          markers.add(
            Marker(
              markerId: MarkerId(doc.id), position: LatLng(lat, lng),
              icon: markerIcon, 
              zIndex: 10,
              onTap: () => _onMarkerTapped(doc.id, data),
            ),
          );
          filteredDocs.add(doc); 
        }

        return Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _cameraCenter, zoom: 14),
              onMapCreated: (controller) {
                mapController = controller;
                if (_currentP != null && !_isFirstLocationFetched) {
                  mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentP!, 13));
                  _isFirstLocationFetched = true;
                }
              },
              onCameraMove: (CameraPosition position) {
                _cameraCenter = position.target;
                if (_debounce?.isActive ?? false) _debounce!.cancel();
              },
              onCameraIdle: () {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    setState(() {}); 
                  }
                });
              },
              circles: {
                Circle(
                  circleId: const CircleId('search_radius_circle'),
                  center: _cameraCenter,
                  radius: _currentRadius,
                  fillColor: Colors.green.withOpacity(0.1), 
                  strokeColor: Colors.green.withOpacity(0.6), 
                  strokeWidth: 2,
                )
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
              top: 50, left: 0, right: 0, 
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: GestureDetector(
                          onTap: _showSearchDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.white.withOpacity(0.3)),
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
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTransportFilter(),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _searchQuery.isEmpty ? Colors.black.withOpacity(0.6) : Colors.green.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _searchQuery.isEmpty 
                          ? "📍 화면 중심 기준 ${(_currentRadius / 1000).toInt()}km 이내 번개" 
                          : "🔍 '$_searchQuery' 검색 결과 (화면 중심 ${(_currentRadius / 1000).toInt()}km)",
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              bottom: 180, right: 20,
              child: FloatingActionButton.extended(
                heroTag: "allBoardBtn", 
                backgroundColor: Colors.white,
                elevation: 4,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AllMeetupBoardScreen()),
                  );
                },
                icon: const Icon(Icons.explore, color: Colors.green),
                label: const Text("전국 번개 구경", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ),

            Positioned(
              bottom: 110, right: 20,
              child: FloatingActionButton(
                heroTag: "myLocationBtn", mini: true, backgroundColor: Colors.white,
                onPressed: () {
                  if (mapController != null && _currentP != null) {
                    mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentP!, 13));
                  }
                },
                child: const Icon(Icons.my_location, color: Colors.blue),
              ),
            ),

            // 🚨 [추가] 지도 홈 화면의 '긴급 대피' SOS 버튼 (좌측 하단)
            Positioned(
              bottom: 110, left: 20,
              child: FloatingActionButton.extended(
                heroTag: "emergencySosBtn",
                backgroundColor: Colors.red[700], // 긴급 상황을 알리는 짙은 빨간색
                elevation: 6,
                icon: const Icon(Icons.directions_run, color: Colors.white),
                label: const Text("긴급 대피", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () {
                  // 버튼 누르면 '정말 대피하시겠습니까?' 묻지 않고 1초라도 아끼기 위해 즉시 길안내 실행!
                  _findNearestSafeZoneAndLaunch();
                },
              ),
            ),

            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75), 
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _showListBottomSheet(filteredDocs),
                        icon: const Icon(Icons.location_on, color: Colors.white, size: 20),
                        label: Text(
                          '📍 내 주변 번개 (${filteredDocs.length})', 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent, 
                          shadowColor: Colors.transparent, 
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ),
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

// 🛡️ 여러 개의 Firestore Stream을 동시에 관리해주는 유틸리티 위젯
class MultiStreamBuilder extends StatelessWidget {
  final List<Stream<QuerySnapshot>> streams;
  final Widget Function(BuildContext, List<AsyncSnapshot<QuerySnapshot>>) builder;

  const MultiStreamBuilder({
    Key? key,
    required this.streams,
    required this.builder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _buildMultiStream(context, streams, []);
  }

  Widget _buildMultiStream(
      BuildContext context,
      List<Stream<QuerySnapshot>> remainingStreams,
      List<AsyncSnapshot<QuerySnapshot>> resolvedSnapshots) {
    if (remainingStreams.isEmpty) {
      return builder(context, resolvedSnapshots);
    }
    return StreamBuilder<QuerySnapshot>(
      stream: remainingStreams.first,
      builder: (context, snapshot) {
        return _buildMultiStream(
          context,
          remainingStreams.sublist(1),
          [...resolvedSnapshots, snapshot],
        );
      },
    );
  }
}