import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/question_model.dart';

class QuestionPreviewCard extends StatefulWidget {
  final Question question;
  final bool isExpanded; // If true, shows full details initially

  const QuestionPreviewCard({
    super.key,
    required this.question,
    this.isExpanded = false,
  });

  @override
  State<QuestionPreviewCard> createState() => _QuestionPreviewCardState();
}

class _QuestionPreviewCardState extends State<QuestionPreviewCard> {
  bool _showAnswer = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER: ID + Tags
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "QID: ${q.id}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // UPDATED TAGS: Source -> Chapter -> Topic -> Difficulty
                        if (q.exam.isNotEmpty) ...[
                          _buildTag(q.exam, Colors.blue.shade50, Colors.blue.shade700),
                          const SizedBox(width: 5),
                        ],
                        if (q.chapterId.isNotEmpty) ...[
                          _buildTag(_formatTag(q.chapterId), Colors.orange.shade50, Colors.orange.shade800),
                          const SizedBox(width: 5),
                        ],
                        _buildTag(_formatTag(q.topicId), Colors.grey.shade100, Colors.grey.shade700),
                        const SizedBox(width: 5),
                        _buildTag(q.difficulty, _getDifficultyColor(q.difficulty), Colors.black87),
                      ],
                    ),
                  ),
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

          // FOOTER: Show Answer Toggle
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

          // ANSWER SECTION (Conditional)
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

                  // CORRECT ANSWER TEXT
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
                        Text(q.correctAnswer, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // SOLUTION IMAGE
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

  // Helper to clean up ID strings (e.g., "ray_optics" -> "Ray Optics")
  String _formatTag(String text) {
    if (text.isEmpty) return "";
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