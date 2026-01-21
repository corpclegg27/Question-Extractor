// lib/widgets/solution_detail_sheet.dart
// Description: Slide-up sheet to view detailed solutions for specific questions.
// Updated to use TestResult.attempt for data and removed Self Analysis features.

import 'package:flutter/material.dart';
// For AnswerStatus enum if needed, though we use String status mostly here
import 'package:study_smart_qc/models/test_result.dart';
// Assuming AnswerStatus is here or NTA models
import 'package:study_smart_qc/widgets/expandable_image.dart';

class SolutionDetailSheet extends StatefulWidget {
  final TestResult result;
  final int initialIndex;
  final List<int>? validQuestionIndices;
  final String? categoryTitle;

  const SolutionDetailSheet({
    super.key,
    required this.result,
    required this.initialIndex,
    this.validQuestionIndices,
    this.categoryTitle,
  });

  @override
  State<SolutionDetailSheet> createState() => _SolutionDetailSheetState();
}

class _SolutionDetailSheetState extends State<SolutionDetailSheet> {
  late final PageController _pageController;
  late final List<int> _effectiveIndices;
  int _currentVisualIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.validQuestionIndices != null && widget.validQuestionIndices!.isNotEmpty) {
      _effectiveIndices = widget.validQuestionIndices!;
    } else {
      _effectiveIndices = List.generate(widget.result.questions.length, (i) => i);
    }
    final initialPage = _effectiveIndices.indexOf(widget.initialIndex);
    _currentVisualIndex = initialPage != -1 ? initialPage : 0;
    _pageController = PageController(initialPage: _currentVisualIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

  // --- SAFE FORMATTER ---
  String _formatAnswer(dynamic answer) {
    if (answer == null) return "Not Answered";
    if (answer is String) {
      if (answer.isEmpty) return "Not Answered";
      return answer;
    }
    if (answer is List) {
      if (answer.isEmpty) return "Not Answered";
      return answer.join(", ");
    }
    return answer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _effectiveIndices.length;

    return Column(
      children: [
        // --- HEADER ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 20),
                onPressed: _currentVisualIndex > 0
                    ? () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn)
                    : null,
              ),
              const Text('Solution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 20),
                onPressed: _currentVisualIndex < totalCount - 1
                    ? () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn)
                    : null,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // --- BODY ---
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: totalCount,
            onPageChanged: (index) => setState(() => _currentVisualIndex = index),
            itemBuilder: (context, index) {
              final realQuestionIndex = _effectiveIndices[index];
              final question = widget.result.questions[realQuestionIndex];

              // Access Response from Attempt Model
              // Use question.id or fallback to customId if needed
              String keyToUse = question.id;
              if (!widget.result.attempt.responses.containsKey(keyToUse)) {
                keyToUse = question.customId;
              }

              final responseObj = widget.result.attempt.responses[keyToUse];
              final timeSpentSec = responseObj?.timeSpent ?? 0;

              // Determine Status from Backend Data
              final String statusStr = responseObj?.status ?? 'SKIPPED';
              final bool isCorrect = statusStr == 'CORRECT';
              final bool isPartial = statusStr == 'PARTIALLY_CORRECT';

              // Prepare User Answer Text
              final dynamic rawUserAnswer = responseObj?.selectedOption;
              final String userAnswerText = _formatAnswer(rawUserAnswer);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Question ${realQuestionIndex + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    if (question.imageUrl.isNotEmpty)
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ExpandableImage(imageUrl: question.imageUrl),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Time Badge
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Text("Time Spent: ", style: TextStyle(fontSize: 14, color: Colors.black54)),
                          Text(_formatDuration(timeSpentSec), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                        ],
                      ),
                    ),

                    // Category Badge
                    if (widget.categoryTitle != null) ...[
                      Builder(builder: (context) {
                        final color = _getSmartColor(widget.categoryTitle!);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: color)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.label, size: 16, color: color),
                              const SizedBox(width: 8),
                              Text(widget.categoryTitle!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
                            ],
                          ),
                        );
                      }),
                    ],

                    // Your Answer
                    _buildAnswerStatus(
                      'Your Answer: $userAnswerText',
                      isCorrect,
                      isPartial,
                      statusStr,
                    ),
                    const SizedBox(height: 8),

                    // Correct Answer
                    _buildAnswerStatus(
                      'Correct Answer: ${question.actualCorrectAnswers.join(", ")}',
                      true, // Always show green tick for correct answer
                      false,
                      'CORRECT',
                    ),
                    const SizedBox(height: 20),

                    const Divider(),
                    const SizedBox(height: 10),

                    if (question.solutionUrl != null && question.solutionUrl!.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Solution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Center(
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 300),
                              child: ExpandableImage(imageUrl: question.solutionUrl!),
                            ),
                          ),
                        ],
                      )
                    else
                      const Text("No detailed solution available.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),

                    const SizedBox(height: 40),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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

    // Override for "Correct Answer" line which is always green passed as true/true
    // But since we use this helper for both, logic above handles "Your Answer".
    // For "Correct Answer" line, we pass isCorrect=true, isPartial=false, status='CORRECT'

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
}