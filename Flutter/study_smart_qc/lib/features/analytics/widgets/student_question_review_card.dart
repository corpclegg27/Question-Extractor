// lib/features/analytics/widgets/student_question_review_card.dart
// Description: Displays a single question review card with stats, status, and solution.
// - [UPDATED] Converted to StatefulWidget to handle on-demand AI generation.
// - Uses AiSolutionService to fetch solutions if missing.
// - Renders Image Solutions (Priority 1) or AI Text Solutions (Priority 2).
// - Includes NativeLatexRenderer for safe math rendering.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart';
import 'package:study_smart_qc/core/services/ai_solution_service.dart';

class QuestionReviewCard extends StatefulWidget {
  final String questionId; // [NEW] Required for API call
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
    required this.questionId,
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
  State<QuestionReviewCard> createState() => _QuestionReviewCardState();
}

class _QuestionReviewCardState extends State<QuestionReviewCard> {
  final AiSolutionService _aiService = AiSolutionService();

  // State variables for dynamic generation
  bool _isGenerating = false;
  String? _generatedSolution;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Initialize with the data passed from parent (if any)
    _generatedSolution = widget.aiSolutionText;
  }

  /// Triggers the cloud function to get the solution
  Future<void> _handleGenerateSolution() async {
    setState(() => _isGenerating = true);

    try {
      // Call our new Service
      final solution = await _aiService.generateSolution(widget.questionId);

      if (mounted) {
        setState(() {
          _generatedSolution = solution;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception:", "").trim()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Determine what we have
    final bool hasImageSolution = widget.solutionUrl != null && widget.solutionUrl!.isNotEmpty;
    final bool hasTextSolution = _generatedSolution != null && _generatedSolution!.trim().length > 5;

    // 2. Should we show the "Solution" section at all?
    // We show it if we have a solution OR if we can generate one.
    final bool showSolutionSection = true;

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
          // --- HEADER ROW ---
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Q.${widget.index + 1}",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.questionType.toUpperCase().replaceAll("_", " "),
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onFixToggle != null) ...[
                GestureDetector(
                  onTap: widget.onFixToggle,
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Text(
                          "Mark as Fixed",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: widget.isFixed ? Colors.green : Colors.grey.shade400),
                        ),
                        const SizedBox(width: 4),
                        Icon(widget.isFixed ? Icons.check_circle : Icons.circle_outlined, size: 20, color: widget.isFixed ? Colors.green : Colors.grey.shade300),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.marks > 0 ? Colors.green.shade50 : (widget.marks < 0 ? Colors.red.shade50 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: widget.marks > 0 ? Colors.green.shade200 : (widget.marks < 0 ? Colors.red.shade200 : Colors.grey.shade300)),
                ),
                child: Text("${widget.marks > 0 ? '+' : ''}${widget.marks}",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: widget.marks > 0 ? Colors.green : (widget.marks < 0 ? Colors.red : Colors.grey))),
              ),
            ],
          ),
          const Divider(height: 24),

          // --- QUESTION IMAGE ---
          if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
            Center(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ExpandableImage(imageUrl: widget.imageUrl!),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text("Image not available", style: TextStyle(color: Colors.grey))),
            ),
          const SizedBox(height: 16),

          // --- STATS ROW ---
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
                    Text(_formatDuration(widget.timeSpent), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                  ],
                ),
              ),
              if (widget.smartTag.isNotEmpty)
                Builder(builder: (context) {
                  final shortTag = widget.smartTag.split('(').first.trim();
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

          // --- ANSWER STATUS ---
          _buildAnswerStatus('Your Answer: ${widget.userOption}', widget.status),
          const SizedBox(height: 8),
          _buildAnswerStatus('Correct Answer: ${widget.correctOption}', 'CORRECT'),

          // --- SOLUTION SECTION ---
          if (showSolutionSection) ...[
            const SizedBox(height: 16),
            const Divider(),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Row(
                  children: [
                    const Text("Show solution", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),

                    // Show "AI Explained" Badge if we have a text solution
                    if (hasTextSolution && !hasImageSolution) ...[
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
                onExpansionChanged: (val) => setState(() => _isExpanded = val),
                trailing: const Icon(Icons.expand_more, color: Colors.deepPurple),
                children: [
                  const SizedBox(height: 8),

                  // A. Image Solution (Priority 1)
                  if (hasImageSolution)
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: ExpandableImage(imageUrl: widget.solutionUrl!),
                      ),
                    )

                  // B. AI Solution (Priority 2)
                  else if (hasTextSolution)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: NativeLatexRenderer(text: _generatedSolution!),
                    )

                  // C. No Solution? Show Generate Button
                  else
                    _buildGenerateButton(),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS & HELPERS ---

  Widget _buildGenerateButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          const Icon(Icons.psychology, size: 40, color: Colors.deepPurpleAccent),
          const SizedBox(height: 12),
          const Text(
            "No solution available yet.",
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            "Our AI Tutor can explain this step-by-step.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          if (_isGenerating)
            const SizedBox(
              height: 40,
              width: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            ElevatedButton.icon(
              onPressed: _handleGenerateSolution,
              icon: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
              label: const Text("Generate AI Solution"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
    );
  }

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