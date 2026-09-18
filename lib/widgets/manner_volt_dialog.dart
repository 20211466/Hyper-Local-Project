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

  Future<void> _submitRatings() async {
    final reviewerId = currentUserId;
    if (reviewerId == null) return;

    setState(() => _isSubmitting = true);
    
    try {
      final db = FirebaseFirestore.instance;
      int successCount = 0;
      int skippedCount = 0;
      
      await db.runTransaction((transaction) async {
        Map<String, DocumentSnapshot> cooldownDocs = {};
        for (var targetId in _ratings.keys) {
          final logRef = db.collection('manner_logs').doc('${reviewerId}_$targetId');
          cooldownDocs[targetId] = await transaction.get(logRef);
        }

        final now = DateTime.now();

        for (var entry in _ratings.entries) {
          final targetId = entry.key;
          final score = entry.value;
          final logSnap = cooldownDocs[targetId];

          bool canRate = true; 

          if (logSnap != null && logSnap.exists) {
            final lastRated = (logSnap.data() as Map<String, dynamic>?)?['lastRatedAt'] as Timestamp?;
            if (lastRated != null) {
              final difference = now.difference(lastRated.toDate()).inDays;
              if (difference < 7) {
                canRate = false; 
              }
            }
          }

          if (canRate) {
            final userRef = db.collection('users').doc(targetId);
            transaction.update(userRef, {
              'mannerVolt': FieldValue.increment(score),
            });

            final logRef = db.collection('manner_logs').doc('${reviewerId}_$targetId');
            transaction.set(logRef, {
              'reviewerId': reviewerId,
              'targetId': targetId,
              'lastRatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            successCount++;
          } else {
            skippedCount++;
          }
        }
      });

      if (!mounted) return;
      Navigator.of(context).pop(true); 

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
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        textAlign: TextAlign.center,
      ),
      contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 0), // 좌우 패딩을 살짝 줄여서 공간 확보
      content: targetIds.isEmpty
          ? const Text('평가할 대상이 없습니다.', textAlign: TextAlign.center)
          : SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: targetIds.length,
                separatorBuilder: (_, __) => const Divider(height: 24),
                itemBuilder: (context, index) {
                  final targetId = targetIds[index];
                  
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(targetId).get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()));
                      
                      final userData = snapshot.data!.data() as Map<String, dynamic>?;
                      final name = userData?['displayName'] ?? '알 수 없는 유저';
                      final currentRating = _ratings[targetId];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('👤 $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 12),
                          // 💡 5개의 버튼이 화면에 잘 들어가도록 Expanded와 약간의 간격(SizedBox)을 사용했습니다.
                          Row(
                            children: [
                              Expanded(child: _buildRatingButton(targetId, -5, '🚨', '비매너', currentRating)),
                              const SizedBox(width: 4),
                              Expanded(child: _buildRatingButton(targetId, -1, '👎', '별로', currentRating)),
                              const SizedBox(width: 4),
                              Expanded(child: _buildRatingButton(targetId, 1, '👍', '좋음', currentRating)),
                              const SizedBox(width: 4),
                              Expanded(child: _buildRatingButton(targetId, 3, '💖', '친절', currentRating)),
                              const SizedBox(width: 4),
                              Expanded(child: _buildRatingButton(targetId, 5, '⚡', '최고', currentRating)),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
      actionsPadding: const EdgeInsets.all(16),
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

  // 💡 버튼 디자인 로직 (-5점은 유독 더 강렬한 빨간색으로 시각적 경고!)
  Widget _buildRatingButton(String uid, int score, String emoji, String label, int? currentRating) {
    final isSelected = currentRating == score;
    final isNegative = score < 0;
    final isCritical = score == -5; // -5점(최악)인지 판별

    return InkWell(
      onTap: () => setState(() => _ratings[uid] = score),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          // -5점은 배경을 더 진한 붉은색으로, 나머지는 기존 컬러 유지
          color: isSelected 
              ? (isCritical ? Colors.red.withOpacity(0.2) 
                  : (isNegative ? Colors.red.withOpacity(0.1) : Colors.amber.withOpacity(0.25))) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? (isNegative ? Colors.red : Colors.amber) 
                : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)), // 5개가 들어가야 해서 이모지 사이즈 살짝 축소
            const SizedBox(height: 6),
            Text(
              label, 
              style: TextStyle(
                fontSize: 9, 
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? (isNegative ? Colors.red[900] : Colors.orange[900]) : Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              score > 0 ? '+$score' : '$score', 
              style: TextStyle(
                fontSize: 10, 
                fontWeight: FontWeight.bold, 
                color: isNegative ? Colors.red : Colors.green[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}