import 'package:cloud_firestore/cloud_firestore.dart';

class AttemptItemModel {
  final String userId;
  final DocumentReference attemptRef; // <--- The Fix: Stores reference to parent
  final String questionId;
  final String chapterId;
  final String topicId;
  final String status;
  final int timeSpent;
  final Timestamp attemptedAt;
  final String assignmentCode;
  final String mode;
  final String? mistakeCategory;
  final String? mistakeNote;

  AttemptItemModel({
    required this.userId,
    required this.attemptRef,
    required this.questionId,
    required this.chapterId,
    required this.topicId,
    required this.status,
    required this.timeSpent,
    required this.attemptedAt,
    required this.assignmentCode,
    required this.mode,
    this.mistakeCategory,
    this.mistakeNote,
  });

  factory AttemptItemModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return AttemptItemModel(
      userId: data['userId'] ?? '',
      // Safe casting for the reference
      attemptRef: data['attemptRef'] is DocumentReference
          ? data['attemptRef']
          : FirebaseFirestore.instance.collection('attempts').doc('unknown'),
      questionId: data['questionId'] ?? '',
      chapterId: data['chapterId'] ?? '',
      topicId: data['topicId'] ?? '',
      status: data['status'] ?? 'SKIPPED',
      timeSpent: data['timeSpent'] ?? 0,
      attemptedAt: data['attemptedAt'] ?? Timestamp.now(),
      assignmentCode: data['assignmentCode'] ?? '',
      mode: data['mode'] ?? 'Test',
      mistakeCategory: data['mistakeCategory'],
      mistakeNote: data['mistakeNote'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'attemptRef': attemptRef,
      'questionId': questionId,
      'chapterId': chapterId,
      'topicId': topicId,
      'status': status,
      'timeSpent': timeSpent,
      'attemptedAt': attemptedAt,
      'assignmentCode': assignmentCode,
      'mode': mode,
      'mistakeCategory': mistakeCategory,
      'mistakeNote': mistakeNote,
    };
  }
}