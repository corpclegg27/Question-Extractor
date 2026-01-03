import 'package:cloud_firestore/cloud_firestore.dart';

// Represents a single item in the 'attempt_items' collection for detailed analytics.
class AttemptItemModel {
  final String userId;
  final String questionId;
  final String chapterId;
  final String topicId;
  final String status; // e.g., 'CORRECT', 'INCORRECT', 'SKIPPED'
  final int timeSpent; // in seconds
  final Timestamp attemptedAt;

  AttemptItemModel({
    required this.userId,
    required this.questionId,
    required this.chapterId,
    required this.topicId,
    required this.status,
    required this.timeSpent,
    required this.attemptedAt,
  });

  // Method to convert an AttemptItemModel instance to a map for Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'questionId': questionId,
      'chapterId': chapterId,
      'topicId': topicId,
      'status': status,
      'timeSpent': timeSpent,
      'attemptedAt': attemptedAt,
    };
  }

  // Note: A fromFirestore factory is not strictly necessary for this model
  // as we are primarily using it for writing, not reading, in this flow.
}
