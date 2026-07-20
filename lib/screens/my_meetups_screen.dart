import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
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
                    backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                    child: user.photoURL == null ? const Icon(Icons.person, color: Colors.green, size: 28) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName?.isNotEmpty == true ? user.displayName! : '닉네임 없음',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(user.email ?? '', style: const TextStyle(color: Colors.black54)),
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
                    // 💡 방장인 모임 검색 (조건 1개라 에러 없음)
                    stream: firestore.collection('meetings').where('creatorId', isEqualTo: user.uid).snapshots(),
                    emptyMessage: '아직 만든 번개 모임이 없어요.\n지도에서 새로운 번개를 열어보세요!',
                    isCreatorMode: true, 
                  ),
                  _MeetupStreamList(
                    // 💡 참여자인 모임 검색 (DB에선 참여자만 찾고, 내가 방장인지는 앱에서 필터링하여 인덱스 에러 원천 차단!)
                    stream: firestore.collection('meetings').where('participants', arrayContains: user.uid).snapshots(),
                    emptyMessage: '아직 참여한 번개 모임이 없어요.\n지도에서 마음에 드는 번개에 참여해보세요!',
                    isCreatorMode: false,
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
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String emptyMessage;
  final bool isCreatorMode;

  const _MeetupStreamList({
    required this.stream, 
    required this.emptyMessage,
    required this.isCreatorMode,
  });

  Future<void> _handleDeleteOrLeave(BuildContext context, String docId, Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      if (isCreatorMode) {
        await FirebaseFirestore.instance.collection('meetings').doc(docId).delete();
        await ChatService().leaveRoom(docId); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('종료된 모임을 삭제했습니다.')));
      } else {
        await FirebaseFirestore.instance.collection('meetings').doc(docId).update({
          'participants': FieldValue.arrayRemove([uid]),
          'currentParticipants': FieldValue.increment(-1),
        });
        await ChatService().leaveRoom(docId);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('종료된 모임에서 나갔습니다.')));
      }
    } catch (e) {
      print("삭제 오류: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('처리 중 오류가 발생했습니다.')));
    }
  }

  void _showDeleteDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCreatorMode ? '모임 삭제' : '모임 기록 삭제'),
        content: Text(isCreatorMode 
            ? '이 모임 데이터를 완전히 삭제하시겠습니까?\n(채팅방 목록에서도 사라집니다.)' 
            : '이 모임의 참여 기록과 채팅방을 내 목록에서 지우시겠습니까?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleDeleteOrLeave(context, docId, data);
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data!.docs;

        // 💡 [클라이언트 필터링 핵심 로직] 
        // 참여한 모임 탭(isCreatorMode == false)일 때, 방장이 '나'인 문서는 리스트에서 제외합니다.
        final docs = isCreatorMode 
            ? allDocs 
            : allDocs.where((doc) => doc.data()['creatorId'] != uid).toList();

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

        final now = DateTime.now();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final docId = docs[index].id;
            
            bool isExpired = false;
            if (data['deadline'] != null) {
              final deadline = (data['deadline'] as Timestamp).toDate();
              if (now.isAfter(deadline)) {
                isExpired = true;
              }
            }

            return Stack(
              children: [
                MeetupCard(meetupData: data),
                if (isExpired)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _showDeleteDialog(context, docId, data),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}