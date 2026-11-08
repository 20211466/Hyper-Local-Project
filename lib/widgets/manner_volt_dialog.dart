import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// 평가 창에서 상위 모임 상세 화면으로 전달하는 평가 결과입니다.
class MannerVoltResult {
  final int successCount;
  final int skippedCount;
  final int unavailableCount;

  const MannerVoltResult({
    required this.successCount,
    required this.skippedCount,
    required this.unavailableCount,
  });
}

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
    if (reviewerId == null || _ratings.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final db = FirebaseFirestore.instance;

      // 점수 변경과 평가 로그 저장을 하나의 트랜잭션으로 처리합니다.
      // 중간에 하나라도 실패하면 점수와 로그가 모두 롤백됩니다.
      final result = await db.runTransaction<MannerVoltResult>((
        transaction,
      ) async {
        final cooldownDocs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        final userDocs = <String, DocumentSnapshot<Map<String, dynamic>>>{};

        // Firestore 트랜잭션에서는 모든 읽기를 쓰기보다 먼저 수행합니다.
        for (final targetId in _ratings.keys) {
          final logRef = db
              .collection('manner_logs')
              .doc('${reviewerId}_$targetId');
          final userRef = db.collection('users').doc(targetId);

          cooldownDocs[targetId] = await transaction.get(logRef);
          userDocs[targetId] = await transaction.get(userRef);
        }

        final now = DateTime.now();
        var successCount = 0;
        var skippedCount = 0;
        var unavailableCount = 0;

        for (final entry in _ratings.entries) {
          final targetId = entry.key;
          final score = entry.value;
          final logSnap = cooldownDocs[targetId];
          final userSnap = userDocs[targetId];

          // 화면에 표시된 다섯 가지 점수 이외의 값은 저장하지 않습니다.
          if (!const [-5, -1, 1, 3, 5].contains(score)) {
            throw StateError('허용되지 않은 매너 볼트 점수입니다.');
          }

          // 이미 탈퇴했거나 프로필 문서가 없는 사용자는 점수를 반영하지 않습니다.
          if (userSnap == null || !userSnap.exists) {
            unavailableCount++;
            continue;
          }

          var canRate = true;
          final lastRatedValue = logSnap?.data()?['lastRatedAt'];
          if (lastRatedValue is Timestamp) {
            final elapsed = now.difference(lastRatedValue.toDate());
            if (elapsed < const Duration(days: 7)) {
              canRate = false;
            }
          }

          if (!canRate) {
            skippedCount++;
            continue;
          }

          // 평가 대상자의 users/{targetId}.mannerVolt에 선택 점수를 더합니다.
          // +점수는 증가, -점수는 감소합니다.
          transaction.update(db.collection('users').doc(targetId), {
            'mannerVolt': FieldValue.increment(score),
          });

          // 같은 평가자-대상자 조합은 7일 동안 다시 평가할 수 없도록 기록합니다.
          transaction.set(
            db.collection('manner_logs').doc('${reviewerId}_$targetId'),
            {
              'reviewerId': reviewerId,
              'targetId': targetId,
              'meetingId': widget.meetingId,
              'score': score,
              'lastRatedAt': FieldValue.serverTimestamp(),
            },
          );

          successCount++;
        }

        return MannerVoltResult(
          successCount: successCount,
          skippedCount: skippedCount,
          unavailableCount: unavailableCount,
        );
      });

      if (!mounted) return;

      // SnackBar와 모임 상세창 닫기는 부모 화면에서 한 번에 처리합니다.
      // 여기서는 평가 결과만 반환해, 안내문이 닫히는 창 뒤에 가려지지 않게 합니다.
      Navigator.of(context).pop(result);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      final message = e.code == 'permission-denied'
          ? '평가 저장 권한이 없습니다. Firebase Firestore Rules가 최신 파일로 게시되었는지 확인해주세요.'
          : '평가 저장 중 오류가 발생했습니다. (${e.code})';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('평가 저장에 실패했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetIds = widget.participantIds
        .whereType<String>()
        .where((id) => id.isNotEmpty && id != currentUserId)
        .toSet()
        .toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        '⚡ 함께한 동네 친구 어땠나요?',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        textAlign: TextAlign.center,
      ),
      contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
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

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(targetId)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 50,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return const Text('참여자 정보를 불러오지 못했습니다.');
                      }

                      final userData = snapshot.data?.data();
                      final name = userData?['displayName'] ?? '알 수 없는 유저';
                      final currentRating = _ratings[targetId];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '👤 $name',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildRatingButton(
                                  targetId,
                                  -5,
                                  '🚨',
                                  '비매너',
                                  currentRating,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: _buildRatingButton(
                                  targetId,
                                  -1,
                                  '👎',
                                  '별로',
                                  currentRating,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: _buildRatingButton(
                                  targetId,
                                  1,
                                  '👍',
                                  '좋음',
                                  currentRating,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: _buildRatingButton(
                                  targetId,
                                  3,
                                  '💖',
                                  '친절',
                                  currentRating,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: _buildRatingButton(
                                  targetId,
                                  5,
                                  '⚡',
                                  '최고',
                                  currentRating,
                                ),
                              ),
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
          // 건너뛰기는 null을 반환하며, 상위 모임 상세창은 그대로 둡니다.
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('건너뛰기', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: (_isSubmitting || _ratings.isEmpty)
              ? null
              : _submitRatings,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  '평가 완료',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRatingButton(
    String uid,
    int score,
    String emoji,
    String label,
    int? currentRating,
  ) {
    final isSelected = currentRating == score;
    final isNegative = score < 0;
    final isCritical = score == -5;

    return InkWell(
      onTap: _isSubmitting ? null : () => setState(() => _ratings[uid] = score),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isCritical
                    ? Colors.red.withOpacity(0.2)
                    : (isNegative
                          ? Colors.red.withOpacity(0.1)
                          : Colors.amber.withOpacity(0.25)))
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
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? (isNegative ? Colors.red[900] : Colors.orange[900])
                    : Colors.black54,
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
