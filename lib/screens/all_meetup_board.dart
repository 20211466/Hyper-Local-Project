import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/chat_service.dart';

class AllMeetupBoardScreen extends StatefulWidget {
  @override
  _AllMeetupBoardScreenState createState() => _AllMeetupBoardScreenState();
}

class _AllMeetupBoardScreenState extends State<AllMeetupBoardScreen> {
  final double MAX_DISTANCE_METERS = 8000.0; // 최대 허용 반경 (8km)

  late Stream<QuerySnapshot> _meetupsStream;
  Timer? _expiryRefreshTimer;
  DateTime _now = DateTime.now();

  String _selectedRegion = '전체';
  final List<String> _regions = [
    '전체',
    '서울',
    '경기',
    '인천',
    '강원',
    '충청',
    '전라',
    '경상',
    '제주',
  ];

  String _searchDong = '';
  final TextEditingController _dongSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _meetupsStream = _createMeetupsQuery().snapshots();

    // 화면을 열어 둔 상태에서도 마감 시간이 지나면 목록이 갱신되도록
    // 30초마다 현재 시각을 갱신합니다.
    _expiryRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  // 지역명 표기가 '경기', '경기도', 'Gyeonggi-do', '남양주시'처럼
  // 서로 달라도 앱의 지역 탭 기준으로 분류할 수 있도록 문자열을 정리합니다.
  Query _createMeetupsQuery() {
    // region/dong의 옛날 저장값도 화면에서 분류해야 하므로
    // Firestore에서 region을 정확히 일치시키지 않고 전체 모임을 가져옵니다.
    // 정렬과 지역·동네 검색은 아래에서 앱 쪽에서 처리합니다.
    return FirebaseFirestore.instance.collection('meetings');
  }

  String _compactText(dynamic value) {
    return (value ?? '')
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(',', '')
        .trim();
  }

  String? _regionGroupFromText(String rawValue) {
    final value = _compactText(rawValue);
    if (value.isEmpty) return null;

    if (value.contains('서울') || value.contains('seoul')) return '서울';
    if (value.contains('인천') || value.contains('incheon')) return '인천';
    if (value.contains('강원') || value.contains('gangwon')) return '강원';
    if (value.contains('제주') || value.contains('jeju')) return '제주';

    // 광주광역시는 전라권으로 먼저 분류합니다.
    if (value.contains('광주광역시') ||
        value.contains('전라') ||
        value.contains('전북') ||
        value.contains('전남') ||
        value.contains('jeolla') ||
        value.contains('gwangju')) {
      return '전라';
    }

    if (value.contains('충청') ||
        value.contains('충북') ||
        value.contains('충남') ||
        value.contains('대전') ||
        value.contains('세종') ||
        value.contains('chungcheong') ||
        value.contains('daejeon') ||
        value.contains('sejong')) {
      return '충청';
    }

    if (value.contains('경상') ||
        value.contains('경북') ||
        value.contains('경남') ||
        value.contains('부산') ||
        value.contains('대구') ||
        value.contains('울산') ||
        value.contains('gyeongsang') ||
        value.contains('busan') ||
        value.contains('daegu') ||
        value.contains('ulsan')) {
      return '경상';
    }

    // 경기도 전체 또는 영문 표기
    if (value.contains('경기') || value.contains('gyeonggi')) return '경기';

    // 기존 모임 중 행정구역 필드에 도 이름 대신 시·군 이름만 저장된 경우를 보정합니다.
    const gyeonggiCities = [
      '가평',
      '고양',
      '과천',
      '광명',
      '구리',
      '군포',
      '김포',
      '남양주',
      '동두천',
      '부천',
      '성남',
      '수원',
      '시흥',
      '안산',
      '안성',
      '안양',
      '양주',
      '양평',
      '여주',
      '연천',
      '오산',
      '용인',
      '의왕',
      '의정부',
      '이천',
      '파주',
      '평택',
      '포천',
      '하남',
      '화성',
    ];
    if (gyeonggiCities.any((city) => value.contains(city)) ||
        value.contains('namyangju')) {
      return '경기';
    }

    return null;
  }

