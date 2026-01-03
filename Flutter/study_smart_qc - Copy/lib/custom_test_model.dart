import 'package:cloud_firestore/cloud_firestore.dart';

// Represents a test that has been generated and potentially saved.
class CustomTest {
  final String id;
  final String userId;
  final String testName;
  final String status; // e.g., 'Not Attempted', 'Attempted'
  final List<String> questionIds;
  final int totalQuestions;
  final int timeLimitInMinutes;
  final Timestamp createdAt;
  final List<String> chapterNames;

  CustomTest({
    required this.id,
    required this.userId,
    required this.testName,
    required this.status,
    required this.questionIds,
    required this.totalQuestions,
    required this.timeLimitInMinutes,
    required this.createdAt,
    required this.chapterNames,
  });

  // Factory to create a CustomTest from a Firestore document.
  factory CustomTest.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return CustomTest(
      id: doc.id,
      userId: data['userId'] ?? '',
      testName: data['testName'] ?? 'Custom Test',
      status: data['status'] ?? 'Not Attempted',
      questionIds: List<String>.from(data['questionIds'] ?? []),
      totalQuestions: data['totalQuestions'] ?? 0,
      timeLimitInMinutes: data['timeLimitInMinutes'] ?? 0,
      createdAt: data['createdAt'] ?? Timestamp.now(),
      chapterNames: List<String>.from(data['chapterNames'] ?? []),
    );
  }

  // Method to convert a CustomTest instance to a map for Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'testName': testName,
      'status': status,
      'questionIds': questionIds,
      'totalQuestions': totalQuestions,
      'timeLimitInMinutes': timeLimitInMinutes,
      'createdAt': createdAt,
      'chapterNames': chapterNames,
    };
  }
}
