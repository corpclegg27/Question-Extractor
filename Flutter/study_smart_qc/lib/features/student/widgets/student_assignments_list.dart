// lib/features/student/widgets/student_assignments_list.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// WIDGETS
import 'package:study_smart_qc/features/student/widgets/student_curation_preview_card.dart';

class StudentAssignmentsList extends StatelessWidget {
  final List<QueryDocumentSnapshot> documents;
  final String? resumableAssignmentCode;
  final Future<void> Function() onResumeTap;
  final VoidCallback onViewAnalysisTap;
  final bool isHistoryMode;

  const StudentAssignmentsList({
    super.key,
    required this.documents,
    required this.resumableAssignmentCode,
    required this.onResumeTap,
    required this.onViewAnalysisTap,
    this.isHistoryMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              isHistoryMode
                  ? "No completed assignments yet."
                  : "No pending assignments!",
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final data = doc.data() as Map<String, dynamic>;

        final String assignmentCode = data['assignmentCode'] ?? '';
        final bool isStrict = data['onlySingleAttempt'] ?? false;
        final bool isResumable = (assignmentCode == resumableAssignmentCode);

        // The Card now handles the "New Test" logic internally
        return StudentCurationPreviewCard(
          snapshot: doc,
          isResumable: isResumable,
          isSubmitted: isHistoryMode,
          isStrict: isStrict,
          onResumeTap: onResumeTap,
          onViewAnalysisTap: onViewAnalysisTap,
        );
      },
    );
  }
}