  String? _getMeetupRegionGroup(Map<String, dynamic> data) {
    // 지역 필드가 가장 우선이며, 기존 데이터에서 지역 필드에 시·군 이름만
    // 있거나 비어 있는 경우를 대비해 동네·주소 등의 값도 함께 확인합니다.
    final candidates = <dynamic>[
      data['region'],
      data['address'],
      data['location'],
      data['dong'],
      data['district'],
      data['city'],
    ];

    for (final candidate in candidates) {
      final group = _regionGroupFromText((candidate ?? '').toString());
      if (group != null) return group;
    }
    return null;
  }

  bool _matchesRegion(Map<String, dynamic> data) {
    if (_selectedRegion == '전체') return true;
    return _getMeetupRegionGroup(data) == _selectedRegion;
  }

  bool _matchesDongSearch(Map<String, dynamic> data) {
    if (_searchDong.trim().isEmpty) return true;

    final keyword = _compactText(_searchDong);
    final searchableText = _compactText(
      [
        data['dong'],
        data['region'],
        data['address'],
        data['location'],
        data['district'],
        data['city'],
      ].where((value) => value != null).join(' '),
    );

    // 완전 일치가 아니라 포함 여부로 검색해 '남양주', '다산동'처럼
    // 일부만 입력해도 해당 모임이 검색되도록 합니다.
    return searchableText.contains(keyword);
  }

  DateTime? _getMeetupCreatedAt(Map<String, dynamic> data) {
    final value = data['createdAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  DateTime? _getMeetupDeadline(Map<String, dynamic> data) {
    final deadlineValue = data['deadline'];

    if (deadlineValue is Timestamp) {
      return deadlineValue.toDate();
    }
    if (deadlineValue is DateTime) {
      return deadlineValue;
    }
    if (deadlineValue is String) {
      return DateTime.tryParse(deadlineValue);
    }

    // deadline 필드가 없는 기존 데이터는 만료 여부를 판단할 수 없으므로
    // 임의로 숨기지 않습니다.
    return null;
  }

  bool _isMeetupActive(Map<String, dynamic> data, {DateTime? referenceTime}) {
    final deadline = _getMeetupDeadline(data);
    if (deadline == null) return true;

    // 목록 표시와 참가 처리 모두 실제 현재 시각을 기준으로 판단합니다.
    // 버튼이 화면에 남아 있거나 GPS를 가져오는 중 마감되어도 통과하지 않습니다.
    return deadline.isAfter(referenceTime ?? DateTime.now());
  }

  void _showJoinMessage(BuildContext context, String message) {
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _expiryRefreshTimer?.cancel();
    _dongSearchController.dispose();
    super.dispose();
  }

  Future<void> _checkDistanceAndJoin(
    BuildContext context,
    DocumentSnapshot meetupDoc,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showJoinMessage(context, '참가하려면 먼저 로그인해 주세요.');
      return;
    }

    final meetingRef = FirebaseFirestore.instance
        .collection('meetings')
        .doc(meetupDoc.id);

    bool loadingDialogOpen = false;

    void closeLoadingDialog() {
      if (loadingDialogOpen && mounted && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingDialogOpen = false;
      }
    }

    try {
      // 목록에서 전달된 스냅샷은 오래된 값일 수 있으므로 서버에서 다시 읽습니다.
      final latestSnapshot = await meetingRef.get(
        const GetOptions(source: Source.server),
      );

      if (!latestSnapshot.exists) {
        _showJoinMessage(context, '이미 삭제된 모임입니다.');
        return;
      }

      final latestData = latestSnapshot.data() ?? <String, dynamic>{};

      if (!_isMeetupActive(latestData, referenceTime: DateTime.now())) {
        _showJoinMessage(context, '마감 시간이 지난 모임입니다. 참가할 수 없습니다.');
        if (mounted) setState(() => _now = DateTime.now());
        return;
      }

      final initialParticipants = latestData['participants'] is List
          ? List<dynamic>.from(latestData['participants'] as List)
          : <dynamic>[];

      // 모임 생성자는 보통 participants에 이미 포함됩니다.
      // 배열 누락된 기존 데이터도 creatorId로 중복 참가를 막습니다.
      final bool alreadyJoined =
          initialParticipants.contains(user.uid) ||
          latestData['creatorId'] == user.uid;

      if (alreadyJoined) {
        _showJoinMessage(context, '이미 참가한 모임입니다. 중복으로 참가할 수 없습니다.');
        return;
      }

      final initialCurrent =
          (latestData['currentParticipants'] as num?)?.toInt() ??
          initialParticipants.length;
      final initialMax = (latestData['maxParticipants'] as num?)?.toInt() ?? 4;

      if (initialCurrent >= initialMax) {
        _showJoinMessage(context, '모임 정원이 모두 찼습니다.');
        return;
      }

      // 위치 확인 중에도 모임 마감 여부를 마지막에 한 번 더 확인합니다.
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator(color: Colors.green)),
      );
      loadingDialogOpen = true;

