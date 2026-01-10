// lib/services/test_service.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';

class TestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Question>> generateTest({
    required Set<String> chapterIds,
    required Set<String> topicIds,
    required int questionCount,
  }) async {
    if (chapterIds.isEmpty || topicIds.isEmpty) {
      return [];
    }

    // Step 1: Fetch all questions from the selected CHAPTERS.
    // Note: Firestore 'whereIn' is limited to 10 items.
    // If you have more than 10 chapters, you might need to chunk this request.
    QuerySnapshot querySnapshot = await _firestore
        .collection('questions')
        .where('chapterId', whereIn: chapterIds.toList())
        .get();

    List<Question> fetchedQuestions = querySnapshot.docs
        .map((doc) => Question.fromFirestore(doc))
        .toList();

    // Step 2: Locally filter those questions by the selected TOPICS.
    List<Question> filteredByTopic = fetchedQuestions
        .where((q) => topicIds.contains(q.topicId))
        .toList();

    // Step 3: Ensure questions have a valid image URL.
    List<Question> validQuestions = filteredByTopic.where((q) {
      final url = q.imageUrl;
      return url.isNotEmpty &&
          (url.startsWith('http') || url.startsWith('https'));
    }).toList();

    // Step 4: Apply 80/20 split for question types

    // CHANGED: Using the Enum defined in the model (QuestionType)
    final scqQuestions = validQuestions
        .where((q) => q.type == QuestionType.singleCorrect)
        .toList();

    final numericalQuestions = validQuestions
        .where((q) => q.type == QuestionType.numerical)
        .toList();

    scqQuestions.shuffle();
    numericalQuestions.shuffle();

    final numNumerical = (questionCount * 0.2).round();
    final numScq = questionCount - numNumerical;

    final finalScq = scqQuestions
        .take(min(numScq, scqQuestions.length))
        .toList();
    final finalNumerical = numericalQuestions
        .take(min(numNumerical, numericalQuestions.length))
        .toList();

    final finalTestQuestions = [...finalScq, ...finalNumerical];
    finalTestQuestions.shuffle();

    return finalTestQuestions;
  }
}