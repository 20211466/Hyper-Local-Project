import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore 컬렉션: "meetups"
/// 문서 필드:
///   title        : String
///   description  : String
///   category     : String
///   location     : String   (지도에서 선택한 주소/장소명)
///   lat, lng     : double   (구글맵 좌표 - 필요시 사용)
///   createdBy    : String   (모임장 uid)
///   participants : List<String>  (참여자 uid 배열, 모임장도 포함)
///   maxMembers   : int
///   meetingDate  : Timestamp
///   thumbnailEmoji : String (선택)
class Meetup {
  final String id;
  final String title;
  final String description;
  final String category;
  final String location;
  final double? lat;
  final double? lng;
  final String createdBy;
  final List<String> participants;
  final int maxMembers;
  final DateTime meetingDate;
  final String thumbnailEmoji;

  const Meetup({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.location,
    this.lat,
    this.lng,
    required this.createdBy,
    required this.participants,
    required this.maxMembers,
    required this.meetingDate,
    this.thumbnailEmoji = '📍',
  });

  int get memberCount => participants.length;

  bool isOwnedBy(String uid) => createdBy == uid;
  bool isJoinedBy(String uid) => participants.contains(uid) && createdBy != uid;

  factory Meetup.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Meetup(
      id: doc.id,
      title: data['title'] ?? '제목 없음',
      description: data['description'] ?? '',
      category: data['category'] ?? '기타',
      location: data['location'] ?? '',
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      createdBy: data['createdBy'] ?? '',
      participants: List<String>.from(data['participants'] ?? const []),
      maxMembers: data['maxMembers'] ?? 0,
      meetingDate: (data['meetingDate'] is Timestamp)
          ? (data['meetingDate'] as Timestamp).toDate()
          : DateTime.now(),
      thumbnailEmoji: data['thumbnailEmoji'] ?? '📍',
    );
  }
}
