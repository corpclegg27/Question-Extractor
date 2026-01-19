// lib/models/test_enums.dart
enum TestMode {
  test, // Timer counts down, no feedback, auto-submit
  practice, // Timer counts up (or hidden), instant feedback, solution access, pause allowed
}

enum PerformanceCategory {
  mastery, // Correct & Fast (Ideal)
  needsSpeed, // Correct & Slow (Knowledge is there, speed is not)
  rushed, // Incorrect & Fast (Likely a silly mistake or guess)
  struggle, // Incorrect & Slow (Conceptual gap)
  skipped, // Not attempted
  notVisited, // Didn't reach
}


enum QuestionType {
  singleCorrect,
  numerical,
  oneOrMoreOptionsCorrect,
  matrixSingle,
  matrixMulti,
  unknown,
}

class QuestionStatus {
  static const String correct = 'CORRECT';
  static const String incorrect = 'INCORRECT';
  static const String skipped = 'SKIPPED';
  static const String partiallyCorrect = 'PARTIALLY_CORRECT'; // New Status
}

class QuestionTypeStrings {
  static const String singleCorrect = 'Single Correct';
  static const String numerical = 'Numerical type';
  static const String multipleCorrect = 'One or more options correct';
  static const String matrixSingle = 'Single Matrix Match';
  static const String matrixMulti = 'Multi Matrix Match';
}


