import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class AllMeetupBoardScreen extends StatefulWidget {
  @override
  _AllMeetupBoardScreenState createState() => _AllMeetupBoardScreenState();
}

class _AllMeetupBoardScreenState extends State<AllMeetupBoardScreen> {
  final double MAX_DISTANCE_METERS = 8000.0; // 최대 허용 반경 (8km)
  
  String _selectedRegion = '전체'; 
  final List<String> _regions = ['전체', '서울', '경기', '인천', '강원', '충청', '전라', '경상', '제주'];

  String _searchDong = ''; 
  final TextEditingController _dongSearchController = TextEditingController();

  Future<void> _checkDistanceAndJoin(BuildContext context, DocumentSnapshot meetupDoc) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      Position userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 💡 [수정됨] location 필드가 없는 옛날 데이터에서도 에러가 안나게 처리
      final data = meetupDoc.data() as Map<String, dynamic>? ?? {};
      double lat = data['lat'] ?? 0.0;
      double lng = data['lng'] ?? 0.0;

      double distanceInMeters = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        lat,
        lng,
      );

      Navigator.pop(context); 

      if (distanceInMeters <= MAX_DISTANCE_METERS) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('참가 성공! ${(distanceInMeters / 1000).toStringAsFixed(1)}km 거리에 있습니다.')),
        );
        // TODO: 채팅방 이동 로직 연동
      } else {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('📍 참여 불가', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Text('현재 위치에서 모임 장소까지 ${(distanceInMeters / 1000).toStringAsFixed(1)}km 떨어져 있습니다.\n\n동네 번개는 8km 이내에서만 참여 가능해요! 눈으로만 구경해 주세요 👀'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치 정보를 가져오는데 실패했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance.collection('meetings').orderBy('createdAt', descending: true);
    
    if (_selectedRegion != '전체') {
      query = query.where('region', isEqualTo: _selectedRegion);
    }
    
    if (_searchDong.isNotEmpty) {
      query = query.where('dong', isEqualTo: _searchDong);
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('🌐 전국 동네 번개 구경하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. 큰 지역 선택 가로 스크롤
          Container(
            height: 50,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _regions.length,
              itemBuilder: (context, index) {
                final region = _regions[index];
                final isSelected = _selectedRegion == region;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(region, style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    )),
                    selected: isSelected,
                    selectedColor: Colors.green,
                    backgroundColor: Colors.grey[200],
                    showCheckmark: false,
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() {
                          _selectedRegion = region;
                          _searchDong = ''; 
                          _dongSearchController.clear();
                        });
                      }
                    },
                  ),
                );
              },
            ),
          ),
          
          // 2. 세부 동네 검색 바
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _dongSearchController,
              decoration: InputDecoration(
                hintText: '특정 동네 이름으로 찾기 (예: 역삼동)',
                prefixIcon: const Icon(Icons.search, color: Colors.green),
                suffixIcon: _searchDong.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.grey),
                      onPressed: () {
                        setState(() {
                          _searchDong = '';
                          _dongSearchController.clear();
                        });
                      },
                    )
                  : null,
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (value) {
                setState(() {
                  _searchDong = value.trim();
                  if (_searchDong.isNotEmpty) _selectedRegion = '전체'; 
                });
              },
            ),
          ),

          // 3. 게시판 리스트
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.green));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.explore_off, size: 60, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          _searchDong.isNotEmpty 
                            ? "'$_searchDong'에 생성된 번개가 없어요!" 
                            : '아직 $_selectedRegion 지역에 생성된 번개가 없어요!', 
                          style: const TextStyle(color: Colors.grey, fontSize: 16)
                        ),
                      ],
                    ),
                  );
                }

                final meetups = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: meetups.length,
                  itemBuilder: (context, index) {
                    var meetup = meetups[index];
                    
                    // 💡 [수정됨] DB 데이터 추출 시 에러가 나지 않도록 매우 안전하게 변경
                    final data = meetup.data() as Map<String, dynamic>? ?? {};
                    
                    String title = data['title'] ?? '제목 없음';
                    String category = data['category'] ?? '기타';
                    int currentMembers = data['currentParticipants'] ?? 1;
                    int maxMembers = data['maxParticipants'] ?? 4;
                    String meetRegion = data['region'] ?? '지역 미상'; 
                    String meetDong = data['dong'] ?? '동네 미상'; 

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green[50],
                            child: Icon(Icons.bolt, color: Colors.green[700]),
                          ),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              '📍 $meetRegion $meetDong | $category\n👥 인원: $currentMembers/$maxMembers명', 
                              style: const TextStyle(height: 1.4)
                            ),
                          ),
                          isThreeLine: true,
                          trailing: ElevatedButton(
                            onPressed: () => _checkDistanceAndJoin(context, meetup),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('참가 확인'),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}