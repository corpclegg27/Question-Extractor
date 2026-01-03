import 'package:cloud_firestore/cloud_firestore.dart';

class Question {
  final String id;
  final String chapterId;
  final String topicId;
  final String type;
  final String imageUrl;
  final String? solutionUrl;
  final String correctAnswer;
  final String difficulty;
  final String source;

  Question({
    required this.id,
    required this.chapterId,
    required this.topicId,
    required this.type,
    required this.imageUrl,
    this.solutionUrl,
    required this.correctAnswer,
    required this.difficulty,
    required this.source,
  });

  factory Question.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Question(
      id: doc.id,
      chapterId: data['chapterId'] ?? '',
      topicId: data['topicId'] ?? '',
      type: data['Question type'] ?? 'SCQ',
      imageUrl: data['image_url'] ?? '',
      solutionUrl: data['solution_url'],
      // FIX: Using the correct field name as you specified
      correctAnswer: data['Correct Answer'] ?? '',
      difficulty: data['Difficulty_tag'] ?? 'Medium',
      source: data['Exam'] ?? '',
    );
  }
}
