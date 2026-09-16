import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../widgets/meetup_card.dart';
import '../widgets/manner_volt_dialog.dart'; 

class MyMeetupsScreen extends StatefulWidget {
  const MyMeetupsScreen({super.key});

  @override
  State<MyMeetupsScreen> createState() => _MyMeetupsScreenState();
}

class _MyMeetupsScreenState extends State<MyMeetupsScreen> {
  
  Widget _buildBadge(String text, MaterialColor color) {
    if (text == '비공개') return const SizedBox.shrink(); 
    return Container(
      margin: const EdgeInsets.only(top: 6, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color[200]!),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color[700]),
      ),
    );
  }

  Widget _buildMannerVoltBadge(int volt) {
    String emoji;
    String title;
    MaterialColor color;

    if (volt < 30) {
      emoji = '🔋'; title = '정전기'; color = Colors.grey;
    } else if (volt < 100) {
      emoji = '💡'; title = '꼬마전구'; color = Colors.amber;
    } else if (volt < 300) {
      emoji = '⚡'; title = '에너자이저'; color = Colors.green;
    } else {
      emoji = '👑'; title = '인간 발전소'; color = Colors.purple;
    }

    return Container(
      margin: const EdgeInsets.only(top: 6, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color[300]!, width: 1.5),
        boxShadow: volt >= 300 
            ? [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '$volt V ($title)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color[800]),
          ),
        ],
      ),
    );
  }

  void _showProfilePicker(BuildContext context, User user) {
    final List<String> defaultAvatars = [
      'https://api.dicebear.com/8.x/micah/png?seed=Felix&backgroundColor=f4d150',
      'https://api.dicebear.com/8.x/micah/png?seed=Aneka&backgroundColor=b6e3f4',
      'https://api.dicebear.com/8.x/micah/png?seed=Tinkerbell&backgroundColor=c0aede',
      'https://api.dicebear.com/8.x/avataaars/png?seed=Boo&backgroundColor=d1d4f9',
      'https://api.dicebear.com/8.x/avataaars/png?seed=Max&backgroundColor=ffdfbf',
      'https://api.dicebear.com/8.x/avataaars/png?seed=Lola&backgroundColor=b6e3f4',
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('프로필 아바타 선택', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: defaultAvatars.length,
              itemBuilder: (context, index) {
                final avatarUrl = defaultAvatars[index];
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    await user.updatePhotoURL(avatarUrl);
                    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                      'photoUrl': avatarUrl,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('프로필이 변경되었습니다! ✨')));
                      setState(() {}); 
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    ),
                    child: ClipOval(child: Image.network(avatarUrl, fit: BoxFit.cover)),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  // 💡 [새로운 기능] 차단한 유저 목록을 보고 해제할 수 있는 팝업창
  void _showBlockedUsersDialog(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('차단 관리', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                      final data = snapshot.data!.data() as Map<String, dynamic>?;
                      final blockedUsers = List<String>.from(data?['blockedUsers'] ?? []);

                      if (blockedUsers.isEmpty) {
                        return const Center(
                          child: Text('차단한 유저가 없습니다.', style: TextStyle(color: Colors.grey)),
                        );
                      }

                      return ListView.builder(
                        itemCount: blockedUsers.length,
                        itemBuilder: (context, index) {
                          final targetUid = blockedUsers[index];
                          return FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance.collection('users').doc(targetUid).get(),
                            builder: (context, targetSnapshot) {
                              if (!targetSnapshot.hasData) return const SizedBox.shrink();

                              final targetData = targetSnapshot.data!.data() as Map<String, dynamic>?;
                              final name = targetData?['displayName'] ?? '알 수 없는 유저';
                              final photoUrl = targetData?['photoUrl'];

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green[50],
                                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                  child: photoUrl == null ? const Icon(Icons.person, color: Colors.green) : null,
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                trailing: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () async {
                                    // 💡 DB의 배열에서 해당 유저 UID를 쏙 빼버립니다 (차단 해제)
                                    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                                      'blockedUsers': FieldValue.arrayRemove([targetUid]),
                                    });
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('[$name]님의 차단을 해제했습니다.')),
                                      );
                                    }
                                  },
                                  child: const Text('차단 해제', style: TextStyle(color: Colors.black87, fontSize: 12)),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기', style: TextStyle(color: Colors.grey)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    
    final authService = AuthService();
    final firestore = FirebaseFirestore.instance;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('내 정보', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            // 💡 [추가] 차단 관리 버튼 배치
            IconButton(
              icon: const Icon(Icons.person_off_outlined),
              tooltip: '차단 관리',
              onPressed: () => _showBlockedUsersDialog(context, user),
            ),
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
            StreamBuilder<DocumentSnapshot>(
              stream: firestore.collection('users').doc(user.uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final userData = snapshot.data!.data() as Map<String, dynamic>?;
                final photoUrl = userData?['photoUrl']; 
                final ageGroup = userData?['ageGroup'] ?? '비공개';
                final gender = userData?['gender'] ?? '비공개';
                final mbti = userData?['mbti'] ?? '비공개';
                final mannerVolt = userData?['mannerVolt'] ?? 0;

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _showProfilePicker(context, user),
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: Colors.green[50],
                              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                              child: photoUrl == null ? const Icon(Icons.person, color: Colors.green, size: 34) : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey[300]!)),
                                child: const Icon(Icons.edit, size: 14, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName?.isNotEmpty == true ? user.displayName! : '닉네임 없음',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(user.email ?? '', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                            const SizedBox(height: 4),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center, 
                              children: [
                                _buildBadge(ageGroup, Colors.blue),
                                _buildBadge(gender, Colors.pink),
                                _buildBadge(mbti, Colors.purple),
                                _buildMannerVoltBadge(mannerVolt), 
                                
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.orange, size: 20),
                                  tooltip: '테스트용 볼트 충전',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () async {
                                    await firestore.collection('users').doc(user.uid).update({
                                      'mannerVolt': FieldValue.increment(10),
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1, thickness: 1.5),
            
            Expanded(
              child: TabBarView(
                children: [
                  _MeetupStreamList(
                    stream: firestore.collection('meetings').where('creatorId', isEqualTo: user.uid).snapshots(),
                    emptyMessage: '아직 만든 번개 모임이 없어요.\n지도에서 새로운 번개를 열어보세요!',
                    isCreatorMode: true, 
                  ),
                  _MeetupStreamList(
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

    final isActuallyCreator = data['creatorId'] == uid;
    List<dynamic> participants = data['participants'] ?? [];
    
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false, 
      builder: (context) => MannerVoltDialog(
        participantIds: participants,
        meetingId: docId,
      ),
    );

    if (shouldDelete != true) return;

    try {
      if (isActuallyCreator) {
        await FirebaseFirestore.instance.collection('meetings').doc(docId).delete();
        try { await ChatService().leaveRoom(docId); } catch (_) {} 
      } else {
        await FirebaseFirestore.instance.collection('meetings').doc(docId).update({
          'participants': FieldValue.arrayRemove([uid]),
          'currentParticipants': FieldValue.increment(-1),
        });
        try { await ChatService().leaveRoom(docId); } catch (_) {} 
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isActuallyCreator ? '종료된 모임을 삭제했습니다.' : '종료된 모임에서 나갔습니다.'))
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('처리 중 오류가 발생했습니다.')));
      }
    }
  }

  void _showDeleteDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isActuallyCreator = data['creatorId'] == uid;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isActuallyCreator ? '모임 삭제' : '모임 기록 삭제'),
        content: Text(isActuallyCreator 
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs; 

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(emptyMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
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
              if (now.isAfter(deadline)) isExpired = true;
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