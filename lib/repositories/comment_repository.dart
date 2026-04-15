import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/comment.dart';

class CommentRepository {
  CommentRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _comments(String ticketId) =>
      _firestore.collection('tickets').doc(ticketId).collection('comments');

  Stream<List<Comment>> watchComments(String ticketId) {
    return _comments(ticketId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Comment.fromDoc).toList());
  }

  Future<void> addComment({
    required String ticketId,
    required String authorId,
    required String authorName,
    required String text,
  }) {
    return _comments(ticketId).add({
      'ticketId': ticketId,
      'authorId': authorId,
      'authorName': authorName,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteComment(String ticketId, String commentId) {
    return _comments(ticketId).doc(commentId).delete();
  }
}

final commentRepositoryProvider = Provider<CommentRepository>(
  (ref) => CommentRepository(FirebaseFirestore.instance),
);

final commentsProvider =
    StreamProvider.family<List<Comment>, String>((ref, ticketId) {
  return ref.watch(commentRepositoryProvider).watchComments(ticketId);
});
