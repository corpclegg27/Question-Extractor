// lib/features/analytics/widgets/attempt_display_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/models/attempt_model.dart';

class AttemptDisplayCard extends StatelessWidget {
  final AttemptModel attempt;
  final VoidCallback onTap;

  const AttemptDisplayCard({
    super.key,
    required this.attempt,
    required this.onTap,
  });

  String _formatDurationClean(int seconds) {
    if (seconds < 60) return "${seconds}s";
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    if (s == 0) return "${m}m";
    return "${m}m ${s}s";
  }

  @override
  Widget build(BuildContext context) {
    // 1. Data Prep
    final date = attempt.completedAt.toDate();
    final dateStr = DateFormat('d MMM yy, h:mm a').format(date);

    // Time Logic
    String timeDisplay = _formatDurationClean(attempt.timeTakenSeconds);
    if (attempt.timeLimitMinutes != null && attempt.timeLimitMinutes! > 0) {
      timeDisplay += " / ${attempt.timeLimitMinutes}m";
    }

    // Score Logic
    final double max = attempt.maxMarks.toDouble();
    final double score = attempt.score.toDouble();
    final bool isPositive = score >= 0;

    // Percentage Calculation
    // If Positive: 15/20 = 0.75
    // If Negative: |-5|/20 = 0.25 (Visually shows magnitude of 'damage')
    // We clamp it to 1.0 just in case of bonus marks or errors
    double percentage = (max == 0) ? 0 : (score.abs() / max).clamp(0.0, 1.0);

    // Colors
    final Color primaryColor = isPositive ? Colors.green : Colors.red;
    final Color trackColor = Colors.grey.shade200;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F7FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TITLE ROW ---
            Text(
              attempt.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // --- METADATA ROW (Code + Date) ---
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
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4A148C)),
                  ),
                ),
                Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),

            // --- MODE & TIME ROW ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.category_outlined, size: 16, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Text("${attempt.mode} Mode", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87)),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 4),
                    Text(timeDisplay, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // --- VISUAL SCORE BAR ---
            // Label Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    isPositive ? "Score Acquired" : "Score Lost (Negative)", // Smart Label
                    style: TextStyle(
                        fontSize: 11,
                        color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                        fontWeight: FontWeight.w600
                    )
                ),
                Text(
                  "${attempt.score} / ${attempt.maxMarks}",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primaryColor
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // The Bar Itself
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                backgroundColor: trackColor,
                color: primaryColor,
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}