import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'gathering_detail_screen.dart';
import '../models/gathering_model.dart';
import '../widgets/meetup_card.dart';

class GatheringListScreen extends StatefulWidget {
  const GatheringListScreen({super.key});

  @override
  State<GatheringListScreen> createState() => _GatheringListScreenState();
}

class _GatheringListScreenState extends State<GatheringListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _selectedCategory = '전체';
  String _sortMode = '맞춤 추천순';
  final List<String> _categories = const [
    '전체',
    '식사',
    '운동',
    '공부',
    '게임',
    '산책',
    '기타',
  ];

  Position? _currentPosition;
  bool _isLoadingLocation = true;
  DateTime _now = DateTime.now();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();

    // 화면을 열어 둔 상태에서도 마감된 모임이 목록에서 사라지도록 갱신합니다.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });
    } catch (e, stackTrace) {
      debugPrint('[모임 목록] 현재 위치 조회 실패: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double? _readCoordinate(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int _readInt(dynamic value, {required int fallback}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _isActiveMeeting(Map<String, dynamic> data) {
    final DateTime? deadline = _readDateTime(data['deadline']);

    // 마감 시간이 없거나 지난 모임은 현재 모집 중인 목록에서 제외합니다.
    if (deadline == null || !deadline.isAfter(_now)) return false;

    final DateTime? expireAt = _readDateTime(data['expireAt']);
    if (expireAt != null && !expireAt.isAfter(_now)) return false;

    return true;
  }

  double? _calculateDistance(Map<String, dynamic> data) {
    if (_currentPosition == null) return null;

    final double? latitude = _readCoordinate(data['lat']);
    final double? longitude = _readCoordinate(data['lng']);
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        (latitude == 0 && longitude == 0)) {
      return null;
    }

    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      latitude,
      longitude,
    );
  }

  List<String> _readPreferredCategories(Map<String, dynamic>? userData) {
    final dynamic raw = userData?['preferredCategories'];
    if (raw is! List) return <String>[];

    final result = <String>[];
    for (final value in raw) {
      if (value is String &&
          _categories.contains(value) &&
          value != '전체' &&
          !result.contains(value)) {
        result.add(value);
      }
    }
    return result;
  }

  int _calculateRecommendationScore({
    required Map<String, dynamic> data,
    required Map<String, int> categoryParticipationCounts,
    required DateTime deadline,
    required double? distanceMeters,
  }) {
    int score = 0;
    final String category = (data['category'] ?? '기타').toString();

    // 이전에 자주 참여했던 카테고리는 같은 우선순위 안에서 조금 더 추천합니다.
    final int participationCount = (categoryParticipationCounts[category] ?? 0)
        .clamp(0, 3)
        .toInt();
    score += participationCount * 12;

    // 현재 위치와 가까운 모임에 최대 20점을 부여합니다(8km 기준).
    if (distanceMeters != null) {
      final double proximityRatio = (1 - (distanceMeters / 8000))
          .clamp(0.0, 1.0)
          .toDouble();
      score += (proximityRatio * 20).round();
    }

    // 마감이 임박한 모임을 놓치지 않도록 가산합니다.
    final int minutesLeft = deadline.difference(_now).inMinutes;
    if (minutesLeft <= 30) {
      score += 10;
    } else if (minutesLeft <= 120) {
      score += 6;
    } else if (minutesLeft <= 360) {
      score += 2;
    }

    final int currentParticipants = _readInt(
      data['currentParticipants'],
      fallback: data['participants'] is List
          ? (data['participants'] as List).length
          : 0,
    );
    final int maxParticipants = _readInt(data['maxParticipants'], fallback: 4);

    if (currentParticipants < maxParticipants) {
      score += 8;
    } else {
      score -= 20;
    }

    return score;
  }

  void _selectCategory(String category) {
    setState(() => _selectedCategory = category);
  }

  Widget _buildCategorySelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: _categories.map((category) {
            final bool isSelected = _selectedCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  category,
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
                onSelected: (selected) {
                  if (selected) _selectCategory(category);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRecommendationBanner({
    required List<String> preferredCategories,
    required String? favoriteCategory,
    required bool isPersonalizedMode,
  }) {
    late final String message;

    if (!isPersonalizedMode) {
      message = _selectedCategory == '전체'
          ? '모든 카테고리의 모임을 최신 등록순으로 보여드려요.'
          : '[$_selectedCategory] 카테고리 모임을 최신 등록순으로 보여드려요.';
    } else if (_selectedCategory != '전체') {
      final int rank = preferredCategories.indexOf(_selectedCategory);
      message = rank >= 0
          ? '내 관심 ${rank + 1}순위인 [$_selectedCategory] 모임을 보고 있어요.'
          : '[$_selectedCategory] 카테고리 모임을 보고 있어요.';
    } else if (preferredCategories.isNotEmpty) {
      message =
          '내 정보에서 설정한 관심 카테고리만 순위대로 보여드려요.\n${preferredCategories.join('  →  ')}';
    } else if (favoriteCategory != null) {
      message =
          '참여 이력을 바탕으로 [$favoriteCategory] 모임을 먼저 추천해요.\n내 정보에서 관심 카테고리를 설정하면 원하는 모임만 볼 수 있어요.';
    } else {
      message = '내 정보에서 관심 카테고리를 설정하면 원하는 모임만 우선순위대로 볼 수 있어요.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.purple, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.purple,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(List<String> preferredCategories) {
    String message;
    if (_sortMode == '전체 보기' && _selectedCategory == '전체') {
      message = '현재 모집 중인 번개가 없습니다.\n지도에서 새로운 번개를 열어보세요!';
    } else if (_selectedCategory != '전체') {
      message = '아직 모집 중인 [$_selectedCategory] 모임이 없어요.\n다른 카테고리를 선택해 보세요!';
    } else if (preferredCategories.isNotEmpty) {
      message =
          '설정한 관심 카테고리(${preferredCategories.join(', ')})의\n현재 모집 중인 모임이 없습니다.\n내 정보에서 관심 카테고리를 변경할 수 있어요.';
    } else {
      message = '현재 모집 중인 번개가 없습니다.\n지도에서 새로운 번개를 열어보세요!';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildMeetupList({
    required String? currentUserId,
    required Map<String, dynamic>? userData,
  }) {
    final List<String> preferredCategories = _readPreferredCategories(userData);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // 전체 모임을 확인해 선호 카테고리, 참여 이력, 거리 기준으로 정렬합니다.
      stream: _firestore.collection('meetings').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[모임 목록] Firestore 오류: ${snapshot.error}');
          return const Center(child: Text('모임 정보를 불러오지 못했습니다.'));
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.green),
          );
        }

        final allDocs = snapshot.data!.docs;

        // 과거 참여 횟수를 카테고리별로 집계합니다.
        final Map<String, int> categoryParticipationCounts = {};
        if (currentUserId != null) {
          for (final doc in allDocs) {
            final data = doc.data();
            final dynamic rawParticipants = data['participants'];
            final List<dynamic> participants = rawParticipants is List
                ? rawParticipants
                : <dynamic>[];

            if (participants.contains(currentUserId)) {
              final String category = (data['category'] ?? '기타').toString();
              categoryParticipationCounts[category] =
                  (categoryParticipationCounts[category] ?? 0) + 1;
            }
          }
        }

        String? favoriteCategory;
        if (categoryParticipationCounts.isNotEmpty) {
          final rankedCategories = categoryParticipationCounts.entries.toList()
            ..sort((a, b) {
              final int countCompare = b.value.compareTo(a.value);
              if (countCompare != 0) return countCompare;
              return _categories
                  .indexOf(a.key)
                  .compareTo(_categories.indexOf(b.key));
            });
          favoriteCategory = rankedCategories.first.key;
        }

        final bool isSpecificCategorySelected = _selectedCategory != '전체';
        final bool isPersonalizedMode = _sortMode == '맞춤 추천순';
        final Map<String, int> preferredRankByCategory = {
          for (int index = 0; index < preferredCategories.length; index++)
            preferredCategories[index]: index + 1,
        };

        final List<_ScoredMeetup> recommendedMeetups = [];

        for (final doc in allDocs) {
          final Map<String, dynamic> data = doc.data();
          if (!_isActiveMeeting(data)) continue;

          final String category = (data['category'] ?? '기타').toString();

          // 개별 카테고리를 선택하면 해당 카테고리만 표시합니다.
          if (isSpecificCategorySelected && category != _selectedCategory) {
            continue;
          }

          // 맞춤 추천순 + '전체'일 때만 관심 카테고리만 표시합니다.
          // '전체 보기'를 선택하면 선호 카테고리와 관계없이 모든 카테고리를 표시합니다.
          int categoryPriority = 0;
          if (isPersonalizedMode &&
              !isSpecificCategorySelected &&
              preferredCategories.isNotEmpty) {
            categoryPriority = preferredCategories.indexOf(category);
            if (categoryPriority == -1) continue;
          }

          final DateTime deadline = _readDateTime(data['deadline'])!;
          final double? distanceMeters = _calculateDistance(data);
          final int score = _calculateRecommendationScore(
            data: data,
            categoryParticipationCounts: categoryParticipationCounts,
            deadline: deadline,
            distanceMeters: distanceMeters,
          );

          recommendedMeetups.add(
            _ScoredMeetup(
              document: doc,
              score: score,
              categoryPriority: categoryPriority,
              preferredCategoryRank: preferredRankByCategory[category],
              deadline: deadline,
              distanceMeters: distanceMeters,
            ),
          );
        }

        // 정렬 기준:
        // - 맞춤 추천순: 관심 카테고리 우선순위 -> 추천 점수 -> 마감/거리/등록 시간
        // - 전체 보기: 카테고리 제한 없이 모든 모임을 최신 등록순으로 표시
        recommendedMeetups.sort((a, b) {
          final DateTime aCreated =
              _readDateTime(a.document.data()['createdAt']) ?? DateTime(2000);
          final DateTime bCreated =
              _readDateTime(b.document.data()['createdAt']) ?? DateTime(2000);

          if (!isPersonalizedMode) {
            return bCreated.compareTo(aCreated);
          }

          if (!isSpecificCategorySelected && preferredCategories.isNotEmpty) {
            final int categoryCompare = a.categoryPriority.compareTo(
              b.categoryPriority,
            );
            if (categoryCompare != 0) return categoryCompare;
          }

          final int scoreCompare = b.score.compareTo(a.score);
          if (scoreCompare != 0) return scoreCompare;

          final int deadlineCompare = a.deadline.compareTo(b.deadline);
          if (deadlineCompare != 0) return deadlineCompare;

          if (a.distanceMeters != null && b.distanceMeters != null) {
            final int distanceCompare = a.distanceMeters!.compareTo(
              b.distanceMeters!,
            );
            if (distanceCompare != 0) return distanceCompare;
          } else if (a.distanceMeters != null) {
            return -1;
          } else if (b.distanceMeters != null) {
            return 1;
          }

          return bCreated.compareTo(aCreated);
        });

        if (recommendedMeetups.isEmpty) {
          return _buildEmptyState(preferredCategories);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildRecommendationBanner(
              preferredCategories: preferredCategories,
              favoriteCategory: favoriteCategory,
              isPersonalizedMode: isPersonalizedMode,
            ),
            if (_isLoadingLocation)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  '현재 위치를 확인해 가까운 모임을 추천하고 있어요.',
                  style: TextStyle(color: Colors.black45, fontSize: 11),
                ),
              ),
            ...recommendedMeetups.map((item) {
              final Map<String, dynamic> data = item.document.data();
              final Gathering gathering = Gathering(
                title: (data['title'] ?? '제목 없음').toString(),
                location:
                    (data['location'] ??
                            data['dong'] ??
                            data['region'] ??
                            '지도 표시 지점')
                        .toString(),
                date: (data['time'] ?? '시간 미정').toString(),
                description: (data['description'] ?? '지도에서 등록된 번개 모임입니다.')
                    .toString(),
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
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
                  child: MeetupCard(
                    meetupData: data,
                    preferredCategoryRank: item.preferredCategoryRank,
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('우리 동네 번개 목록'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            initialValue: _sortMode,
            onSelected: (value) {
              setState(() => _sortMode = value);
            },
            offset: const Offset(0, 42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: '맞춤 추천순',
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('맞춤 추천순'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: '전체 보기',
                child: Row(
                  children: [
                    Icon(Icons.list, size: 18, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('전체 보기'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _sortMode,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: currentUserId == null
          ? Column(
              children: [
                _buildCategorySelector(),
                const Expanded(
                  child: Center(child: Text('로그인 후 모임 추천을 이용할 수 있습니다.')),
                ),
              ],
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('users')
                  .doc(currentUserId)
                  .snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.hasError) {
                  debugPrint('[모임 목록] 사용자 관심 정보 오류: ${userSnapshot.error}');
                }

                if (!userSnapshot.hasData && !userSnapshot.hasError) {
                  return Column(
                    children: [
                      _buildCategorySelector(),
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.green),
                        ),
                      ),
                    ],
                  );
                }

                final Map<String, dynamic>? userData = userSnapshot.data
                    ?.data();

                return Column(
                  children: [
                    _buildCategorySelector(),
                    Expanded(
                      child: _buildMeetupList(
                        currentUserId: currentUserId,
                        userData: userData,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _ScoredMeetup {
  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final int score;
  final int categoryPriority;
  final int? preferredCategoryRank;
  final DateTime deadline;
  final double? distanceMeters;

  const _ScoredMeetup({
    required this.document,
    required this.score,
    required this.categoryPriority,
    required this.preferredCategoryRank,
    required this.deadline,
    required this.distanceMeters,
  });
}
