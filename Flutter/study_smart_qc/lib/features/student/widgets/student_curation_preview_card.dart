// lib/features/student/widgets/student_curation_preview_card.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StudentCurationPreviewCard extends StatelessWidget {
  // CHANGED: Accept the snapshot directly to get both ID and Data
  final QueryDocumentSnapshot snapshot;

  final bool isResumable;
  final bool isSubmitted;
  final bool isStrict;
  final VoidCallback onTap;

  const StudentCurationPreviewCard({
    super.key,
    required this.snapshot,
    required this.isResumable,
    required this.isSubmitted, // Still needed (Context depends on User, not Doc)
    required this.isStrict,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = snapshot.data() as Map<String, dynamic>;

    // 1. Parsing Data
    final Timestamp? createdAtTs = data['createdAt'];
    final Timestamp? deadlineTs = data['deadline'];

    // --- DATE LOGIC ---
    String dateLabel;
    Color dateColor;

    if (deadlineTs != null) {
      final date = deadlineTs.toDate();
      final formatted = DateFormat('MMM d, h:mm a').format(date);
      dateLabel = "Due: $formatted";

      if (date.isBefore(DateTime.now()) && !isSubmitted) {
        dateColor = Colors.red.shade700;
      } else {
        dateColor = Colors.grey.shade700;
      }
    } else {
      final date = createdAtTs?.toDate();
      dateLabel = date != null ? DateFormat('MMM d, yyyy').format(date) : 'Unknown Date';
      dateColor = Colors.grey;
    }

    final int questionCount = (data['questionIds'] as List?)?.length ?? 0;
    final String code = data['assignmentCode'] ?? '----';
    final int? storedTime = data['timeLimitMinutes'];
    final String timeDisplay = storedTime != null ? "${storedTime}m" : "${questionCount * 2}m (Est)";

    // 2. Styling Logic
    Color codeBgColor = isSubmitted
        ? Colors.teal.shade50
        : (isStrict ? Colors.red.shade50 : Colors.deepPurple.shade50);
    Color codeTextColor = isSubmitted
        ? Colors.teal.shade900
        : (isStrict ? Colors.red.shade900 : Colors.deepPurple.shade900);
    Color borderColor = isSubmitted
        ? Colors.teal.shade300
        : (isStrict ? Colors.red.shade200 : Colors.deepPurple.shade200);

    return Card(
      elevation: (isResumable || isSubmitted) ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: (isResumable || isSubmitted)
            ? const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))
            : BorderRadius.circular(12),
        side: isResumable ? BorderSide(color: Colors.deepPurple.shade300, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
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
                        color: codeBgColor,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderColor)
                    ),
                    child: Text("CODE: $code",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: codeTextColor)),
                  ),
                  Text(dateLabel,
                      style: TextStyle(fontSize: 12, color: dateColor, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(data['title'] ?? "Untitled Assignment",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),

              // Footer
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
}