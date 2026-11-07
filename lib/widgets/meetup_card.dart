import 'package:flutter/material.dart';

class MeetupCard extends StatelessWidget {
  final Map<String, dynamic> meetupData;

  /// 사용자가 내 정보에서 설정한 관심 카테고리 순위입니다.
  /// null이면 관심 카테고리 표시를 보여주지 않습니다.
  final int? preferredCategoryRank;

  const MeetupCard({
    super.key,
    required this.meetupData,
    this.preferredCategoryRank,
  });

  DateTime? _readDateTime(dynamic value) {
    if (value is DateTime) return value;
    // cloud_firestore Timestamp는 toDate()를 제공하지만 타입 import 없이
    // 기존 프로젝트의 Timestamp 필드를 처리하도록 dynamic 변환을 사용합니다.
    try {
      final dynamic converted = value?.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Timestamp가 아닌 값이면 아래 문자열 처리를 시도합니다.
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String title = (meetupData['title'] ?? '제목 없음').toString();
    final String category = (meetupData['category'] ?? '기타').toString();
    final String location =
        (meetupData['location'] ??
                meetupData['dong'] ??
                meetupData['region'] ??
                '지도 표시 지점')
            .toString();

    final int currentParticipants =
        (meetupData['currentParticipants'] as num?)?.toInt() ?? 1;
    final int maxParticipants =
        (meetupData['maxParticipants'] as num?)?.toInt() ?? 4;
    final bool isFull = currentParticipants >= maxParticipants;

    final DateTime? deadline = _readDateTime(meetupData['deadline']);
    final bool isExpired = deadline != null && DateTime.now().isAfter(deadline);

    Widget categoryIcon;
    switch (category) {
      case '식사':
        categoryIcon = const Center(
          child: Text('🍔', style: TextStyle(fontSize: 24)),
        );
        break;
      case '운동':
        categoryIcon = const Center(
          child: Text('⚽', style: TextStyle(fontSize: 24)),
        );
        break;
      case '공부':
        categoryIcon = const Center(
          child: Text('📚', style: TextStyle(fontSize: 24)),
        );
        break;
      case '게임':
        categoryIcon = const Center(
          child: Text('🎮', style: TextStyle(fontSize: 24)),
        );
        break;
      case '산책':
        categoryIcon = const Center(
          child: Text('🐕', style: TextStyle(fontSize: 24)),
        );
        break;
      default:
        categoryIcon = const Center(
          child: Text('⚡', style: TextStyle(fontSize: 24)),
        );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isExpired ? Colors.grey[200] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isExpired ? Colors.grey[300] : Colors.green[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: categoryIcon,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isExpired ? Colors.grey[600] : Colors.black,
                          decoration: isExpired
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isExpired) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '종료',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$category · $location',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (preferredCategoryRank != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      '내 관심 ${preferredCategoryRank}순위',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$currentParticipants/$maxParticipants 명',
            style: TextStyle(
              color: isExpired
                  ? Colors.grey
                  : (isFull ? Colors.red : Colors.green),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
