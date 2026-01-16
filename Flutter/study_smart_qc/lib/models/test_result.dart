// lib/models/test_result.dart

import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/question_model.dart';

class TestResult {
  final String attemptId;
  final List<Question> questions;
  final Map<int, AnswerState> answerStates;

  // STATS (Directly from Firestore)
  final num score;
  final int maxMarks;
  final int correctCount;
  final int incorrectCount;
  final int skippedCount;
  final int totalQuestions;
  final int timeTakenSeconds;
  final int? timeLimitMinutes;

  // BREAKDOWNS (Directly from Firestore)
  final Map<String, int> secondsBreakdownHighLevel;
  final Map<String, int> smartTimeAnalysisCounts;
  final Map<String, int> secondsBreakdownSmartTimeAnalysis;

  final Map<String, ResponseObject> responses;

  TestResult({
    required this.attemptId,
    required this.questions,
    required this.answerStates,
    required this.responses,

    // Required Stats
    required this.score,
    required this.maxMarks,
    required this.correctCount,
    required this.incorrectCount,
    required this.skippedCount,
    required this.totalQuestions,
    required this.timeTakenSeconds,
    this.timeLimitMinutes,

    // Required Maps (Default to empty if missing)
    this.secondsBreakdownHighLevel = const {},
    this.smartTimeAnalysisCounts = const {},
    this.secondsBreakdownSmartTimeAnalysis = const {},
  });
}