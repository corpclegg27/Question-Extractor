// lib/models/question_model.dart
// Description: Data model for a Question. Updated to include 'copyWith' for state updates.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/models/test_enums.dart';

class Question {
  final String id; // Firestore Document ID
  final String customId; // Custom ID (e.g., "17813")

  // --- Hierarchy / Syllabus Fields ---
  final String chapterId;
  final String topicId;
  final String topicL2Id;
  final String subject;
  final String chapter;
  final String topic;
  final String topicL2;

  // --- Question Metadata ---
  final QuestionType type;
  final String imageUrl;
  final String? solutionUrl;

  // [NEW] Field for AI Generated Solution Text (Markdown + LaTeX)
  final String? aiGenSolutionText;

  // LEGACY FIELD: Kept for backward compatibility (Single Correct)
  final dynamic correctAnswer;

  // NEW FIELD: For "One or more options correct" type (Mapped from 'correctAnswersOneOrMore')
  final List<String> correctAnswersList;

  final String difficulty;
  final String exam;
  final bool isPyq;
  final int questionNo;

  // --- NEWLY ADDED FIELDS ---
  final String? qcStatus;      // e.g., "Pending QC", "Accepted"
  final num? difficultyScore;  // e.g., 0.5, 10, etc.
  final int? pyqYear;          // e.g., 2022
  final String? ocrText;       // The raw text of the question

  Question({
    required this.id,
    required this.customId,
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
    this.aiGenSolutionText,
    required this.correctAnswer,
    this.correctAnswersList = const [],
    required this.difficulty,
    required this.exam,
    required this.isPyq,
    required this.questionNo,
    this.qcStatus,
    this.difficultyScore,
    this.pyqYear,
    this.ocrText,
  });

  /// UNIFIED GETTER: Returns the correct answer(s) as a clean List<String>.
  List<String> get actualCorrectAnswers {
    if (correctAnswersList.isNotEmpty) {
      return correctAnswersList;
    }
    if (correctAnswer != null) {
      String raw = correctAnswer.toString();
      return raw.replaceAll(' ', '').split(',').where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  // [ADDED] copyWith method
  Question copyWith({
    String? id,
    String? customId,
    String? chapterId,
    String? topicId,
    String? topicL2Id,
    String? subject,
    String? chapter,
    String? topic,
    String? topicL2,
    QuestionType? type,
    String? imageUrl,
    String? solutionUrl,
    String? aiGenSolutionText,
    dynamic correctAnswer,
    List<String>? correctAnswersList,
    String? difficulty,
    String? exam,
    bool? isPyq,
    int? questionNo,
    String? qcStatus,
    num? difficultyScore,
    int? pyqYear,
    String? ocrText,
  }) {
    return Question(
      id: id ?? this.id,
      customId: customId ?? this.customId,
      chapterId: chapterId ?? this.chapterId,
      topicId: topicId ?? this.topicId,
      topicL2Id: topicL2Id ?? this.topicL2Id,
      subject: subject ?? this.subject,
      chapter: chapter ?? this.chapter,
      topic: topic ?? this.topic,
      topicL2: topicL2 ?? this.topicL2,
      type: type ?? this.type,
      imageUrl: imageUrl ?? this.imageUrl,
      solutionUrl: solutionUrl ?? this.solutionUrl,
      aiGenSolutionText: aiGenSolutionText ?? this.aiGenSolutionText,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      correctAnswersList: correctAnswersList ?? this.correctAnswersList,
      difficulty: difficulty ?? this.difficulty,
      exam: exam ?? this.exam,
      isPyq: isPyq ?? this.isPyq,
      questionNo: questionNo ?? this.questionNo,
      qcStatus: qcStatus ?? this.qcStatus,
      difficultyScore: difficultyScore ?? this.difficultyScore,
      pyqYear: pyqYear ?? this.pyqYear,
      ocrText: ocrText ?? this.ocrText,
    );
  }

  factory Question.fromMap(Map<String, dynamic> data, String docId) {
    return Question(
      id: docId,
      customId: (data['question_id'] ?? data['id'] ?? docId).toString(),
      chapterId: data['chapterId'] ?? '',
      topicId: data['topicId'] ?? '',
      topicL2Id: data['topicL2Id'] ?? '',
      subject: data['Subject'] ?? 'Physics',
      chapter: data['Chapter'] ?? '',
      topic: data['Topic'] ?? '',
      topicL2: data['Topic_L2'] ?? '',
      type: _mapStringToType(data['Question type']),
      imageUrl: data['image_url'] ?? data['imageUrl'] ?? data['Image'] ?? '',
      solutionUrl: data['solution_url'] ?? data['solutionUrl'],
      aiGenSolutionText: data['AIgenSolutionText'],
      correctAnswer: data['Correct Answer'],
      correctAnswersList: (data['correctAnswersOneOrMore'] is List)
          ? List<String>.from(data['correctAnswersOneOrMore'])
          : [],
      difficulty: data['Difficulty'] ?? data['Difficulty_tag'] ?? 'Medium',
      exam: data['Exam'] ?? '',
      isPyq: (data['PYQ'] ?? '').toString().toLowerCase() == 'yes',
      questionNo: data['Question No.'] is int
          ? data['Question No.']
          : int.tryParse(data['Question No.']?.toString() ?? '0') ?? 0,
      qcStatus: data['QC_Status'],
      ocrText: data['OCR_Text'],
      difficultyScore: data['Difficulty_score'] is num
          ? data['Difficulty_score']
          : num.tryParse(data['Difficulty_score']?.toString() ?? '0'),
      pyqYear: data['PYQ_Year'] is int
          ? data['PYQ_Year']
          : int.tryParse(data['PYQ_Year']?.toString() ?? '0'),
    );
  }

  factory Question.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Question.fromMap(data, doc.id);
  }

  static QuestionType _mapStringToType(String? typeString) {
    switch (typeString) {
      case 'Single Correct': return QuestionType.singleCorrect;
      case 'Numerical type': return QuestionType.numerical;
      case 'One or more options correct': return QuestionType.oneOrMoreOptionsCorrect;
      case 'Single Matrix Match': return QuestionType.matrixSingle;
      case 'Multi Matrix Match': return QuestionType.matrixMulti;
      default: return QuestionType.unknown;
    }
  }
}