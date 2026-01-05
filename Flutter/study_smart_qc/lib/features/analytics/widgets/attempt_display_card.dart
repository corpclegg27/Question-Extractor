import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/attempt_model.dart';

class AttemptDisplayCard extends StatelessWidget {
  final AttemptModel attempt;
  final VoidCallback onTap;

  const AttemptDisplayCard({
    super.key,
    required this.attempt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Formatting the date
    final date = attempt.completedAt.toDate();
    final dateStr = "${date.day}/${date.month}/${date.year}";

    // UI logic for mode-based colors
    final bool isTest = attempt.mode == 'Test';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F7FB), // Light lavender tint like assignments
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Code and Date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDED6F5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "CODE: ${attempt.assignmentCode}",
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A148C),
                    ),
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Mode Label (Test/Practice)
            Text(
              "${attempt.mode} Attempt",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            // Bottom Row: Icons and Score
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      "${(attempt.timeTakenSeconds / 60).toStringAsFixed(1)} min",
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
                // Score Display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: attempt.score >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: attempt.score >= 0 ? Colors.green.shade200 : Colors.red.shade200,
                    ),
                  ),
                  child: Text(
                    "Score: ${attempt.score}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: attempt.score >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}