// lib/features/analytics/widgets/student_question_review_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart';

class QuestionReviewCard extends StatelessWidget {
  final int index;
  final String questionType;
  final String? imageUrl;
  final String? solutionUrl;
  final String? aiSolutionText;
  final String status;
  final int timeSpent;
  final String smartTag;
  final String userOption;
  final String correctOption;
  final int marks;

  final bool isFixed;
  final VoidCallback? onFixToggle;

  const QuestionReviewCard({
    super.key,
    required this.index,
    required this.questionType,
    this.imageUrl,
    this.solutionUrl,
    this.aiSolutionText,
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
    // [FEATURE FLAG] Hardcoded to false for now. Set to true to enable AI solutions.
    const bool isLiveAISolutions = false;

    final bool hasImageSolution = solutionUrl != null && solutionUrl!.isNotEmpty;

    // Only show AI solution if the feature is enabled AND text is valid
    final bool hasAiSolution = isLiveAISolutions &&
        (aiSolutionText != null && aiSolutionText!.trim().length > 5);

    final bool showSolutionSection = hasImageSolution || hasAiSolution;

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
          // 1. Header Row
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
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onFixToggle != null) ...[
                GestureDetector(
                  onTap: onFixToggle,
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Text(
                          "Mark as Fixed",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isFixed ? Colors.green : Colors.grey.shade400),
                        ),
                        const SizedBox(width: 4),
                        Icon(isFixed ? Icons.check_circle : Icons.circle_outlined, size: 20, color: isFixed ? Colors.green : Colors.grey.shade300),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: marks > 0 ? Colors.green.shade50 : (marks < 0 ? Colors.red.shade50 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: marks > 0 ? Colors.green.shade200 : (marks < 0 ? Colors.red.shade200 : Colors.grey.shade300)),
                ),
                child: Text("${marks > 0 ? '+' : ''}$marks",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: marks > 0 ? Colors.green : (marks < 0 ? Colors.red : Colors.grey))),
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

          // 3. Stats Row
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Container(
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
                    Text(_formatDuration(timeSpent), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                  ],
                ),
              ),
              if (smartTag.isNotEmpty)
                Builder(builder: (context) {
                  final shortTag = smartTag.split('(').first.trim();
                  final color = _getSmartColor(shortTag);
                  return Container(
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
                        Text(shortTag, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
                      ],
                    ),
                  );
                }),
            ],
          ),
          const SizedBox(height: 16),

          // 5. Answer Status
          _buildAnswerStatus('Your Answer: $userOption', status),
          const SizedBox(height: 8),
          _buildAnswerStatus('Correct Answer: $correctOption', 'CORRECT'),

          // 6. Solution Section
          if (showSolutionSection) ...[
            const SizedBox(height: 16),
            const Divider(),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Row(
                  children: [
                    const Text("Show solution", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                    if (hasAiSolution && !hasImageSolution) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.purple.shade200),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.auto_awesome, size: 12, color: Colors.purple),
                            SizedBox(width: 4),
                            Text("AI Explained", style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    ]
                  ],
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: false,
                trailing: const Icon(Icons.expand_more, color: Colors.deepPurple),
                children: [
                  const SizedBox(height: 8),
                  // A. Image Solution (Priority)
                  if (hasImageSolution)
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: ExpandableImage(imageUrl: solutionUrl!),
                      ),
                    )
                  // B. AI Solution (Native Rendering) - Only shown if feature flag is true
                  else if (hasAiSolution)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: NativeLatexRenderer(text: aiSolutionText!),
                    ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  // --- HELPER METHODS ---

  Widget _buildAnswerStatus(String text, String statusStr) {
    bool isCorrect = statusStr == 'CORRECT';
    Color color = (statusStr == 'SKIPPED' || statusStr == 'NOT_VISITED')
        ? Colors.orange
        : (isCorrect ? Colors.green : Colors.red);
    IconData icon = (statusStr == 'SKIPPED' || statusStr == 'NOT_VISITED')
        ? Icons.warning_amber_rounded
        : (isCorrect ? Icons.check_circle : Icons.cancel);

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

// -----------------------------------------------------------------------------
// [ADVANCED CLASS] NativeLatexRenderer v2.1 (Overflow Safe)
// Renders Text + Math, ensuring long equations don't crash the UI.
// -----------------------------------------------------------------------------
class NativeLatexRenderer extends StatelessWidget {
  final String text;

  const NativeLatexRenderer({super.key, required this.text});

  String _normalizeLatex(String raw) {
    return raw
        .replaceAll(RegExp(r'^```[a-zA-Z]*'), '') // Remove code fences
        .replaceAll(RegExp(r'```$'), '')
        .replaceAll(r'\(', r'$')
        .replaceAll(r'\)', r'$')
        .replaceAll(r'\[', r'$$')
        .replaceAll(r'\]', r'$$')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    String cleanText = _normalizeLatex(text);

    // Calculate a safe max width for inline items to prevent overflow crashes.
    // Screen Width - Card Padding (32) - Inner Padding (32) - Safety Buffer (20)
    final double maxInlineWidth = MediaQuery.of(context).size.width - 84;

    List<Widget> spans = [];

    final RegExp mathPattern = RegExp(
        r'(?<!\\)\$\$(.*?)(?<!\\)\$\$|(?<!\\)\$(.*?)(?<!\\)\$',
        dotAll: true
    );

    int lastMatchEnd = 0;

    for (final match in mathPattern.allMatches(cleanText)) {
      // A. Text BEFORE the math
      if (match.start > lastMatchEnd) {
        final textPart = cleanText.substring(lastMatchEnd, match.start);
        if (textPart.trim().isNotEmpty) {
          spans.add(MarkdownBody(
            data: textPart,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
            ),
          ));
        }
      }

      // B. The Math itself
      String? blockMath = match.group(1);
      String? inlineMath = match.group(2);

      if (blockMath != null) {
        // --- BLOCK MATH ---
        // Block math naturally scrolls horizontally if wide
        spans.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  blockMath.trim(),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  onErrorFallback: (err) => Text("Math Error", style: TextStyle(color: Colors.red)),
                ),
              ),
            )
        );
      } else if (inlineMath != null) {
        // --- INLINE MATH (CRITICAL FIX) ---
        // Wrapped in ConstrainedBox + SingleChildScrollView to prevent RenderLine overflow
        spans.add(
            Container(
              constraints: BoxConstraints(maxWidth: maxInlineWidth),
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  inlineMath.trim(),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black),
                  mathStyle: MathStyle.text,
                  onErrorFallback: (err) => Text(inlineMath ?? "?", style: const TextStyle(color: Colors.red)),
                ),
              ),
            )
        );
      }

      lastMatchEnd = match.end;
    }

    // 4. Text AFTER the last math block
    if (lastMatchEnd < cleanText.length) {
      final textPart = cleanText.substring(lastMatchEnd);
      if (textPart.trim().isNotEmpty) {
        spans.add(MarkdownBody(
          data: textPart,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
          ),
        ));
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.start,
      runSpacing: 6,
      spacing: 0,
      children: spans,
    );
  }
}