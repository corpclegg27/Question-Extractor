import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';

class QuestionPalette extends StatelessWidget {
  final int questionCount;
  final Map<int, AnswerState> answerStates;
  final int currentQuestionIndex;
  final Function(int) onQuestionTapped;

  const QuestionPalette({
    super.key,
    required this.questionCount,
    required this.answerStates,
    required this.currentQuestionIndex,
    required this.onQuestionTapped,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: questionCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final state = answerStates[index] ?? AnswerState();
        final isCurrent = index == currentQuestionIndex;

        return GestureDetector(
          onTap: () => onQuestionTapped(index),
          child: Container(
            decoration: BoxDecoration(
              color: state.status.color,
              borderRadius: BorderRadius.circular(4),
              border: isCurrent ? Border.all(color: Colors.black, width: 2) : null,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
