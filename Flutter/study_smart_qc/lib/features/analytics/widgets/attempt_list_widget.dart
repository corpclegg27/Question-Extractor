// lib/features/analytics/widgets/attempt_list_widget.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/analytics/widgets/attempt_display_card.dart';
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/features/analytics/screens/results_screen.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';

class AttemptListWidget extends StatelessWidget {
  final String? filterMode; // 'Practice', 'Test', or null (for all)
  final String? targetUserId; // Optional: If provided (by Teacher), fetches specific student data

  const AttemptListWidget({
    super.key,
    this.filterMode,
    this.targetUserId,
  });

  // --- NAVIGATION LOGIC ---
  // This helper function fetches the full question data needed for the ResultsScreen
  Future<void> _navigateToAnalysis(BuildContext context, AttemptModel attempt) async {
    // 1. Show Loading Indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final service = TestOrchestrationService();

      // 2. Extract Question IDs from the attempt responses
      List<String> questionIds = attempt.responses.keys.toList();

      // 3. Fetch Full Question Objects from Firestore
      List<Question> questions = await service.getQuestionsByIds(questionIds);

      // 4. Reconstruct AnswerStates for the UI
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
          userAnswer: response?.selectedOption,
        );
      }

      // 5. Create TestResult object
      final result = TestResult(
        attemptId: attempt.id,
        questions: questions,
        answerStates: answerStates,
        timeTaken: Duration(seconds: attempt.timeTakenSeconds),
        totalMarks: questions.length * 4,
        responses: attempt.responses,
      );

      // 6. Navigate
      if (context.mounted) {
        Navigator.pop(context); // Close loader
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ResultsScreen(result: result)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loader on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading analysis: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Determine which User ID to fetch
    final currentUser = FirebaseAuth.instance.currentUser;
    // If targetUserId is passed (by Teacher via Drawer), use it. Otherwise use logged-in user.
    final String? uidToQuery = targetUserId ?? currentUser?.uid;

    if (uidToQuery == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      // Fetch all attempts for the specific user (Student or Teacher Target), ordered by most recent
      stream: FirebaseFirestore.instance
          .collection('attempts')
          .where('userId', isEqualTo: uidToQuery)
          .orderBy('completedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        // --- CLIENT SIDE FILTERING ---
        final docs = snapshot.data!.docs.where((doc) {
          if (filterMode == null) return true;

          final data = doc.data() as Map<String, dynamic>;
          final String mode = data['mode'] ?? '';
          return mode.toLowerCase() == filterMode!.toLowerCase();
        }).toList();

        if (docs.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final attempt = AttemptModel.fromFirestore(docs[index]);

            return AttemptDisplayCard(
              attempt: attempt,
              onTap: () => _navigateToAnalysis(context, attempt),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    String message = "No attempts found.";
    IconData icon = Icons.history;

    if (filterMode == 'Test') {
      message = "No strict tests attempted yet.";
      icon = Icons.timer_off;
    } else if (filterMode == 'Practice') {
      message = "No practice assignments completed yet.";
      icon = Icons.assignment_late_outlined;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}