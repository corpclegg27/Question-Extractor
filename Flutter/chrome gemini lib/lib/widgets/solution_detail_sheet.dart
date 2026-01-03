import 'package:flutter/material.dart';
import 'package:study_smart_qc/nta_test_models.dart';
import 'package:study_smart_qc/question_model.dart';
import 'package:study_smart_qc/test_result.dart'; // Added missing import

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

  String _formatTime(int totalSeconds) {
    if (totalSeconds < 60) {
      return '$totalSeconds s';
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: _currentIndex > 0 ? () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn) : null,
              ),
              Text('Solution ${_currentIndex + 1} / ${widget.result.questions.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: _currentIndex < widget.result.questions.length - 1 ? () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn) : null,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.result.questions.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final question = widget.result.questions[index];
              final answerState = widget.result.answerStates[index]!;
              final isCorrect = answerState.userAnswer == question.correctAnswer;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Question ${index + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Image.network(question.imageUrl),
                    const SizedBox(height: 20),
                    _buildAnswerStatus('Your Answer: ${answerState.userAnswer ?? "Not Answered"}', isCorrect, answerState.status),
                    const SizedBox(height: 8),
                    _buildAnswerStatus('Correct Answer: ${question.correctAnswer}', true, AnswerStatus.answered),
                    const Divider(height: 30),
                    if (question.solutionUrl != null && question.solutionUrl!.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Solution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Image.network(question.solutionUrl!),
                        ],
                      ),
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
    if (status == AnswerStatus.answered || status == AnswerStatus.answeredAndMarked) {
      color = isCorrect ? Colors.green : Colors.red;
    }
    return Row(children: [Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: color, size: 20), const SizedBox(width: 8), Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)))]);
  }
}
