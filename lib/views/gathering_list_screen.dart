import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'gathering_detail_screen.dart';
import '../models/gathering_model.dart'; 
import '../widgets/meetup_card.dart';

class GatheringListScreen extends StatefulWidget {
  const GatheringListScreen({super.key});

  @override
  State<GatheringListScreen> createState() => _GatheringListScreenState();
}

class _GatheringListScreenState extends State<GatheringListScreen> {
  String _selectedCategory = '전체';
  final List<String> _categories = ['전체', '식사', '운동', '공부', '게임', '산책', '기타'];

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("우리 동네 번개 목록"),
        backgroundColor: Colors.green,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. 상단 카테고리 필터 UI
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: _categories.map((category) {
                  final isSelected = _selectedCategory == category;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(
                        category,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: Colors.green,
                      backgroundColor: Colors.grey[200],
                      showCheckmark: false,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = category;
                          });
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          // 2. 모임 목록 및 AI 맞춤 정렬 레이어
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('meetings')
                  .where('deadline', isGreaterThanOrEqualTo: Timestamp.now())
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('데이터를 불러오는 중 오류가 발생했습니다.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data!.docs;

                // 💡 [AI 매치메이킹 핵심 로직] 유저의 참여 기록을 분석해 최애 카테고리 도출
                String? favoriteCategory;
                if (currentUserId != null && _selectedCategory == '전체') {
                  final Map<String, int> categoryCounts = {};
                  for (var doc in allDocs) {
                    final data = doc.data();
                    final participants = List<String>.from(data['participants'] ?? []);
                    if (participants.contains(currentUserId)) {
                      final cat = data['category'] ?? '기타';
                      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
                    }
                  }
                  if (categoryCounts.isNotEmpty) {
                    // 가장 많이 참여한 카테고리를 1위로 선정
                    favoriteCategory = categoryCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
                  }
                }

                // 💡 카테고리 필터 적용
                var docs = allDocs.where((doc) {
                  if (_selectedCategory == '전체') return true;
                  return doc.data()['category'] == _selectedCategory;
                }).toList();

                // 💡 [AI 정렬 알고리즘] '전체' 탭일 때 유저가 자주 찾는 최애 카테고리 모임을 맨 위로 재배치!
                if (_selectedCategory == '전체' && favoriteCategory != null) {
                  docs.sort((a, b) => (b.data()['category'] == favoriteCategory ? 1 : 0) -
                                     (a.data()['category'] == favoriteCategory ? 1 : 0));
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _selectedCategory == '전체' 
                          ? '현재 모집 중인 번개가 없습니다.\n지도에서 새로운 번개를 열어보세요!'
                          : '아직 모집 중인 [$_selectedCategory] 번개가 없어요.\n첫 번째 모임을 만들어보세요!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54, fontSize: 16),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 💡 [UI 피드백] AI가 취향을 분석했을 때 상단에 친절한 배너 띄워주기
                    if (_selectedCategory == '전체' && favoriteCategory != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.purple[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purple.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome, color: Colors.purple),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'AI 분석: 팀장님이 자주 찾는 [$favoriteCategory] 모임을 상단에 추천해 드려요!',
                                style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 모임 카드 리스트 렌더링
                    ...docs.map((doc) {
                      final data = doc.data();
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
                              builder: (context) => GatheringDetailScreen(gathering: gathering),
                            ),
                          );
                        },
                        child: MeetupCard(meetupData: data),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}