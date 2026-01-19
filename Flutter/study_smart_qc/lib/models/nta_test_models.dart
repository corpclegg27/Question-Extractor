// lib/models/nta_test_models.dart

import 'package:flutter/material.dart';

enum AnswerStatus {
  notVisited,
  notAnswered, // Visited but skipped
  answered,
  markedForReview, // Not answered, but marked
  answeredAndMarked, // Answered and marked for review
}

extension AnswerStatusExtension on AnswerStatus {
  Color get color {
    switch (this) {
      case AnswerStatus.answered:
        return Colors.green;
      case AnswerStatus.notAnswered:
        return Colors.red;
      case AnswerStatus.markedForReview:
        return Colors.purple;
      case AnswerStatus.answeredAndMarked:
        return Colors.blue;
      case AnswerStatus.notVisited:
      default:
        return Colors.grey.shade400;
    }
  }
}

class AnswerState {
  // CHANGED: String? -> dynamic to allow List<String> for Multiple Correct
  dynamic userAnswer;
  AnswerStatus status;

  AnswerState({this.userAnswer, this.status = AnswerStatus.notVisited});
}