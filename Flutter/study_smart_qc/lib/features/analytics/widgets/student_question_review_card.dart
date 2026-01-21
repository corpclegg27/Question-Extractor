// lib/features/analytics/widgets/student_question_review_card.dart
// Description: Card displaying a single question review.
// UPDATED: Added 'Mark as Fixed' checkbox inside the header row.

import 'package:flutter/material.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart';

class QuestionReviewCard extends StatelessWidget {
  final int index;
  final String questionType;
  final String? imageUrl;
  final String? solutionUrl;
  final String status;
  final int timeSpent;
  final String smartTag;
  final String userOption;
  final String correctOption;
  final int marks;

  // [NEW] Params for fixing mistakes
  final bool isFixed;
  final VoidCallback? onFixToggle;

  const QuestionReviewCard({
    super.key,
    required this.index,
    required this.questionType,
    this.imageUrl,
    this.solutionUrl,
    required this.status,
    required this.timeSpent,
    required this.smartTag,
    required this.userOption,
    required this.correctOption,
    required this.marks,
    this.isFixed = false,
    this.onFixToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool isCorrect = status == 'CORRECT';
    final bool isPartial = status == 'PARTIALLY_CORRECT';

    // Determine colors
    Color statusColor = Colors.red;
    if (isCorrect) statusColor = Colors.green;
    if (isPartial) statusColor = Colors.orange;
    if (status == 'SKIPPED' || status == 'NOT_VISITED') statusColor = Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Row (Q No, Type, [NEW] Fixed Checkbox, Marks)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Q.${index + 1}",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  questionType.toUpperCase().replaceAll("_", " "),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // [NEW] Integrated 'Mark as Fixed' Checkbox
              if (onFixToggle != null) ...[
                GestureDetector(
                  onTap: onFixToggle,
                  child: Container(
                    color: Colors.transparent, // Hit area
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Text(
                          "Mark as Fixed",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isFixed ? Colors.green : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          isFixed ? Icons.check_circle : Icons.circle_outlined,
                          size: 20,
                          color: isFixed ? Colors.green : Colors.grey.shade300,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Marks Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: marks > 0
                      ? Colors.green.shade50
                      : (marks < 0 ? Colors.red.shade50 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: marks > 0
                        ? Colors.green.shade200
                        : (marks < 0 ? Colors.red.shade200 : Colors.grey.shade300),
                  ),
                ),
                child: Text(
                  "${marks > 0 ? '+' : ''}$marks",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: marks > 0
                        ? Colors.green
                        : (marks < 0 ? Colors.red : Colors.grey),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // 2. Question Image
          if (imageUrl != null && imageUrl!.isNotEmpty)
            Center(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ExpandableImage(imageUrl: imageUrl!),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text("Image not available", style: TextStyle(color: Colors.grey))),
            ),
          const SizedBox(height: 16),

          // 3. Time Spent
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100)
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                const Text("Time Spent: ", style: TextStyle(fontSize: 14, color: Colors.black54)),
                Text(_formatDuration(timeSpent), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
              ],
            ),
          ),

          // 4. Smart Tag
          if (smartTag.isNotEmpty)
            Builder(builder: (context) {
              final shortTag = smartTag.split('(').first.trim();
              final color = _getSmartColor(shortTag);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color)
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.label, size: 16, color: color),
                    const SizedBox(width: 8),
                    Flexible(child: Text(shortTag, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
                  ],
                ),
              );
            }),

          // 5. Answer Status
          _buildAnswerStatus('Your Answer: $userOption', isCorrect, isPartial, status),
          const SizedBox(height: 8),
          _buildAnswerStatus('Correct Answer: $correctOption', true, false, 'CORRECT'),

          // 6. Expandable Solution
          if (solutionUrl != null && solutionUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text("Show solution", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: false,
                trailing: const SizedBox.shrink(),
                children: [
                  const SizedBox(height: 8),
                  const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Solution:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ExpandableImage(imageUrl: solutionUrl!),
                    ),
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildAnswerStatus(String text, bool isCorrect, bool isPartial, String statusStr) {
    Color color = Colors.grey;
    IconData icon = Icons.help_outline;

    if (statusStr == 'SKIPPED' || statusStr == 'NOT_VISITED') {
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
    } else {
      if (isPartial) {
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
      } else {
        color = isCorrect ? Colors.green : Colors.red;
        icon = isCorrect ? Icons.check_circle : Icons.cancel;
      }
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  Color _getSmartColor(String category) {
    switch (category) {
      case "Perfect Attempt": return Colors.green.shade700;
      case "Overtime Correct": return Colors.green.shade400;
      case "Careless Mistake": return Colors.red.shade300;
      case "Wasted Attempt": return Colors.red.shade800;
      case "Good Skip": return Colors.grey.shade400;
      case "Time Wasted": return Colors.grey.shade600;
      default: return Colors.blue;
    }
  }
}