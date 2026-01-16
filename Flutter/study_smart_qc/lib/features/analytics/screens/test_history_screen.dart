/*
// lib/features/analytics/screens/test_history_screen.dart

import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
import 'package:study_smart_qc/features/analytics/screens/results_screen.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/test_enums.dart';
// Import the new reusable widget
import 'package:study_smart_qc/features/analytics/widgets/attempt_display_card.dart';

class TestHistoryScreen extends StatefulWidget {
  const TestHistoryScreen({Key? key}) : super(key: key);

  @override
  State<TestHistoryScreen> createState() => _TestHistoryScreenState();
}

class _TestHistoryScreenState extends State<TestHistoryScreen> {
  late Future<List<AttemptModel>> _attemptsFuture;
  final TestOrchestrationService _service = TestOrchestrationService();

  @override
  void initState() {
    super.initState();
    // Fetch attempts from Firestore via the orchestration service
    _attemptsFuture = _service.getUserAttempts();
  }

  Future<void> _refresh() async {
    setState(() {
      _attemptsFuture = _service.getUserAttempts();
    });
  }

  void _navigateToAnalysis(AttemptModel attempt) async {
    // 1. Show Loading UI while fetching question details
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 2. Extract Question IDs from the attempt responses
      List<String> questionIds = attempt.responses.keys.toList();

      // 3. Fetch Full Question Objects from Firestore to render the UI
      List<Question> questions = await _service.getQuestionsByIds(questionIds);

      // 4. Reconstruct AnswerStates from the history data for the ResultsScreen
      Map<int, AnswerState> answerStates = {};

      for (int i = 0; i < questions.length; i++) {
        final q = questions[i];
        final response = attempt.responses[q.id];

        AnswerStatus status = AnswerStatus.notVisited;
        if (response != null) {
          if (response.status == 'CORRECT' || response.status == 'INCORRECT') {
            status = AnswerStatus.answered;
          } else if (response.status == 'SKIPPED') {
            status = AnswerStatus.notAnswered;
          }
        }

        answerStates[i] = AnswerState(
          status: status,
          userAnswer: response?.selectedOption, // Supports String, List, or Map
        );
      }

      // 5. Create a TestResult object to pass to the ResultsScreen
      final result = TestResult(
        attemptId: attempt.id, // FIXED: Added attemptId here
        questions: questions,
        answerStates: answerStates,
        timeTaken: Duration(seconds: attempt.timeTakenSeconds),
        totalMarks: questions.length * 4,
        responses: attempt.responses,
      );

      // 6. Navigate to Analysis
      if (mounted) {
        Navigator.pop(context); // Close loader
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ResultsScreen(result: result)),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loader on error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading analysis: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("History & Analysis"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))
        ],
      ),
      body: FutureBuilder<List<AttemptModel>>(
        future: _attemptsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildEmptyState();
          }

          final attempts = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: attempts.length,
            itemBuilder: (context, index) {
              // Using the reusable AttemptDisplayCard for consistent UI
              return AttemptDisplayCard(
                attempt: attempts[index],
                onTap: () => _navigateToAnalysis(attempts[index]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text("No tests taken yet!", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}*/
