import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String ticketId;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  const Comment({
    required this.id,
    required this.ticketId,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.createdAt,
  });

  factory Comment.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return Comment(
      id: doc.id,
      ticketId: m['ticketId'] as String? ?? '',
      authorId: m['authorId'] as String? ?? '',
      authorName: m['authorName'] as String? ?? '',
      text: m['text'] as String? ?? '',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
