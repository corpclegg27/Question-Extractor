// lib/features/student/widgets/student_curation_preview_card.dart
// Description: Card widget. Fixed UI Precedence: "Resume" status now overrides "Completed" status.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// LOGIC IMPORTS
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
import 'package:study_smart_qc/features/test_taking/screens/test_screen.dart';
import 'package:study_smart_qc/models/marking_configuration.dart';

class StudentCurationPreviewCard extends StatelessWidget {
  final QueryDocumentSnapshot snapshot;
  final bool isResumable;
  final bool isSubmitted;
  final bool isStrict;

  final VoidCallback onResumeTap;
  final VoidCallback onViewAnalysisTap;

  final VoidCallback? onRefreshNeeded;

  const StudentCurationPreviewCard({
    super.key,
    required this.snapshot,
    required this.isResumable,
    required this.isSubmitted,
    required this.isStrict,
    required this.onResumeTap,
    required this.onViewAnalysisTap,
    this.onRefreshNeeded,
  });

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    final data = snapshot.data() as Map<String, dynamic>;
    final String assignmentCode = data['assignmentCode'] ?? '----';

    return StreamBuilder<DocumentSnapshot>(
      stream: uid != null
          ? FirebaseFirestore.instance.collection('users').doc(uid).snapshots()
          : null,
      builder: (context, userSnap) {

        // --- 1. DETERMINE TRUE STATUS ---
        bool actuallySubmitted = isSubmitted;

        // Check Backend Status
        final String docStatus = data['status']?.toString() ?? '';
        if (docStatus.toLowerCase() == 'submitted' || docStatus == 'Attempted') {
          actuallySubmitted = true;
        }

        // Check User Profile (Real-time)
        if (!actuallySubmitted && userSnap.hasData && userSnap.data!.exists) {
          final userData = userSnap.data!.data() as Map<String, dynamic>;
          final List<dynamic> submittedList = userData['assignmentCodesSubmitted'] ?? [];
          if (submittedList.contains(assignmentCode)) {
            actuallySubmitted = true;
          }
        }

        return _buildCardUI(context, data, actuallySubmitted);
      },
    );
  }

  Widget _buildCardUI(BuildContext context, Map<String, dynamic> data, bool actuallySubmitted) {
    // --- 2. PARSE DATA ---
    final Timestamp? createdAtTs = data['createdAt'];
    final Timestamp? deadlineTs = data['deadline'];
    final String title = data['title'] ?? "Untitled Assignment";
    final String code = data['assignmentCode'] ?? '----';
    final int questionCount = (data['questionIds'] as List?)?.length ?? 0;
    final int? storedTime = data['timeLimitMinutes'];
    final String timeDisplay = storedTime != null ? "${storedTime}m" : "${questionCount * 2}m (Est)";

    // Date Strings
    final String assignedDateText = createdAtTs != null
        ? DateFormat('MMM d, yyyy').format(createdAtTs.toDate())
        : 'Unknown';

    String? deadlineLabel;
    bool isOverdue = false;

    if (deadlineTs != null) {
      final date = deadlineTs.toDate();
      final formatted = DateFormat('MMM d, h:mm a').format(date);
      deadlineLabel = "Due: $formatted";
      if (date.isBefore(DateTime.now()) && !actuallySubmitted) {
        isOverdue = true;
      }
    }

    // --- 3. THEME LOGIC ---
    Color borderColor = Colors.transparent;
    List<BoxShadow> shadows;
    Widget? statusBadge;

    // Default Shadow
    shadows = [
      BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4)),
    ];

    // [CRITICAL FIX] Check Resumable FIRST.
    // Even if it's "Completed" (retake scenario), we want to show the Resume UI if a session is pending.
    if (isResumable) {
      // 🟠 RESUMABLE: Orange Glow
      borderColor = Colors.orange.shade300;
      shadows = [
        BoxShadow(color: Colors.orange.withOpacity(0.2), blurRadius: 10, spreadRadius: 1),
      ];
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.timelapse, size: 16, color: Colors.orange.shade800),
            const SizedBox(width: 4),
            Text("In Progress", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
          ],
        ),
      );
    } else if (actuallySubmitted) {
      // 🟢 COMPLETED: Green Glow & Border
      borderColor = Colors.green.shade300;
      shadows = [
        BoxShadow(color: Colors.green.withOpacity(0.25), blurRadius: 12, spreadRadius: 2),
        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 3)),
      ];
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 4),
            Text("Completed", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
          ],
        ),
      );
    } else {
      // ⚪ PENDING
      borderColor = Colors.grey.shade200;
      if (isOverdue) borderColor = Colors.red.shade200;

      // Only show badge if there is a deadline
      if (deadlineLabel != null) {
        statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isOverdue ? Colors.red.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: isOverdue ? Border.all(color: Colors.red.shade200) : null,
          ),
          child: Text(
            deadlineLabel,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isOverdue ? Colors.red : Colors.grey.shade600
            ),
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: shadows,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _handleTap(context, data, actuallySubmitted),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER: CODE + BADGE ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "CODE: $code",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                  ),
                  if (statusBadge != null) statusBadge!,
                ],
              ),

              const SizedBox(height: 6),

              // --- ASSIGNED DATE ---
              Text(
                "Assigned on: $assignedDateText",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),

              const SizedBox(height: 8),

              // --- TITLE ---
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 8),

              // --- DETAILS ROW ---
              Row(
                children: [
                  Icon(Icons.quiz_outlined, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text("$questionCount Qs", style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(timeDisplay, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),

                  const Spacer(),
                  if (isStrict && !actuallySubmitted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.shade100)
                      ),
                      child: Text("STRICT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // --- ACTION BUTTONS ---

              // [CRITICAL FIX] Prioritize Resume Button
              if (isResumable) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onResumeTap,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text("Resume Test"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ] else if (actuallySubmitted) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onViewAnalysisTap,
                        icon: const Icon(Icons.analytics_outlined, size: 18),
                        label: const Text("View Analysis"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6200EA),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),

                    if (!isStrict) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _initiateTestFlow(context, data),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text("Retake", style: TextStyle(fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.deepPurple,
                            side: const BorderSide(color: Colors.deepPurple),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  //  LOGIC: HANDLE CLICKS & START TEST
  // ===========================================================================

  void _handleTap(BuildContext context, Map<String, dynamic> data, bool actuallySubmitted) {
    if (isResumable) {
      onResumeTap();
    } else if (actuallySubmitted) {
      onViewAnalysisTap();
    } else {
      _initiateTestFlow(context, data);
    }
  }

  Future<void> _initiateTestFlow(BuildContext context, Map<String, dynamic> data) async {
    TestMode selectedMode = TestMode.test;
    if (isStrict) {
      selectedMode = TestMode.test;
    } else {
      final userChoice = await _showModeSelectionDialog(context);
      if (userChoice == null) return;
      selectedMode = userChoice;
    }
    if (context.mounted) {
      _fetchAndLaunch(context, data, selectedMode);
    }
  }

  Future<TestMode?> _showModeSelectionDialog(BuildContext context) async {
    return showDialog<TestMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Start Assignment"),
        content: const Text("How would you like to attempt this?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, TestMode.practice),
            child: const Text("Practice Mode"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6200EA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, TestMode.test),
            child: const Text("Test Mode"),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchAndLaunch(BuildContext context, Map<String, dynamic> data, TestMode mode) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final List<dynamic> rawIds = data['questionIds'] ?? [];
      final List<String> qIds = rawIds.cast<String>();

      if (qIds.isEmpty) throw Exception("No questions in this assignment.");

      final questions = await TestOrchestrationService().getQuestionsByIds(qIds);

      Map<QuestionType, MarkingConfiguration> markingSchemes = {};
      if (data['markingSchemes'] != null && data['markingSchemes'] is Map) {
        (data['markingSchemes'] as Map).forEach((key, value) {
          QuestionType type = _mapStringToType(key.toString());
          if (type != QuestionType.unknown) {
            markingSchemes[type] = MarkingConfiguration.fromMap(Map<String, dynamic>.from(value));
          }
        });
      }

      if (context.mounted) {
        Navigator.pop(context);

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TestScreen(
              sourceId: snapshot.id,
              assignmentCode: data['assignmentCode'] ?? 'UNKNOWN',
              title: data['title'] ?? 'Assignment',
              onlySingleAttempt: data['onlySingleAttempt'] ?? false,
              questions: questions,
              timeLimitInMinutes: data['timeLimitMinutes'] ?? 30,
              testMode: mode,
              resumedTimerSeconds: null,
              resumedPageIndex: 0,
              resumedResponses: const {},
              markingSchemes: markingSchemes.isNotEmpty ? markingSchemes : null,
            ),
          ),
        );

        // Triggers refresh when user comes back
        onRefreshNeeded?.call();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error launching test: $e")),
        );
      }
    }
  }

  QuestionType _mapStringToType(String typeString) {
    switch (typeString) {
      case 'Single Correct': return QuestionType.singleCorrect;
      case 'Numerical type': return QuestionType.numerical;
      case 'One or more options correct': return QuestionType.oneOrMoreOptionsCorrect;
      case 'Single Matrix Match': return QuestionType.matrixSingle;
      case 'Multi Matrix Match': return QuestionType.matrixMulti;
      default: return QuestionType.unknown;
    }
  }
}