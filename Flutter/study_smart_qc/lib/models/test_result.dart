// lib/models/test_result.dart

import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/question_model.dart';

class TestResult {
  final String attemptId;
  final List<Question> questions;
  final Map<int, AnswerState> answerStates;
  final Duration timeTaken;
  final int totalMarks;
  final Map<String, ResponseObject> responses;

  // ADDED: The source of truth for the limit
  final int? timeLimitMinutes;

  TestResult({
    required this.attemptId,
    required this.questions,
    required this.answerStates,
    required this.timeTaken,
    required this.totalMarks,
    required this.responses,
    this.timeLimitMinutes, // Initialize
  });
}