// lib/features/student/widgets/student_assignments_list.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/features/test_taking/screens/test_screen.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';

class StudentAssignmentsList extends StatelessWidget {
  final bool isStrict;

  final String? resumableAssignmentCode;
  final VoidCallback? onResumeTap;

  final List<String> submittedCodes;
  final VoidCallback? onViewAnalysisTap;

  const StudentAssignmentsList({
    super.key,
    required this.isStrict,
    this.resumableAssignmentCode,
    this.onResumeTap,
    this.submittedCodes = const [],
    this.onViewAnalysisTap,
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
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final data = filteredDocs[index].data() as Map<String, dynamic>;
            final docId = filteredDocs[index].id;

            final String currentCode = data['assignmentCode'] ?? '----';
            final bool isResumable = (resumableAssignmentCode != null && resumableAssignmentCode == currentCode);
            final bool isSubmitted = submittedCodes.contains(currentCode);

            return Column(
              children: [
                _buildAssignmentCard(context, data, docId, isResumable, isSubmitted),

                // CASE 1: RESUMABLE
                if (isResumable && !isSubmitted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      border: Border.all(color: Colors.deepPurple.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Unfinished Session Found", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 13)),
                        ElevatedButton.icon(
                          onPressed: onResumeTap,
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text("Resume"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  )

                // CASE 2: SUBMITTED
                else if (isSubmitted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Completed", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13)),
                        Row(
                          children: [
                            if (!isStrict)
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: TextButton(
                                  onPressed: () => _showModeSelectionDialog(context, docId, data),
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Colors.teal.shade800),
                                  child: const Text("Attempt Again", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ElevatedButton.icon(
                              onPressed: onViewAnalysisTap,
                              icon: const Icon(Icons.analytics, size: 16),
                              label: const Text("View Analysis"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 12),
              ],
            );
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
          Icon(isStrict ? Icons.timer_off_outlined : Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(isStrict ? "No pending tests!" : "No pending assignments!", style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildAssignmentCard(BuildContext context, Map<String, dynamic> data, String docId, bool isResumable, bool isSubmitted) {
    final Timestamp? ts = data['createdAt'];
    final dateStr = ts != null ? DateFormat('MMM d, yyyy').format(ts.toDate()) : 'Unknown Date';
    final int questionCount = (data['questionIds'] as List?)?.length ?? 0;
    final String code = data['assignmentCode'] ?? '----';
    final int? storedTime = data['timeLimitMinutes'];
    final String timeDisplay = storedTime != null ? "${storedTime}m" : "${questionCount * 2}m (Est)";

    Color codeBgColor;
    Color codeTextColor;
    Color borderColor;

    if (isSubmitted) {
      codeBgColor = Colors.teal.shade50;
      codeTextColor = Colors.teal.shade900;
      borderColor = Colors.teal.shade300;
    } else if (isStrict) {
      codeBgColor = Colors.red.shade50;
      codeTextColor = Colors.red.shade900;
      borderColor = Colors.red.shade200;
    } else {
      codeBgColor = Colors.deepPurple.shade50;
      codeTextColor = Colors.deepPurple.shade900;
      borderColor = Colors.deepPurple.shade200;
    }

    return Card(
      elevation: (isResumable || isSubmitted) ? 4 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: (isResumable || isSubmitted)
            ? const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))
            : BorderRadius.circular(12),
        side: (isResumable) ? BorderSide(color: Colors.deepPurple.shade300, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: (isResumable || isSubmitted)
            ? const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))
            : BorderRadius.circular(12),
        onTap: () {
          if (isSubmitted) {
            if (isStrict) {
              if (onViewAnalysisTap != null) onViewAnalysisTap!();
            } else {
              _showModeSelectionDialog(context, docId, data);
            }
          } else {
            _showModeSelectionDialog(context, docId, data);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: codeBgColor, borderRadius: BorderRadius.circular(4), border: Border.all(color: borderColor)),
                    child: Text("CODE: $code", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: codeTextColor)),
                  ),
                  Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 10),
              Text(data['title'] ?? "Untitled Assignment", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.quiz, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text("$questionCount Qs", style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(width: 15),
                  Icon(Icons.timer, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(timeDisplay, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  if (isSubmitted) ...[
                    const Spacer(),
                    const Icon(Icons.check_circle, size: 18, color: Colors.teal),
                    const SizedBox(width: 4),
                    Text("Done", style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                  ]
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

    // EXTRACT TITLE HERE
    final String title = data['title'] ?? "Untitled Assignment";

    final bool isStrictAssignment = data['onlySingleAttempt'] ?? false;
    final int timeLimit = data['timeLimitMinutes'] ?? (questionIds.length * 2);

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Start Session"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Title: $title"),
              const SizedBox(height: 10),
              Text("Questions: ${questionIds.length}"),
              Text("Time Limit: $timeLimit mins"),
              const SizedBox(height: 10),
              if (isStrictAssignment)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.red.shade200)),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text("Single Attempt Only. Practice Mode disabled.", style: TextStyle(fontSize: 12, color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              const Text("Select Mode:", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            if (!isStrictAssignment)
              OutlinedButton.icon(
                icon: const Icon(Icons.school_outlined),
                label: const Text("Practice Mode"),
                onPressed: () {
                  Navigator.pop(ctx);
                  // PASS TITLE
                  _launchTest(context, docId, code, title, questionIds, TestMode.practice, timeLimit);
                },
              ),
            ElevatedButton.icon(
              icon: const Icon(Icons.timer),
              label: const Text("Test Mode"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                // PASS TITLE
                _launchTest(context, docId, code, title, questionIds, TestMode.test, timeLimit);
              },
            ),
          ],
        )
    );
  }

  // UPDATED SIGNATURE: Added 'title'
  Future<void> _launchTest(
      BuildContext context,
      String assignmentId,
      String assignmentCode,
      String title,
      List<String> questionIds,
      TestMode mode,
      int timeLimit
      ) async {
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

                // PASS TITLE TO TEST SCREEN
                title: title,

                questions: questions,
                timeLimitInMinutes: timeLimit,
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