import 'package:flutter/material.dart';
import '../models/question_model.dart';

class QuestionInputWidget extends StatefulWidget {
  final Question question;
  final dynamic currentAnswer;
  final Function(dynamic) onAnswerChanged;

  const QuestionInputWidget({
    Key? key,
    required this.question,
    required this.currentAnswer,
    required this.onAnswerChanged,
  }) : super(key: key);

  @override
  State<QuestionInputWidget> createState() => _QuestionInputWidgetState();
}

class _QuestionInputWidgetState extends State<QuestionInputWidget> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void didUpdateWidget(QuestionInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh text field if the question changes or answer is externally reset
    if (widget.question.id != oldWidget.question.id || widget.currentAnswer == null) {
      _textController.text = widget.currentAnswer?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.question.type) {
      case QuestionType.singleCorrect:
        return _buildSingleCorrectUI();
      case QuestionType.numerical:
        return _buildNumericalUI();
      case QuestionType.multipleCorrect:
        return _buildMultiCorrectUI();
      case QuestionType.matrixSingle:
      case QuestionType.matrixMulti:
        return _buildMatrixUI();
      default:
        return const Center(child: Text("Unknown Question Type"));
    }
  }

  // =========================================================
  // TYPE 1: SINGLE CORRECT (Radio Tiles)
  // =========================================================
  Widget _buildSingleCorrectUI() {
    final options = ['A', 'B', 'C', 'D'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: options.map((option) {
        final isSelected = widget.currentAnswer == option;
        return Expanded(
          child: GestureDetector(
            onTap: () => widget.onAnswerChanged(option),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey.shade300
                ),
              ),
              child: Center(
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // =========================================================
  // TYPE 2: NUMERICAL (Text Field)
  // =========================================================
  Widget _buildNumericalUI() {
    return TextField(
      controller: _textController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: 'Enter numerical answer (e.g. 5.5)',
      ),
      onChanged: (val) => widget.onAnswerChanged(val),
    );
  }

  // =========================================================
  // TYPE 3: MULTIPLE CORRECT (Checkboxes)
  // =========================================================
  Widget _buildMultiCorrectUI() {
    final options = ['A', 'B', 'C', 'D'];
    final List<dynamic> currentSelection = (widget.currentAnswer is List)
        ? widget.currentAnswer
        : [];

    return Row(
      children: options.map((option) {
        final isSelected = currentSelection.contains(option);
        return Expanded(
          child: GestureDetector(
            onTap: () {
              List<dynamic> newSel = List.from(currentSelection);
              if (isSelected) {
                newSel.remove(option);
              } else {
                newSel.add(option);
              }
              widget.onAnswerChanged(newSel);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.green.shade100 : Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: isSelected ? Colors.green : Colors.grey.shade300,
                    width: 2
                ),
              ),
              child: Center(child: Text(option)),
            ),
          ),
        );
      }).toList(),
    );
  }

  // =========================================================
  // TYPE 4: MATRIX MATCH (The Grid)
  // =========================================================
  Widget _buildMatrixUI() {
    // Standard JEE Matrix setup
    final rows = ['A', 'B', 'C', 'D'];
    final cols = ['P', 'Q', 'R', 'S', 'T'];

    // Safe Cast: Ensure answer is a Map. If null/wrong type, start empty.
    Map<String, List<String>> matrixAns = {};
    if (widget.currentAnswer is Map) {
      (widget.currentAnswer as Map).forEach((key, value) {
        if (value is List) {
          matrixAns[key.toString()] = List<String>.from(value);
        }
      });
    }

    return Column(
      children: [
        // 1. Header Row (Labels P, Q, R, S, T)
        Row(
          children: [
            const SizedBox(width: 40), // Empty space for row labels column
            ...cols.map((col) => Expanded(
              child: Center(
                child: Text(col, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            )),
          ],
        ),
        const Divider(),

        // 2. The Data Rows (A, B, C, D)
        ...rows.map((rowLabel) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                // Row Label
                SizedBox(
                  width: 40,
                  child: Center(
                    child: Text(
                      rowLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),

                // The Interactive Bubbles
                ...cols.map((colLabel) {
                  final rowSelections = matrixAns[rowLabel] ?? [];
                  final isSelected = rowSelections.contains(colLabel);

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        // Create a copy of the current row's selection to modify
                        List<String> newRowSel = List.from(rowSelections);

                        if (widget.question.type == QuestionType.matrixSingle) {
                          // LOGIC: Single Matrix (One choice per row)
                          newRowSel.clear();
                          if (!isSelected) {
                            newRowSel.add(colLabel);
                          }
                        } else {
                          // LOGIC: Multi Matrix (Multiple choices per row)
                          if (isSelected) {
                            newRowSel.remove(colLabel);
                          } else {
                            newRowSel.add(colLabel);
                          }
                        }

                        // Update the Main Map
                        Map<String, List<String>> newMatrixAns = Map.from(matrixAns);
                        newMatrixAns[rowLabel] = newRowSel;

                        // Send back to Controller
                        widget.onAnswerChanged(newMatrixAns);
                      },
                      child: Container(
                        height: 36, // Tap target size
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.deepPurple : Colors.grey.shade100,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isSelected ? Colors.deepPurple : Colors.grey.shade400
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 20, color: Colors.white)
                            : null,
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}