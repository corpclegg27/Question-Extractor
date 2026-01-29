// lib/features/analytics/widgets/attempt_display_card.dart
// Description: Card widget to display a single attempt summary.
// UPDATED: Supports optional 'studentName' & 'studentId' for Teacher View.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/models/attempt_model.dart';

class AttemptDisplayCard extends StatelessWidget {
  final AttemptModel attempt;
  final VoidCallback onTap;

  // [NEW] Optional fields for Teacher Context
  final String? studentName;
  final String? studentId;

  const AttemptDisplayCard({
    super.key,
    required this.attempt,
    required this.onTap,
    this.studentName,
    this.studentId,
  });

  String _formatDurationClean(int seconds) {
    if (seconds < 60) return "${seconds}s";
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    if (s == 0) return "${m}m";
    return "${m}m ${s}s";
  }

  /// Returns a record containing the [BarColor] and a darker [TextColor]
  ({Color bar, Color text}) _getDynamicColors(double score, double max) {
    if (score < 0) {
      return (bar: const Color(0xFFD32F2F), text: const Color(0xFFB71C1C));
    }
    if (max == 0) {
      return (bar: Colors.grey, text: Colors.grey.shade700);
    }

    final double percentage = (score / max).clamp(0.0, 1.0);
    Color color;

    if (percentage < 0.4) {
      final t = percentage / 0.4;
      color = Color.lerp(Colors.deepOrange, Colors.orange, t)!;
    } else if (percentage < 0.75) {
      final t = (percentage - 0.4) / 0.35;
      color = Color.lerp(Colors.orange, Colors.lightGreen.shade600, t)!;
    } else {
      final t = (percentage - 0.75) / 0.25;
      color = Color.lerp(Colors.green, const Color(0xFF1B5E20), t)!;
    }

    final HSLColor hsl = HSLColor.fromColor(color);
    final Color textColor = hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();

    return (bar: color, text: textColor);
  }

  @override
  Widget build(BuildContext context) {
    // --- Data Prep ---
    final date = attempt.completedAt.toDate();
    final dateStr = DateFormat('MMM d, h:mm a').format(date);

    final int timeTakenSec = attempt.timeTakenSeconds;
    final int timeLimitMin = attempt.timeLimitMinutes ?? 0;
    final int timeLimitSec = timeLimitMin * 60;

    String timeDisplay = _formatDurationClean(timeTakenSec);
    if (timeLimitMin > 0) timeDisplay += " / ${timeLimitMin}m";

    double timePercentage = (timeLimitSec > 0)
        ? (timeTakenSec / timeLimitSec).clamp(0.0, 1.0)
        : 0.0;

    final double maxScore = attempt.maxMarks.toDouble();
    final double score = attempt.score.toDouble();
    final bool isPositive = score >= 0;

    double scorePercentage = (maxScore == 0)
        ? 0
        : (score.abs() / maxScore).clamp(0.0, 1.0);

    // --- Dynamic Colors ---
    final themeColors = _getDynamicColors(score, maxScore);
    final Color statusColor = themeColors.bar;
    final Color statusTextColor = themeColors.text;
    final Color trackColor = Colors.grey.shade100;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D2F45).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- 1. DYNAMIC COLORED STRIP ---
                Container(width: 6, color: statusColor),

                // --- 2. MAIN CONTENT ---
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // [NEW] TEACHER VIEW HEADER (Only visible if name provided)
                        if (studentName != null) ...[
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.deepPurple.shade50,
                                child: Text(
                                  studentName!.isNotEmpty ? studentName![0].toUpperCase() : 'S',
                                  style: TextStyle(color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      studentName!,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      "ID: $studentId",
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                        ],

                        // Standard Header (Code + Date)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3E5F5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "CODE: ${attempt.assignmentCode}",
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7B1FA2), letterSpacing: 0.5),
                              ),
                            ),
                            Text(dateStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Title
                        Text(
                          attempt.title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF2D2D2D), height: 1.2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 20),

                        // Stats: Time
                        if (timeLimitSec > 0) ...[
                          _buildStatRow(
                            icon: Icons.access_time_rounded,
                            label: "Time Taken",
                            value: timeDisplay,
                            color: const Color(0xFFFF9800),
                            percent: timePercentage,
                            trackColor: trackColor,
                          ),
                          const SizedBox(height: 16),
                        ] else ...[
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text(timeDisplay, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Stats: Score
                        _buildStatRow(
                          icon: isPositive ? Icons.analytics_outlined : Icons.warning_amber_rounded,
                          label: isPositive ? "Score" : "Negative Score",
                          value: "${attempt.score.toStringAsFixed(0)} / ${attempt.maxMarks.toStringAsFixed(0)}",
                          color: statusColor,
                          valueColor: statusTextColor,
                          percent: scorePercentage,
                          trackColor: trackColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    Color? valueColor,
    required double percent,
    required Color trackColor,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              ],
            ),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: valueColor ?? color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: percent.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value,
                backgroundColor: trackColor,
                color: color,
                minHeight: 8,
              );
            },
          ),
        ),
      ],
    );
  }
}