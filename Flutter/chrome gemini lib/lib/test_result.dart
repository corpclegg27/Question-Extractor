import 'package:study_smart_qc/attempt_model.dart';
import 'package:study_smart_qc/nta_test_models.dart';
import 'package:study_smart_qc/question_model.dart';

class TestResult {
  final List<Question> questions;
  final Map<int, AnswerState> answerStates;
  final Duration timeTaken;
  final int totalMarks;
  final Map<String, ResponseObject> responses; // Added to carry full response data

  TestResult({
    required this.questions,
    required this.answerStates,
    required this.timeTaken,
    required this.totalMarks,
    required this.responses, // Added
  });
}
