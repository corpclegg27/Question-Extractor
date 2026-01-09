import 'package:flutter/material.dart';
// CRITICAL IMPORTS
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_enums.dart'; // <--- ADD THIS

class QuestionInputWidget extends StatefulWidget {
  final Question question;
  final dynamic currentAnswer;
  final ValueChanged<dynamic> onAnswerChanged;

  const QuestionInputWidget({
    super.key,
    required this.question,
    required this.currentAnswer,
    required this.onAnswerChanged,
  });

  @override
  State<QuestionInputWidget> createState() => _QuestionInputWidgetState();
}

class _QuestionInputWidgetState extends State<QuestionInputWidget> {
  @override
  Widget build(BuildContext context) {
    switch (widget.question.type) {
      case QuestionType.singleCorrect:
        return _buildSingleCorrect();
      case QuestionType.numerical:
        return _buildNumerical();
      case QuestionType.multipleCorrect:
        return _buildMultipleCorrect();
      case QuestionType.matrixSingle:
        return _buildMatrixMatch(isMulti: false);
      case QuestionType.matrixMulti:
        return _buildMatrixMatch(isMulti: true);
      default:
        return const Center(child: Text("Unknown Question Type"));
    }
  }

  // --- 1. Single Correct (Radio) ---
  Widget _buildSingleCorrect() {
    final List<String> options = ['A', 'B', 'C', 'D'];
    return Column(
      children: options.map((opt) {
        return RadioListTile<String>(
          title: Text("Option $opt"),
          value: opt,
          groupValue: widget.currentAnswer?.toString(),
          onChanged: (val) => widget.onAnswerChanged(val),
          activeColor: Colors.deepPurple,
        );
      }).toList(),
    );
  }

  // --- 2. Numerical (TextField) ---
  Widget _buildNumerical() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: TextField(
        controller:
            TextEditingController(text: widget.currentAnswer?.toString() ?? '')
              ..selection = TextSelection.fromPosition(
                TextPosition(
                  offset: (widget.currentAnswer?.toString() ?? '').length,
                ),
              ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: "Enter Numerical Answer",
          hintText: "e.g. 5 or 2.5",
        ),
        onChanged: (val) => widget.onAnswerChanged(val),
      ),
    );
  }

  // --- 3. Multiple Correct (Checkbox) ---
  Widget _buildMultipleCorrect() {
    final List<String> options = ['A', 'B', 'C', 'D'];
    List<String> selected = [];
    if (widget.currentAnswer is List) {
      selected = List<String>.from(widget.currentAnswer);
    } else if (widget.currentAnswer is String) {
      // Fallback if data is malformed
      selected = [widget.currentAnswer];
    }

    return Column(
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return CheckboxListTile(
          title: Text("Option $opt"),
          value: isSelected,
          onChanged: (bool? checked) {
            final newSelection = List<String>.from(selected);
            if (checked == true) {
              newSelection.add(opt);
            } else {
              newSelection.remove(opt);
            }
            newSelection.sort(); // Keep consistent order
            widget.onAnswerChanged(newSelection);
          },
          activeColor: Colors.deepPurple,
        );
      }).toList(),
    );
  }

  // --- 4. Matrix Match (Grid of Radio/Checkbox) ---
  Widget _buildMatrixMatch({required bool isMulti}) {
    // Rows: A, B, C, D
    // Cols: p, q, r, s, t
    final rows = ['A', 'B', 'C', 'D'];
    final cols = ['p', 'q', 'r', 's', 't'];

    // Structure: Map<String, List<String>>  e.g. {'A': ['p'], 'B': ['q', 'r']}
    Map<String, List<String>> matrixState = {};
    if (widget.currentAnswer is Map) {
      matrixState = Map<String, List<String>>.from(
        (widget.currentAnswer as Map).map(
          (k, v) => MapEntry(k.toString(), List<String>.from(v ?? [])),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          const DataColumn(label: Text('')), // Corner
          ...cols.map((c) => DataColumn(label: Text(c))),
        ],
        rows: rows.map((rowKey) {
          return DataRow(
            cells: [
              DataCell(
                Text(
                  rowKey,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ), // Row Header
              ...cols.map((colKey) {
                final currentSelections = matrixState[rowKey] ?? [];
                final isSelected = currentSelections.contains(colKey);

                return DataCell(
                  isMulti
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (val) {
                            final newRowSelections = List<String>.from(
                              currentSelections,
                            );
                            if (val == true) {
                              newRowSelections.add(colKey);
                            } else {
                              newRowSelections.remove(colKey);
                            }
                            newRowSelections.sort();

                            final newState = Map<String, List<String>>.from(
                              matrixState,
                            );
                            newState[rowKey] = newRowSelections;
                            widget.onAnswerChanged(newState);
                          },
                        )
                      : Radio<String>(
                          value: colKey,
                          groupValue: currentSelections.isNotEmpty
                              ? currentSelections.first
                              : null,
                          onChanged: (val) {
                            final newState = Map<String, List<String>>.from(
                              matrixState,
                            );
                            newState[rowKey] = [val!]; // Single select per row
                            widget.onAnswerChanged(newState);
                          },
                        ),
                );
              }),
            ],
          );
        }).toList(),
      ),
    );
  }
}