      final userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 참가자 중복, 마감, 정원, 거리 검사를 최신 문서 기준으로
      // 한 트랜잭션 안에서 다시 확인하고 실제 참가자 정보를 갱신합니다.
      final result = await FirebaseFirestore.instance
          .runTransaction<Map<String, dynamic>>((transaction) async {
            final freshSnapshot = await transaction.get(meetingRef);

            if (!freshSnapshot.exists) {
              return {'status': 'missing'};
            }

            final data = freshSnapshot.data() ?? <String, dynamic>{};

            if (!_isMeetupActive(data, referenceTime: DateTime.now())) {
              return {'status': 'expired'};
            }

            final rawParticipants = data['participants'];
            final participants = rawParticipants is List
                ? List<dynamic>.from(rawParticipants)
                : <dynamic>[];

            if (participants.contains(user.uid) ||
                data['creatorId'] == user.uid) {
              return {'status': 'already_joined'};
            }

            final currentCount =
                (data['currentParticipants'] as num?)?.toInt() ??
                participants.length;
            final maxCount = (data['maxParticipants'] as num?)?.toInt() ?? 4;

            if (currentCount >= maxCount) {
              return {'status': 'full'};
            }

            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();

            if (lat == null ||
                lng == null ||
                lat < -90 ||
                lat > 90 ||
                lng < -180 ||
                lng > 180 ||
                (lat == 0 && lng == 0)) {
              return {'status': 'invalid_location'};
            }

            final distanceInMeters = Geolocator.distanceBetween(
              userPosition.latitude,
              userPosition.longitude,
              lat,
              lng,
            );

            if (distanceInMeters > MAX_DISTANCE_METERS) {
              return {'status': 'too_far', 'distance': distanceInMeters};
            }

            final updatedParticipants = [...participants, user.uid];
            transaction.update(meetingRef, {
              'participants': updatedParticipants,
              'currentParticipants': currentCount + 1,
            });

            return {'status': 'joined', 'distance': distanceInMeters};
          });

      closeLoadingDialog();

      final status = result['status'];

