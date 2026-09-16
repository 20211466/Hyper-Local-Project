import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MannerVoltDialog extends StatefulWidget {
  final List<dynamic> participantIds;
  final String meetingId;

  const MannerVoltDialog({
    super.key,
    required this.participantIds,
    required this.meetingId,
  });

  @override
  State<MannerVoltDialog> createState() => _MannerVoltDialogState();
}

class _MannerVoltDialogState extends State<MannerVoltDialog> {
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final Map<String, int> _ratings = {};
  bool _isSubmitting = false;

  // 💡 [핵심 추가] 어뷰징 방지 룰이 적용된 안전한 평가 전송 로직
  Future<void> _submitRatings() async {
    final reviewerId = currentUserId;
    if (reviewerId == null) return;

    setState(() => _isSubmitting = true);
    
    try {
      final db = FirebaseFirestore.instance;
      int successCount = 0;
      int skippedCount = 0;
      
      // 트랜잭션: 도중에 누군가 점수를 수정해도 꼬이지 않게 보호
      await db.runTransaction((transaction) async {
        
        // 1. [읽기 단계] 내가 이 사람들을 최근 7일 내에 평가한 적이 있는지 기록부터 싹 조회합니다.
        Map<String, DocumentSnapshot> cooldownDocs = {};
        for (var targetId in _ratings.keys) {
          final logRef = db.collection('manner_logs').doc('${reviewerId}_$targetId');
          cooldownDocs[targetId] = await transaction.get(logRef);
        }

        final now = DateTime.now();

        // 2. [쓰기 단계] 조회한 기록을 바탕으로 진짜 점수를 올려줄지 판단합니다.
        for (var entry in _ratings.entries) {
          final targetId = entry.key;
          final score = entry.value;
          final logSnap = cooldownDocs[targetId];

          bool canRate = true; // 일단 평가 가능하다고 가정

          if (logSnap != null && logSnap.exists) {
            final lastRated = (logSnap.data() as Map<String, dynamic>?)?['lastRatedAt'] as Timestamp?;
            if (lastRated != null) {
              final difference = now.difference(lastRated.toDate()).inDays;
              // 🚨 만약 마지막 평가일로부터 7일이 지나지 않았다면? ➔ 평가 불가(스킵)
              if (difference < 7) {
                canRate = false; 
              }
            }
          }

          if (canRate) {
            // ✅ 조건 통과: 상대방의 매너 볼트 올려주기
            final userRef = db.collection('users').doc(targetId);
            transaction.update(userRef, {
              'mannerVolt': FieldValue.increment(score),
            });

            // ✅ 쿨타임 타이머 기록 업데이트 (오늘 평가했다고 도장 쾅!)
            final logRef = db.collection('manner_logs').doc('${reviewerId}_$targetId');
            transaction.set(logRef, {
              'reviewerId': reviewerId,
              'targetId': targetId,
              'lastRatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            successCount++;
          } else {
            // 🚫 7일 룰에 걸려서 점수 반영 스킵됨
            skippedCount++;
          }
        }
      });

      if (!mounted) return;
      Navigator.of(context).pop(true); 

      // 💡 [UX 디테일] 유저에게 결과에 맞는 맞춤형 피드백 제공
      if (skippedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚡ 평가 완료! (단, 7일 이내 중복 평가는 어뷰징 방지로 제외되었습니다)')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚡ 매너 볼트 평가가 완벽하게 반영되었습니다!')),
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오류가 발생했습니다. 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetIds = widget.participantIds.where((id) => id != currentUserId).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        '⚡ 함께한 동네 친구 어땠나요?',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        textAlign: TextAlign.center,
      ),
      content: targetIds.isEmpty
          ? const Text('평가할 대상이 없습니다.')
          : SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: targetIds.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final targetId = targetIds[index];
                  
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(targetId).get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()));
                      
                      final userData = snapshot.data!.data() as Map<String, dynamic>?;
                      final name = userData?['displayName'] ?? '알 수 없는 유저';
                      final currentRating = _ratings[targetId] ?? 0;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildRatingButton(targetId, 1, '👍', '좋아요', currentRating),
                              _buildRatingButton(targetId, 3, '💖', '친절해요', currentRating),
                              _buildRatingButton(targetId, 5, '⚡', '최고예요!', currentRating),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(true),
          child: const Text('건너뛰기', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: (_isSubmitting || _ratings.isEmpty) ? null : _submitRatings,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          child: _isSubmitting 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('평가 완료', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildRatingButton(String uid, int score, String emoji, String label, int currentRating) {
    final isSelected = currentRating == score;
    return InkWell(
      onTap: () => setState(() => _ratings[uid] = score),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.amber : Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: isSelected ? Colors.orange[800] : Colors.grey)),
          ],
        ),
      ),
    );
  }
}