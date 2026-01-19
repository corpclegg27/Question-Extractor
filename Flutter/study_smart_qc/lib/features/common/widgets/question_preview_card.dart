// lib/features/common/widgets/question_preview_card.dart

import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';

class QuestionPreviewCard extends StatefulWidget {
  final Question question;

  const QuestionPreviewCard({
    super.key,
    required this.question,
  });

  @override
  State<QuestionPreviewCard> createState() => _QuestionPreviewCardState();
}

class _QuestionPreviewCardState extends State<QuestionPreviewCard> {
  bool _showAnswer = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;

    // --- Breadcrumb Logic ---
    List<String> hierarchy = [];
    bool isValidTag(String? s) => s != null && s.isNotEmpty && !s.toLowerCase().contains('unknown');

    if (isValidTag(q.chapter)) hierarchy.add(_formatTag(q.chapter));
    if (isValidTag(q.topic)) hierarchy.add(_formatTag(q.topic));
    if (isValidTag(q.topicL2)) hierarchy.add(_formatTag(q.topicL2));

    String breadcrumbText = hierarchy.join(" > ");
    if (breadcrumbText.isEmpty) breadcrumbText = "General";

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER: ID + Type + Tags
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // QID Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "QID: ${q.customId.isNotEmpty ? q.customId : 'NA'}",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Question Type Badge
                    _buildTag(
                        _getQuestionTypeLabel(q.type),
                        Colors.blue.shade50,
                        Colors.blue.shade800
                    ),

                    const Spacer(),

                    // Difficulty Badge
                    _buildTag(q.difficulty, _getDifficultyColor(q.difficulty), Colors.black87),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: const Icon(Icons.account_tree, size: 16, color: Colors.grey),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        breadcrumbText,
                        style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // BODY: Question Image
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Question:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: Image.network(
                      q.imageUrl,
                      loadingBuilder: (ctx, child, p) => p == null ? child : const CircularProgressIndicator(),
                      errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // FOOTER
          const Divider(height: 1),
          if (!_showAnswer)
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text("Show Answer & Solution"),
                onPressed: () => setState(() => _showAnswer = true),
              ),
            ),

          if (_showAnswer)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Solution:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _showAnswer = false),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.green.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Correct Option: ", style: TextStyle(fontWeight: FontWeight.bold)),
                        // Handle List or String answer
                        Flexible(
                          child: Text(
                              (q.actualCorrectAnswers is List)
                                  ? (q.actualCorrectAnswers as List).join(", ")
                                  : q.actualCorrectAnswers.toString(),
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (q.solutionUrl != null && q.solutionUrl!.isNotEmpty)
                    Center(
                      child: Image.network(
                        q.solutionUrl!,
                        errorBuilder: (ctx, err, stack) => const Text("Solution image not available"),
                      ),
                    )
                  else
                    const Text("No detailed solution image available.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatTag(String text) {
    if (text.isEmpty) return "";
    if (text.contains(' ')) return text;
    return text.split('_').map((str) => str.isNotEmpty ? str[0].toUpperCase() + str.substring(1) : '').join(' ');
  }

  Color _getDifficultyColor(String diff) {
    switch (diff.toLowerCase()) {
      case 'easy': return Colors.green.shade100;
      case 'medium': return Colors.yellow.shade100;
      case 'hard': return Colors.red.shade100;
      default: return Colors.grey.shade200;
    }
  }

  String _getQuestionTypeLabel(QuestionType type) {
    switch (type) {
      case QuestionType.singleCorrect: return "Single Correct";
      case QuestionType.oneOrMoreOptionsCorrect: return "Multi Correct";
      case QuestionType.numerical: return "Numerical";
      case QuestionType.matrixSingle: return "Matrix (Single)";
      case QuestionType.matrixMulti: return "Matrix (Multi)";
      default: return "Unknown";
    }
  }

  Widget _buildTag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg.withOpacity(0.5)),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w500)),
    );
  }
}