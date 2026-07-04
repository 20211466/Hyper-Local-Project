import 'package:flutter/material.dart';
import '../models/meetup.dart';

class MeetupCard extends StatelessWidget {
  final Meetup meetup;

  const MeetupCard({super.key, required this.meetup});

  @override
  Widget build(BuildContext context) {
    final isFull = meetup.currentParticipants >= meetup.maxParticipants;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bolt, color: Colors.amber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meetup.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  '${meetup.category} · ${meetup.time}까지',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            '${meetup.currentParticipants}/${meetup.maxParticipants}명',
            style: TextStyle(
              color: isFull ? Colors.red : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
