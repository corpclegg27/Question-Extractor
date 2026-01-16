// lib/widgets/solution_detail_sheet.dart
// Description: Displays detailed solution for a specific question or a filtered list.
// Updated: Added Category Tag below Time Spent using exact colors from ResultsScreen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart';

class SolutionDetailSheet extends StatefulWidget {
  final TestResult result;
  final int initialIndex; // The global index of the question clicked

  // Optional: For filtering the bottom sheet to specific questions (e.g. "Perfect Attempt" only)
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

    // 1. Determine which questions to show (Filter Logic)
    if (widget.validQuestionIndices != null && widget.validQuestionIndices!.isNotEmpty) {
      _effectiveIndices = widget.validQuestionIndices!;
    } else {
      // Show all if no filter
      _effectiveIndices = List.generate(widget.result.questions.length, (i) => i);
    }

    // 2. Find the visual page index corresponding to the global question index
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

  // --- COLOR LOGIC (Identical to ResultsScreen) ---
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
                    ? () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeIn,
                )
                    : null,
              ),
              Column(
                children: [
                  Text(
                    'Solution',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 20),
                onPressed: _currentVisualIndex < totalCount - 1
                    ? () => _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeIn,
                )
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

              if (!widget.result.answerStates.containsKey(realQuestionIndex)) {
                return const Center(child: Text("Data missing for this question"));
              }

              final answerState = widget.result.answerStates[realQuestionIndex]!;
              final isCorrect = answerState.userAnswer?.trim().toLowerCase() ==
                  question.correctAnswer.trim().toLowerCase();

              final responseObj = widget.result.responses[question.id];
              final timeSpentSec = responseObj?.timeSpent ?? 0;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Question Number
                    Text(
                      'Question ${realQuestionIndex + 1}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 2. Question Image
                    if (question.imageUrl.isNotEmpty)
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ExpandableImage(imageUrl: question.imageUrl),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // 3. Time Spent
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Text("Time Spent: ",
                              style: TextStyle(
                                  fontSize: 14, color: Colors.black54)),
                          Text(
                            _formatDuration(timeSpentSec),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900),
                          ),
                        ],
                      ),
                    ),

                    // --- NEW: Category Display (Below Time Spent) ---
                    if (widget.categoryTitle != null) ...[
                      Builder(
                          builder: (context) {
                            // Get exact color from ResultsScreen logic
                            final color = _getSmartColor(widget.categoryTitle!);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: color), // Colored border
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.label, size: 16, color: color), // Colored Icon
                                  const SizedBox(width: 8),
                                  Text(
                                    "",
                                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                                  ),
                                  Text(
                                    widget.categoryTitle!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: color, // Colored Text
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                      ),
                    ],
                    // ------------------------------------------------

                    // 4. Your Answer
                    _buildAnswerStatus(
                      'Your Answer: ${answerState.userAnswer ?? "Not Answered"}',
                      isCorrect,
                      answerState.status,
                    ),
                    const SizedBox(height: 8),

                    // 5. Correct Answer
                    _buildAnswerStatus(
                      'Correct Answer: ${question.correctAnswer}',
                      true,
                      AnswerStatus.answered,
                    ),
                    const SizedBox(height: 20),

                    // --- Mistake Analysis ---
                    if (responseObj?.status == 'INCORRECT') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Self Analysis',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            _MistakeForm(
                              attemptId: widget.result.attemptId,
                              questionId: question.id,
                              initialCategory: responseObj?.mistakeCategory,
                              initialNote: responseObj?.mistakeNote,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Divider(),
                    const SizedBox(height: 10),

                    // 6. Solution Image
                    if (question.solutionUrl != null &&
                        question.solutionUrl!.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Solution',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 300),
                              child: ExpandableImage(
                                  imageUrl: question.solutionUrl!),
                            ),
                          ),
                        ],
                      )
                    else
                      const Text("No detailed solution available.",
                          style: TextStyle(
                              fontStyle: FontStyle.italic, color: Colors.grey)),

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

  Widget _buildAnswerStatus(String text, bool isCorrect, AnswerStatus status) {
    Color color = Colors.grey;
    IconData icon = Icons.help_outline;

    if (status == AnswerStatus.notAnswered ||
        status == AnswerStatus.notVisited) {
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
    } else if (status == AnswerStatus.answered ||
        status == AnswerStatus.answeredAndMarked) {
      color = isCorrect ? Colors.green : Colors.red;
      icon = isCorrect ? Icons.check_circle : Icons.cancel;
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// INTERNAL WIDGET: Mistake Form
// =============================================================================
class _MistakeForm extends StatefulWidget {
  final String attemptId;
  final String questionId;
  final String? initialCategory;
  final String? initialNote;

  const _MistakeForm({
    required this.attemptId,
    required this.questionId,
    this.initialCategory,
    this.initialNote,
  });

  @override
  State<_MistakeForm> createState() => _MistakeFormState();
}

class _MistakeFormState extends State<_MistakeForm> {
  final TestOrchestrationService _service = TestOrchestrationService();
  final TextEditingController _noteController = TextEditingController();
  String? _selectedCategory;

  final List<String> _categories = [
    'Conceptual Error',
    'Calculation Error',
    'Silly Mistake',
    'Time Pressure',
    'Did not understand question',
    'Guessed',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _noteController.text = widget.initialNote ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _categories.contains(_selectedCategory)
              ? _selectedCategory
              : null,
          hint: const Text("Why did you get this wrong?"),
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          items: _categories.map((cat) {
            return DropdownMenuItem(
              value: cat,
              child: Text(cat, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCategory = value;
            });
            _service.updateQuestionMistake(
              attemptId: widget.attemptId,
              questionId: widget.questionId,
              mistakeCategory: value ?? '',
              mistakeNote: _noteController.text,
            );
          },
        ),
      ],
    );
  }
}