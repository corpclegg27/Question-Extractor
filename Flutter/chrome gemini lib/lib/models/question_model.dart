import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionModel {
  final String id;
  final String chapterId;
  final String topicId;
  final String subject; 
  final String type;
  final String imageUrl;
  final String? solutionUrl;
  final String correctAnswer;
  final String difficulty;
  final String source;

  QuestionModel({
    required this.id,
    required this.chapterId,
    required this.topicId,
    this.subject = 'Physics', 
    required this.type,
    required this.imageUrl,
    this.solutionUrl,
    required this.correctAnswer,
    required this.difficulty,
    required this.source,
  });

  factory QuestionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return QuestionModel(
      id: doc.id,
      chapterId: data['chapterId'] ?? '',
      topicId: data['topicId'] ?? '',
      subject: data['subject'] ?? 'Physics', 
      type: data['Question type'] ?? 'Single Correct',
      imageUrl: data['image_url'] ?? '',
      solutionUrl: data['solution_url'],
      correctAnswer: data['Correct Answer'] ?? '',
      difficulty: data['Difficulty_tag'] ?? 'Medium',
      source: data['Exam'] ?? '',
    );
  }
}