      if (status == 'missing') {
        _showJoinMessage(context, '이미 삭제된 모임입니다.');
        return;
      }
      if (status == 'expired') {
        _showJoinMessage(context, '마감 시간이 지난 모임입니다. 참가할 수 없습니다.');
        if (mounted) setState(() => _now = DateTime.now());
        return;
      }
      if (status == 'already_joined') {
        _showJoinMessage(context, '이미 참가한 모임입니다. 중복으로 참가할 수 없습니다.');
        return;
      }
      if (status == 'full') {
        _showJoinMessage(context, '모임 정원이 모두 찼습니다.');
        return;
      }
      if (status == 'invalid_location') {
        _showJoinMessage(context, '모임 장소 좌표가 올바르지 않아 참가할 수 없습니다.');
        return;
      }
      if (status == 'too_far') {
        final distanceInMeters = (result['distance'] as num).toDouble();
        if (!mounted || !context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              '📍 참여 불가',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              '현재 위치에서 모임 장소까지 '
              '${(distanceInMeters / 1000).toStringAsFixed(1)}km 떨어져 있습니다.\n\n'
              '동네 번개는 8km 이내에서만 참여 가능해요! '
              '눈으로만 구경해 주세요 👀',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        return;
      }

      if (status == 'joined') {
        // 실제 모임 참가 처리는 위 트랜잭션에서 완료됐습니다.
        // 채팅방 연결이 실패해도 모임 참가 카운트는 중복 증가시키지 않습니다.
        try {
          final updatedSnapshot = await meetingRef.get();
          final updatedData = updatedSnapshot.data() ?? latestData;
          await ChatService().joinRoom(
            meetingId: meetupDoc.id,
            meetingData: updatedData,
          );
          _showJoinMessage(context, '🎉 모임 참가가 완료됐습니다! 채팅방에도 합류했어요.');
        } catch (chatError) {
          debugPrint('채팅방 참가 처리 실패: $chatError');
          _showJoinMessage(context, '🎉 모임 참가가 완료됐습니다. 채팅방 연결은 다시 확인해 주세요.');
        }
      }
    } catch (e) {
      closeLoadingDialog();
      debugPrint('전국 번개 참가 처리 오류: $e');
      _showJoinMessage(context, '참가 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          '🌐 전국 동네 번개 구경하기',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
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
                    label: Text(
                      region,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
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
                          _meetupsStream = _createMeetupsQuery().snapshots();
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
                            _meetupsStream = _createMeetupsQuery().snapshots();
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
                  _meetupsStream = _createMeetupsQuery().snapshots();
                });
              },
            ),
          ),

          // 3. 게시판 리스트
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _meetupsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.green),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 42,
                          ),
                          const SizedBox(height: 12),
                          const Text('모임 목록을 불러오지 못했습니다.'),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => setState(() {
                              _meetupsStream = _createMeetupsQuery()
                                  .snapshots();
                            }),
                            child: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.green),
                  );
                }

                // 마감 시간이 현재 시각보다 이전이거나 같으면 전국 게시판에서 제외합니다.
                final meetups = snapshot.data!.docs;
                final activeMeetups = meetups.where((meetup) {
                  final data = meetup.data() as Map<String, dynamic>? ?? {};
                  return _isMeetupActive(data, referenceTime: _now) &&
                      _matchesRegion(data) &&
                      _matchesDongSearch(data);
                }).toList();

                // createdAt이 누락된 기존 데이터도 포함하고, 날짜가 있는 모임은
                // 최신 순서로 보여줍니다.
                activeMeetups.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>? ?? {};
                  final bData = b.data() as Map<String, dynamic>? ?? {};
                  final aDate = _getMeetupCreatedAt(aData) ?? DateTime(1970);
                  final bDate = _getMeetupCreatedAt(bData) ?? DateTime(1970);
                  return bDate.compareTo(aDate);
                });

                if (activeMeetups.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.explore_off,
                          size: 60,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchDong.isNotEmpty
                              ? "'$_searchDong'에 진행 중인 번개가 없어요!"
                              : '아직 $_selectedRegion 지역에 진행 중인 번개가 없어요!',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: activeMeetups.length,
                  itemBuilder: (context, index) {
                    var meetup = activeMeetups[index];

                    // 💡 [수정됨] DB 데이터 추출 시 에러가 나지 않도록 매우 안전하게 변경
                    final data = meetup.data() as Map<String, dynamic>? ?? {};

                    String title = data['title'] ?? '제목 없음';
                    String category = data['category'] ?? '기타';
                    int currentMembers =
                        (data['currentParticipants'] as num?)?.toInt() ?? 1;
                    int maxMembers =
                        (data['maxParticipants'] as num?)?.toInt() ?? 4;
                    String meetRegion =
                        _getMeetupRegionGroup(data) ??
                        (data['region'] ?? '지역 미상').toString();
                    String meetDong = (data['dong'] ?? '동네 미상').toString();

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green[50],
                            child: Icon(Icons.bolt, color: Colors.green[700]),
                          ),
                          title: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              '📍 $meetRegion $meetDong | $category\n👥 인원: $currentMembers/$maxMembers명',
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                          isThreeLine: true,
                          trailing: ElevatedButton(
                            onPressed: () =>
                                _checkDistanceAndJoin(context, meetup),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
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
