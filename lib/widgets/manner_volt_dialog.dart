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
  // 각 유저에게 줄 점수를 저장하는 맵 {uid: 점수}
  final Map<String, int> _ratings = {};
  bool _isSubmitting = false;

  Future<void> _submitRatings() async {
    setState(() => _isSubmitting = true);
    
    try {
      final db = FirebaseFirestore.instance;
      
      // 💡 Firestore 트랜잭션: 여러 유저의 점수를 안전하게 동시 업데이트
      await db.runTransaction((transaction) async {
        for (var entry in _ratings.entries) {
          final userRef = db.collection('users').doc(entry.key);
          transaction.update(userRef, {
            'mannerVolt': FieldValue.increment(entry.value),
          });
        }
      });

      if (!mounted) return;
      Navigator.of(context).pop(true); // 성공 시 true 반환하며 창 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚡ 매너 볼트 평가가 완료되었습니다!')),
      );
    } catch (e) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오류가 발생했습니다. 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 나를 제외한 참여자 목록만 필터링
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
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
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