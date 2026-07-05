import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import '../models/meetup.dart'; // 💡 더 이상 중간 변환 모델이 필요 없으므로 삭제/주석 처리해도 됩니다.
import '../services/auth_service.dart';
import '../widgets/meetup_card.dart';

class MyMeetupsScreen extends StatelessWidget {
  const MyMeetupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인이 필요합니다.')),
      );
    }
    final authService = AuthService();
    final firestore = FirebaseFirestore.instance;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('내 정보'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '로그아웃',
              onPressed: () => authService.signOut(),
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.green,
            tabs: [
              Tab(text: '내가 만든 모임'),
              Tab(text: '참여한 모임'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.green[50],
                    backgroundImage: user.photoURL != null
                        ? NetworkImage(user.photoURL!)
                        : null,
                    child: user.photoURL == null
                        ? const Icon(Icons.person, color: Colors.green, size: 28)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName?.isNotEmpty == true
                              ? user.displayName!
                              : '닉네임 없음',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email ?? '',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _MeetupStreamList(
                    stream: firestore
                        .collection('meetings')
                        .where('creatorId', isEqualTo: user.uid)
                        .snapshots(),
                    emptyMessage: '아직 만든 번개 모임이 없어요.\n지도에서 새로운 번개를 열어보세요!',
                  ),
                  _MeetupStreamList(
                    stream: firestore
                        .collection('meetings')
                        .where('participants', arrayContains: user.uid)
                        .snapshots(),
                    emptyMessage: '아직 참여한 번개 모임이 없어요.\n지도에서 마음에 드는 번개에 참여해보세요!',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetupStreamList extends StatelessWidget {
  // 💡 타입을 <Map<String, dynamic>>으로 명확하게 지정해서 에러를 원천 차단합니다.
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String emptyMessage;

  const _MeetupStreamList({required this.stream, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            // 💡 복잡한 모델 변환 없이 파이어베이스 데이터를 바로 꺼냅니다.
            final data = docs[index].data();
            
            // 💡 업그레이드된 MeetupCard에 맞게 meetupData 파라미터로 전달합니다!
            return MeetupCard(meetupData: data);
          },
        );
      },
    );
  }
}