// lib/services/universal_scoring_engine.dart

import 'package:study_smart_qc/models/marking_configuration.dart';
import 'package:study_smart_qc/models/test_enums.dart';

class ScoringResult {
  final double score;
  final String status; // 'CORRECT', 'INCORRECT', 'SKIPPED', 'PARTIALLY_CORRECT'

  ScoringResult({required this.score, required this.status});
}

class UniversalScoringEngine {

  static ScoringResult calculateScore({
    required QuestionType questionType,
    required dynamic userResponse, // Can be String (A or A,B) or List<String>
    required List<String> correctAnswers,
    required MarkingConfiguration config,
  }) {

    // 1. NORMALIZE INPUT TO LIST<STRING>
    List<String> userList = [];

    if (userResponse is String && userResponse.isNotEmpty) {
      // FIX: Handle comma-separated values for Multi-Correct types stored as Strings
      if (userResponse.contains(',')) {
        userList = userResponse.split(',').map((e) => e.trim()).toList();
      } else {
        userList = [userResponse];
      }
    } else if (userResponse is List) {
      userList = userResponse.map((e) => e.toString()).toList();
    }

    // 2. CHECK SKIPPED
    if (userList.isEmpty) {
      return ScoringResult(
        score: config.unattemptedScore,
        status: QuestionStatus.skipped,
      );
    }

    // 3. LOGIC: SINGLE CORRECT / NUMERICAL
    if (questionType == QuestionType.singleCorrect ||
        questionType == QuestionType.numerical) {

      String userVal = userList.first.trim().toLowerCase();
      String correctVal = correctAnswers.first.trim().toLowerCase();

      if (userVal == correctVal) {
        return ScoringResult(score: config.correctScore, status: QuestionStatus.correct);
      } else {
        return ScoringResult(score: config.incorrectScore, status: QuestionStatus.incorrect);
      }
    }

    // 4. LOGIC: ONE OR MORE OPTIONS CORRECT
    if (questionType == QuestionType.oneOrMoreOptionsCorrect) {
      return _calculateMultipleCorrect(userList, correctAnswers, config);
    }

    // Fallback
    return ScoringResult(score: 0.0, status: QuestionStatus.skipped);
  }

  static ScoringResult _calculateMultipleCorrect(
      List<String> userList,
      List<String> correctList,
      MarkingConfiguration config,
      ) {
    // Normalize for comparison
    final userSet = userList.map((e) => e.trim()).toSet();
    final correctSet = correctList.map((e) => e.trim()).toSet();

    // A. IMMEDIATE INCORRECT CHECK
    // If user selected ANYTHING that is not in the correct list, it is wrong.
    bool hasIncorrectSelection = userSet.any((e) => !correctSet.contains(e));

    if (hasIncorrectSelection) {
      return ScoringResult(
        score: config.incorrectScore,
        status: QuestionStatus.incorrect,
      );
    }

    // B. PERFECT MATCH CHECK
    if (userSet.length == correctSet.length) {
      return ScoringResult(
        score: config.correctScore,
        status: QuestionStatus.correct,
      );
    }

    // C. PARTIAL MARKING CHECK
    if (config.allowPartialMarking) {
      double partialScore = userSet.length * config.partialScorePerOption;
      return ScoringResult(
        score: partialScore,
        status: QuestionStatus.partiallyCorrect,
      );
    }

    // D. FALLBACK
    return ScoringResult(
      score: config.incorrectScore,
      status: QuestionStatus.incorrect,
    );
  }
}