import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 💡 Timestamp 처리를 위해 추가

class MeetupCard extends StatelessWidget {
  final Map<String, dynamic> meetupData;

  const MeetupCard({super.key, required this.meetupData});

  @override
  Widget build(BuildContext context) {
    final title = meetupData['title'] ?? '제목 없음';
    final category = meetupData['category'] ?? '기타';
    final location = meetupData['location'] ?? '지도 표시 지점';
    
    final int currentParticipants = meetupData['currentParticipants'] ?? 1;
    final int maxParticipants = meetupData['maxParticipants'] ?? 4;
    final isFull = currentParticipants >= maxParticipants;

    // 💡 2단계 핵심 로직: 현재 시간과 마감 시간을 비교해서 종료 여부(isExpired) 판단
    bool isExpired = false;
    if (meetupData['deadline'] != null) {
      final deadline = (meetupData['deadline'] as Timestamp).toDate();
      if (DateTime.now().isAfter(deadline)) {
        isExpired = true;
      }
    }

    Widget categoryIcon;
    switch (category) {
      case '식사':
        categoryIcon = const Center(child: Text('🍔', style: TextStyle(fontSize: 24)));
        break;
      case '운동':
        categoryIcon = const Center(child: Text('⚽', style: TextStyle(fontSize: 24)));
        break;
      case '공부':
        categoryIcon = const Center(child: Text('📚', style: TextStyle(fontSize: 24)));
        break;
      case '게임':
        categoryIcon = const Center(child: Text('🎮', style: TextStyle(fontSize: 24)));
        break;
      case '산책':
        categoryIcon = const Center(child: Text('🐕', style: TextStyle(fontSize: 24)));
        break;
      default:
        categoryIcon = const Center(child: Text('⚡', style: TextStyle(fontSize: 24)));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 💡 종료되었으면 카드 배경을 옅은 회색으로 변경
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
              // 💡 아이콘 배경도 종료 여부에 따라 회색 처리
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
                          // 💡 종료된 제목은 회색으로 만들고 취소선(-) 긋기
                          color: isExpired ? Colors.grey[600] : Colors.black,
                          decoration: isExpired ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 💡 종료되었을 때만 우측에 [종료] 뱃지 띄우기
                    if (isExpired) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '종료',
                          style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      )
                    ]
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$category · $location',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$currentParticipants/$maxParticipants 명',
            style: TextStyle(
              // 💡 종료되었으면 빨간/초록 대신 일괄 회색 처리
              color: isExpired ? Colors.grey : (isFull ? Colors.red : Colors.green),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}