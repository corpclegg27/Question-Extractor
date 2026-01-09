import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
// CRITICAL IMPORT
import 'package:study_smart_qc/models/test_enums.dart';

class Question {
  final String id;
  final String chapterId;
  final String topicId;
  final String topicL2Id;
  final String subject;
  final String chapter;
  final String topic;
  final String topicL2;

  final QuestionType type; // Uses the enum from test_enums.dart

  final String imageUrl;
  final String? solutionUrl;
  final dynamic correctAnswer;
  final String difficulty;
  final String exam;
  final bool isPyq;
  final int questionNo;

  Question({
    required this.id,
    required this.chapterId,
    required this.topicId,
    required this.topicL2Id,
    required this.subject,
    required this.chapter,
    required this.topic,
    required this.topicL2,
    required this.type,
    required this.imageUrl,
    this.solutionUrl,
    required this.correctAnswer,
    required this.difficulty,
    required this.exam,
    required this.isPyq,
    required this.questionNo,
  });

  factory Question.fromMap(Map<String, dynamic> data, String id) {
    // Debugging Missing Images
    String? foundImage = data['image_url'] ?? data['imageUrl'] ?? data['Image'];
    if (foundImage == null || foundImage.isEmpty) {
      debugPrint("⚠️ [WARNING] Question $id has NO IMAGE URL detected.");
    }

    return Question(
      id: id.isNotEmpty ? id : (data['question_id'] ?? ''),
      chapterId: data['chapterId'] ?? '',
      topicId: data['topicId'] ?? '',
      topicL2Id: data['topicL2Id'] ?? '',
      subject: data['Subject'] ?? 'Physics',
      chapter: data['Chapter'] ?? '',
      topic: data['Topic'] ?? '',
      topicL2: data['Topic_L2'] ?? '',

      type: _mapStringToType(data['Question type']),

      // Robust Image Check
      imageUrl: data['image_url'] ?? data['imageUrl'] ?? data['Image'] ?? '',
      solutionUrl: data['solution_url'] ?? data['solutionUrl'],

      correctAnswer: data['Correct Answer'],
      difficulty: data['Difficulty_tag'] ?? 'Medium',
      exam: data['Exam'] ?? '',
      isPyq: (data['PYQ'] ?? '') == 'Yes',
      questionNo: data['Question No.'] is int
          ? data['Question No.']
          : int.tryParse(data['Question No.']?.toString() ?? '0') ?? 0,
    );
  }

  factory Question.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Question.fromMap(data, doc.id);
  }

  static QuestionType _mapStringToType(String? typeString) {
    switch (typeString) {
      case 'Single Correct':
        return QuestionType.singleCorrect;
      case 'Numerical type':
        return QuestionType.numerical;
      case 'One or more options correct':
        return QuestionType.multipleCorrect;
      case 'Single Matrix Match':
        return QuestionType.matrixSingle;
      case 'Multi Matrix Match':
        return QuestionType.matrixMulti;
      default:
        return QuestionType.unknown;
    }
  }
}
