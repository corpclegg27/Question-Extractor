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

class AttemptListWidget extends StatelessWidget {
  final String? filterMode;
  final String? targetUserId;
  final bool onlySingleAttempt;

  const AttemptListWidget({
    super.key,
    this.filterMode,
    this.targetUserId,
    this.onlySingleAttempt = false,
  });

  Future<void> _navigateToAnalysis(BuildContext context, AttemptModel attempt) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      List<String> docIds = attempt.responses.keys.toList();
      List<Question> questions = [];

      for (var i = 0; i < docIds.length; i += 10) {
        final end = (i + 10 < docIds.length) ? i + 10 : docIds.length;
        final chunk = docIds.sublist(i, end);

        if (chunk.isNotEmpty) {
          final snapshot = await FirebaseFirestore.instance
              .collection('questions')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          questions.addAll(
              snapshot.docs.map((d) => Question.fromFirestore(d))
          );
        }
      }

      questions.sort((a, b) {
        int seqA = attempt.responses[a.id]?.q_no ?? 999;
        int seqB = attempt.responses[b.id]?.q_no ?? 999;
        return seqA.compareTo(seqB);
      });

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
          } else if (response.status == 'REVIEW') {
            status = AnswerStatus.markedForReview;
          }
        }

        answerStates[i] = AnswerState(
          status: status,
          userAnswer: response?.selectedOption,
        );
      }

      final result = TestResult(
        attemptId: attempt.id,
        questions: questions,
        answerStates: answerStates,
        timeTaken: Duration(seconds: attempt.timeTakenSeconds),
        totalMarks: questions.length * 4,
        responses: attempt.responses,
        // ADDED: Pass the time limit from the attempt model
        timeLimitMinutes: attempt.timeLimitMinutes,
      );

      if (context.mounted) {
        Navigator.pop(context); // Close loader
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ResultsScreen(result: result)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading analysis: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final String? uidToQuery = targetUserId ?? currentUser?.uid;

    if (uidToQuery == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
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

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (filterMode != null) {
            final String mode = data['mode'] ?? '';
            if (mode.toLowerCase() != filterMode!.toLowerCase()) return false;
          }
          final bool docSingleAttempt = data['onlySingleAttempt'] ?? false;
          if (docSingleAttempt != onlySingleAttempt) return false;
          return true;
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
      if (onlySingleAttempt) {
        message = "No strict tests attempted yet.";
        icon = Icons.timer_off;
      } else {
        message = "No assignments taken in Test Mode yet.";
        icon = Icons.timer_outlined;
      }
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