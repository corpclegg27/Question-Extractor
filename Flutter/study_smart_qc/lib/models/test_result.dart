// lib/models/test_result.dart
// Description: Refactored to act as a wrapper around AttemptModel, eliminating data redundancy.

import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/question_model.dart';

class TestResult {
  // Single Source of Truth
  final AttemptModel attempt;

  // Contextual Data (Questions list is needed to render the solution sheet text/images)
  final List<Question> questions;

  // Optional: Transient UI state (if coming directly from test screen)
  final Map<int, dynamic>? answerStates;

  TestResult({
    required this.attempt,
    required this.questions,
    this.answerStates,
  });
}