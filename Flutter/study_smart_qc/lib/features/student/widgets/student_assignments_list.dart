import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/features/test_taking/screens/test_screen.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';

class StudentAssignmentsList extends StatelessWidget {
  final bool isStrict; // <--- NEW FILTER PARAMETER

  const StudentAssignmentsList({
    super.key,
    required this.isStrict,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('questions_curation')
          .where('studentUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'assigned')
          .orderBy('createdAt', descending: true)
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
        // We do this here to safely handle 'null' values for legacy data
        final allDocs = snapshot.data!.docs;
        final filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final bool docIsStrict = data['onlySingleAttempt'] ?? false;
          return docIsStrict == isStrict;
        }).toList();

        if (filteredDocs.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          // Allow this list to scroll nicely inside the main page
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final data = filteredDocs[index].data() as Map<String, dynamic>;
            final docId = filteredDocs[index].id;
            return _buildAssignmentCard(context, data, docId);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isStrict ? Icons.timer_off_outlined : Icons.assignment_turned_in_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            isStrict ? "No pending tests!" : "No pending assignments!",
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentCard(BuildContext context, Map<String, dynamic> data, String docId) {
    final Timestamp? ts = data['createdAt'];
    final dateStr = ts != null
        ? DateFormat('MMM d, yyyy').format(ts.toDate())
        : 'Unknown Date';

    final List<dynamic> subjects = data['subjects'] ?? [];
    final int questionCount = (data['questionIds'] as List?)?.length ?? 0;
    final String code = data['assignmentCode'] ?? '----';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _showModeSelectionDialog(context, docId, data);
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isStrict ? Colors.red.shade50 : Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: isStrict ? Colors.red.shade200 : Colors.deepPurple.shade200
                      ),
                    ),
                    child: Text(
                      isStrict ? "TEST MODE" : "CODE: $code",
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isStrict ? Colors.red.shade900 : Colors.deepPurple.shade900
                      ),
                    ),
                  ),
                  Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                data['title'] ?? "Untitled Assignment",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),

              // Details
              Row(
                children: [
                  Icon(Icons.menu_book, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    subjects.join(", "),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 15),
                  Icon(Icons.quiz, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    "$questionCount Qs",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showModeSelectionDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    final questionIds = List<String>.from(data['questionIds'] ?? []);
    final String code = data['assignmentCode'] ?? '----';

    // READ THE FLAG
    final bool isStrictAssignment = data['onlySingleAttempt'] ?? false;

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Start Session"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Title: ${data['title']}"),
              const SizedBox(height: 10),
              Text("Questions: ${questionIds.length}"),
              const SizedBox(height: 10),

              if (isStrictAssignment)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red.shade200)
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Single Attempt Only. Practice Mode disabled.",
                          style: TextStyle(fontSize: 12, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),
              const Text("Select Mode:", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            // CONDITIONAL: Only show Practice Mode if NOT strict
            if (!isStrictAssignment)
              OutlinedButton.icon(
                icon: const Icon(Icons.school_outlined),
                label: const Text("Practice Mode"),
                onPressed: () {
                  Navigator.pop(ctx);
                  _launchTest(context, docId, code, questionIds, TestMode.practice);
                },
              ),

            ElevatedButton.icon(
              icon: const Icon(Icons.timer),
              label: const Text("Test Mode"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _launchTest(context, docId, code, questionIds, TestMode.test);
              },
            ),
          ],
        )
    );
  }

  Future<void> _launchTest(BuildContext context, String assignmentId, String assignmentCode, List<String> questionIds, TestMode mode) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator())
    );

    try {
      final questions = await TestOrchestrationService().getQuestionsByIds(questionIds);

      if (!context.mounted) return;
      Navigator.pop(context); // Hide loading

      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Questions not found.")));
        return;
      }

      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TestScreen(
                sourceId: assignmentId,
                assignmentCode: assignmentCode,
                questions: questions,
                timeLimitInMinutes: questions.length * 3,
                testMode: mode,
              )
          )
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading test: $e")));
      }
    }
  }
}