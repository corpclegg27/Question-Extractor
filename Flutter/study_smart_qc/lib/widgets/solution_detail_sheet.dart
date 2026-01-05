// lib/widgets/solution_detail_sheet.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart';

class SolutionDetailSheet extends StatefulWidget {
  final TestResult result;
  final int initialIndex;
  const SolutionDetailSheet({
    super.key,
    required this.result,
    required this.initialIndex,
  });
  @override
  State<SolutionDetailSheet> createState() => _SolutionDetailSheetState();
}

class _SolutionDetailSheetState extends State<SolutionDetailSheet> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- HEADER ---
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: _currentIndex > 0
                    ? () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeIn,
                )
                    : null,
              ),
              Text(
                'Solution ${_currentIndex + 1} / ${widget.result.questions.length}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: _currentIndex < widget.result.questions.length - 1
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
            itemCount: widget.result.questions.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final question = widget.result.questions[index];
              final answerState = widget.result.answerStates[index]!;
              final isCorrect = answerState.userAnswer?.trim().toLowerCase() ==
                  question.correctAnswer.trim().toLowerCase();

              final responseObj = widget.result.responses[question.id];
              final timeSpentSec = responseObj?.timeSpent ?? 0;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Question Text
                    Text(
                      'Question ${index + 1}',
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

                    // --- MOVED: Mistake Analysis Section (Step 2) ---
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
// INTERNAL WIDGET: Mistake Form (Refined)
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

  // REMOVED 'Other' (Step 1)
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
            // Update Service with Note (even if empty, passed as '')
            _service.updateQuestionMistake(
              attemptId: widget.attemptId,
              questionId: widget.questionId,
              mistakeCategory: value ?? '',
              mistakeNote: _noteController.text, // Passed directly, 'Other' field removed
            );
          },
        ),
      ],
    );
  }
}