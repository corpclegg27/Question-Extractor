// lib/features/batches/widgets/student_display_card.dart
// Description: A reusable card to display student details (Name, ID, Stats).
// Accepts an optional 'trailing' widget (e.g., Checkbox) for flexibility.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/models/user_model.dart';

class StudentDisplayCard extends StatelessWidget {
  final UserModel user;
  final Widget? trailing; // Optional: Pass a Checkbox, Delete Button, or null

  const StudentDisplayCard({
    super.key,
    required this.user,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    // Format Date: "Jan 19, 2026"
    final String joinedDate = DateFormat('MMM d, y').format(user.createdAt.toDate());

    // Calculate Stats
    final int submittedCount = user.assignmentCodesSubmitted.length;
    final String targetInfo = "${user.targetExam} ${user.targetYear}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Align to top
        children: [
          // 1. Avatar / Initials
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.deepPurple.shade50,
            child: Text(
              (user.displayName.isNotEmpty ? user.displayName[0] : 'S').toUpperCase(),
              style: TextStyle(
                color: Colors.deepPurple.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 2. Main Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name & ID
                Text(
                  user.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "ID: ${user.studentId} • ${user.currentClass}",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),

                // Stats Row (Joined, Target, Submitted)
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _buildStatPill(Icons.calendar_today, "Joined $joinedDate"),
                    _buildStatPill(Icons.flag, targetInfo),
                    _buildStatPill(Icons.assignment_turned_in, "$submittedCount submitted"),
                  ],
                ),
              ],
            ),
          ),

          // 3. Optional Trailing Widget (Checkbox)
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _buildStatPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}