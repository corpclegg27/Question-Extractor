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
      // 1. Fetch Questions using Hybrid Logic
      List<String> keys = attempt.responses.keys.toList();
      List<Question> questions = [];
      bool useDocIds = keys.isNotEmpty && keys.first.length > 10;

      for (var i = 0; i < keys.length; i += 10) {
        final end = (i + 10 < keys.length) ? i + 10 : keys.length;
        final chunk = keys.sublist(i, end);

        if (chunk.isNotEmpty) {
          Query query = FirebaseFirestore.instance.collection('questions');
          if (useDocIds) {
            query = query.where(FieldPath.documentId, whereIn: chunk);
          } else {
            query = query.where('question_id', whereIn: chunk);
          }
          final snapshot = await query.get();
          questions.addAll(snapshot.docs.map((d) => Question.fromFirestore(d)));
        }
      }

      // Sort
      questions.sort((a, b) {
        String keyA = useDocIds ? a.id : a.customId;
        String keyB = useDocIds ? b.id : b.customId;
        if (!attempt.responses.containsKey(keyA)) keyA = useDocIds ? a.customId : a.id;
        if (!attempt.responses.containsKey(keyB)) keyB = useDocIds ? b.customId : b.id;
        int seqA = attempt.responses[keyA]?.q_no ?? 999;
        int seqB = attempt.responses[keyB]?.q_no ?? 999;
        return seqA.compareTo(seqB);
      });

      // 2. Map Answers
      Map<int, AnswerState> answerStates = {};
      for (int i = 0; i < questions.length; i++) {
        final q = questions[i];
        String lookupKey = useDocIds ? q.id : q.customId;
        if (!attempt.responses.containsKey(lookupKey)) lookupKey = useDocIds ? q.customId : q.id;

        final response = attempt.responses[lookupKey];
        AnswerStatus status = AnswerStatus.notVisited;
        if (response != null) {
          if (response.status == 'CORRECT' || response.status == 'INCORRECT') {
            status = AnswerStatus.answered;
          } else if (response.status == 'SKIPPED') {
            status = AnswerStatus.notAnswered;
          } else if (response.status == 'REVIEW') {
            status = AnswerStatus.markedForReview;
          } else if (response.status == 'REVIEW_ANSWERED') {
            status = AnswerStatus.answeredAndMarked;
          }
        }
        answerStates[i] = AnswerState(status: status, userAnswer: response?.selectedOption);
      }

      // 3. Create TestResult (POPULATING FROM ATTEMPT MODEL)
      final result = TestResult(
        attemptId: attempt.id,
        questions: questions,
        answerStates: answerStates,
        responses: attempt.responses,

        // Pass Aggregated Stats
        score: attempt.score,
        maxMarks: attempt.maxMarks,
        correctCount: attempt.correctCount,
        incorrectCount: attempt.incorrectCount,
        skippedCount: attempt.skippedCount,
        totalQuestions: attempt.totalQuestions,
        timeTakenSeconds: attempt.timeTakenSeconds,
        timeLimitMinutes: attempt.timeLimitMinutes,

        // Pass Breakdown Maps
        secondsBreakdownHighLevel: attempt.secondsBreakdownHighLevel,
        smartTimeAnalysisCounts: attempt.smartTimeAnalysisCounts,
        secondsBreakdownSmartTimeAnalysis: attempt.secondsBreakdownSmartTimeAnalysis,
      );

      if (context.mounted) {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (context) => ResultsScreen(result: result)));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading analysis: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (Build method remains same as before) ...
    final currentUser = FirebaseAuth.instance.currentUser;
    final String? uidToQuery = targetUserId ?? currentUser?.uid;
    if (uidToQuery == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('attempts').where('userId', isEqualTo: uidToQuery).orderBy('completedAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState();

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

        if (docs.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final attempt = AttemptModel.fromFirestore(docs[index]);
            return AttemptDisplayCard(attempt: attempt, onTap: () => _navigateToAnalysis(context, attempt));
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history, size: 64, color: Colors.grey.shade300), const SizedBox(height: 16), const Text("No attempts found.", style: TextStyle(color: Colors.grey))]));
  }
}