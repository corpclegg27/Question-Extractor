//lib/models/question_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
  final dynamic correctAnswer;
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
    required this.correctAnswer,
    required this.difficulty,
    required this.exam,
    required this.isPyq,
    required this.questionNo,
    // Initialize new fields
    this.qcStatus,
    this.difficultyScore,
    this.pyqYear,
    this.ocrText,
  });

  factory Question.fromMap(Map<String, dynamic> data, String docId) {
    return Question(
      id: docId,
      // CAPTURE THE CUSTOM ID (Fallback to docId if missing)
      customId: (data['question_id'] ?? data['id'] ?? docId).toString(),

      chapterId: data['chapterId'] ?? '',
      topicId: data['topicId'] ?? '',
      topicL2Id: data['topicL2Id'] ?? '',
      subject: data['Subject'] ?? 'Physics', // Default to Physics if missing
      chapter: data['Chapter'] ?? '',
      topic: data['Topic'] ?? '',
      topicL2: data['Topic_L2'] ?? '',

      type: _mapStringToType(data['Question type']),

      // CORRECT IMAGE FIELD (Matches your Firestore doc: 'image_url')
      imageUrl: data['image_url'] ?? data['imageUrl'] ?? data['Image'] ?? '',

      solutionUrl: data['solution_url'] ?? data['solutionUrl'],
      correctAnswer: data['Correct Answer'],

      // Look for 'Difficulty' first (per your Firestore doc), fallback to 'Difficulty_tag'
      difficulty: data['Difficulty'] ?? data['Difficulty_tag'] ?? 'Medium',

      exam: data['Exam'] ?? '',

      // Updated Logic: Check if String is 'Yes' (Case insensitive safe check)
      isPyq: (data['PYQ'] ?? '').toString().toLowerCase() == 'yes',

      questionNo: data['Question No.'] is int
          ? data['Question No.']
          : int.tryParse(data['Question No.']?.toString() ?? '0') ?? 0,

      // --- MAPPING NEW FIELDS ---
      qcStatus: data['QC_Status'],
      ocrText: data['OCR_Text'],

      // Handle potential String vs Number mismatches safely
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
      case 'One or more options correct': return QuestionType.multipleCorrect;
      case 'Single Matrix Match': return QuestionType.matrixSingle;
      case 'Multi Matrix Match': return QuestionType.matrixMulti;
      default: return QuestionType.unknown;
    }
  }

}