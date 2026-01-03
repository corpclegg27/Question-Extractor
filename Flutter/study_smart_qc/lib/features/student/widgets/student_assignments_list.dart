import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- CRITICAL IMPORTS ---
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/features/test_taking/screens/test_screen.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';

class StudentAssignmentsList extends StatelessWidget {
  const StudentAssignmentsList({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('questions_curation')
          .where('studentUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'assigned') // Only show pending work
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // --- ERROR HANDLING FOR MISSING INDEX ---
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            color: Colors.red.shade50,
            child: Column(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(height: 10),
                const Text(
                  "Database Index Missing",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  "Please create the index using the link below (check console logs if truncated):\n\n${snapshot.error}",
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        final docs = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
              child: Text(
                "My Assignments",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final docId = docs[index].id;
                return _buildAssignmentCard(context, data, docId);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 40, color: Colors.grey),
            SizedBox(height: 10),
            Text("No pending assignments!", style: TextStyle(color: Colors.grey)),
          ],
        ),
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
      elevation: 3,
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
                      color: Colors.deepPurple.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "CODE: $code",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade900),
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
                    "$questionCount Questions",
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
    // Extract the assignment code to pass along
    final String code = data['assignmentCode'] ?? '----';

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Start Assignment"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Title: ${data['title']}"),
              const SizedBox(height: 10),
              Text("Questions: ${questionIds.length}"),
              const SizedBox(height: 20),
              const Text("Select Mode:", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            // PRACTICE BUTTON
            OutlinedButton.icon(
              icon: const Icon(Icons.school_outlined),
              label: const Text("Practice Mode"),
              onPressed: () {
                Navigator.pop(ctx);
                _launchTest(context, docId, code, questionIds, TestMode.practice);
              },
            ),

            // TEST BUTTON
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

  // UPDATED: Now accepts assignmentCode
  Future<void> _launchTest(BuildContext context, String assignmentId, String assignmentCode, List<String> questionIds, TestMode mode) async {
    // Show loading
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator())
    );

    try {
      // 1. Fetch Questions
      final questions = await TestOrchestrationService().getQuestionsByIds(questionIds);

      if (!context.mounted) return;
      Navigator.pop(context); // Hide loading

      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Questions not found.")));
        return;
      }

      // 2. Navigate to Player
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TestScreen(
                sourceId: assignmentId, // Linking for analytics
                assignmentCode: assignmentCode, // NEW: Passed to TestScreen
                questions: questions,
                timeLimitInMinutes: questions.length * 3, // Default 3 mins per question
                testMode: mode, // Pass the selected mode
              )
          )
      );

    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Hide loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading test: $e")));
      }
    }
  }
}