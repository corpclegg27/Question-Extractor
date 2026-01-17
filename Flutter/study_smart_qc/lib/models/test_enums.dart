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
