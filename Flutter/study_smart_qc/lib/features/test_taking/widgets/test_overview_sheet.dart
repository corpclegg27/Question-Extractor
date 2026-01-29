// lib/features/test_taking/widgets/test_overview_sheet.dart
// Description: A bottom sheet widget displaying test statistics and a navigation grid for all questions.
// UPDATED: Groups questions by Subject AND Question Type. Fixed text truncation in stats.

import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';

class TestOverviewSheet extends StatelessWidget {
  final Map<int, AnswerState> answerStates;
  final List<Question> questions; // [UPDATED] Receive full list to access types
  final Function(int) onQuestionSelected;

  const TestOverviewSheet({
    super.key,
    required this.answerStates,
    required this.questions,
    required this.onQuestionSelected,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Calculate Stats
    int answered = 0;
    int notAnswered = 0;
    int notVisited = 0;
    int markedForReview = 0;
    int ansAndMarked = 0;

    for (var i = 0; i < questions.length; i++) {
      final status = answerStates[i]?.status ?? AnswerStatus.notVisited;
      switch (status) {
        case AnswerStatus.answered:
          answered++;
          break;
        case AnswerStatus.notAnswered:
          notAnswered++;
          break;
        case AnswerStatus.notVisited:
          notVisited++;
          break;
        case AnswerStatus.markedForReview:
          markedForReview++;
          break;
        case AnswerStatus.answeredAndMarked:
          ansAndMarked++;
          break;
      }
    }

    // 2. Prepare Grouped Data: Map<Subject, Map<TypeString, List<Index>>>
    final Map<String, Map<String, List<int>>> groupedIndices = {};

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      String subject = q.subject.toUpperCase();
      if (subject.isEmpty) subject = "GENERAL";

      String type = _mapTypeToString(q.type).toUpperCase();

      groupedIndices.putIfAbsent(subject, () => {});
      groupedIndices[subject]!.putIfAbsent(type, () => []);
      groupedIndices[subject]![type]!.add(i);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // --- Header ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Test Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // --- Stats Grid (2 Columns) ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatItem(answered, "Answered", Colors.green),
                              const SizedBox(height: 12),
                              _buildStatItem(notVisited, "Not Visited", Colors.grey),
                              const SizedBox(height: 12),
                              _buildStatItem(ansAndMarked, "Answered & Marked for Review", Colors.indigo, showDot: true),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatItem(notAnswered, "Not Answered", Colors.red),
                              const SizedBox(height: 12),
                              _buildStatItem(markedForReview, "Marked for Review", Colors.purple),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Divider(thickness: 1),
                    const SizedBox(height: 16),

                    // --- Question Grid (Nested Grouping) ---
                    ...groupedIndices.keys.map((subject) {
                      final typeMap = groupedIndices[subject]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: typeMap.keys.map((type) {
                          final indices = typeMap[type]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Text(
                                  "$subject - $type",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.deepPurple),
                                ),
                              ),
                              _buildGrid(indices),
                            ],
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGrid(List<int> indices) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // 7 items per row for smaller size (~70% of standard 5)
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: indices.length,
      itemBuilder: (context, i) {
        final realIndex = indices[i];
        final state = answerStates[realIndex];
        return _buildGridItem(realIndex, state?.status ?? AnswerStatus.notVisited);
      },
    );
  }

  Widget _buildGridItem(int index, AnswerStatus status) {
    Color bg = Colors.white;
    Color text = Colors.black;
    Border? border = Border.all(color: Colors.grey.shade300);
    BoxShape shape = BoxShape.rectangle;
    Widget? badge;

    switch (status) {
      case AnswerStatus.notVisited:
        bg = Colors.white;
        text = Colors.black;
        border = Border.all(color: Colors.grey.shade400);
        break;
      case AnswerStatus.notAnswered:
        bg = Colors.red.shade600;
        text = Colors.white;
        border = null;
        break;
      case AnswerStatus.answered:
        bg = Colors.green.shade600;
        text = Colors.white;
        border = null;
        break;
      case AnswerStatus.markedForReview:
        bg = Colors.purple.shade700;
        text = Colors.white;
        border = null;
        shape = BoxShape.circle;
        break;
      case AnswerStatus.answeredAndMarked:
        bg = Colors.purple.shade700;
        text = Colors.white;
        border = null;
        shape = BoxShape.circle;
        badge = const Positioned(
          bottom: 0,
          right: 0,
          child: Icon(Icons.check_circle, size: 10, color: Colors.greenAccent),
        );
        break;
    }

    return GestureDetector(
      onTap: () => onQuestionSelected(index),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: bg,
              shape: shape,
              border: border,
              borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(6) : null,
            ),
            alignment: Alignment.center,
            child: Text(
              "${index + 1}",
              style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          if (badge != null) badge,
        ],
      ),
    );
  }

  Widget _buildStatItem(int count, String label, Color color, {bool showDot = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Align to top for wrapping text
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color),
              ),
              child: Text(
                "$count",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
              ),
            ),
            if (showDot)
              const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.check_circle, size: 12, color: Colors.green),
              )
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2.0), // Visual alignment
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              // [UPDATED] Removed overflow ellipsis to allow wrapping
            ),
          ),
        ),
      ],
    );
  }

  String _mapTypeToString(QuestionType type) {
    switch (type) {
      case QuestionType.singleCorrect: return "Single Correct";
      case QuestionType.numerical: return "Numerical";
      case QuestionType.oneOrMoreOptionsCorrect: return "Multi Correct";
      case QuestionType.matrixSingle: return "Matrix Single";
      case QuestionType.matrixMulti: return "Matrix Multi";
      default: return "Unknown";
    }
  }
}