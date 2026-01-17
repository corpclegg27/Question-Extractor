//lib/widgets/question_input_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';

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
  late TextEditingController _numericalController;

  @override
  void initState() {
    super.initState();
    _numericalController = TextEditingController(
        text: widget.currentAnswer?.toString() ?? ''
    );
  }

  @override
  void didUpdateWidget(covariant QuestionInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.question.id != oldWidget.question.id ||
        widget.currentAnswer != oldWidget.currentAnswer) {
      String newText = widget.currentAnswer?.toString() ?? '';
      if (_numericalController.text != newText) {
        _numericalController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _numericalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.question.type) {
      case QuestionType.singleCorrect:
        return _buildSingleCorrect();
      case QuestionType.numerical:
        return _buildNumerical();
      case QuestionType.oneOrMoreOptionsCorrect:
        return _buildMultipleCorrect();
      case QuestionType.matrixSingle:
      case QuestionType.matrixMulti:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Matrix Match is not supported in this view yet."),
          ),
        );
      case QuestionType.unknown:
      default:
        return const Center(child: Text("Unknown Question Type"));
    }
  }

  // ===========================================================================
  // 1. SINGLE CORRECT (Row of 4 Rectangles)
  // ===========================================================================
  Widget _buildSingleCorrect() {
    final options = ['A', 'B', 'C', 'D'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Row(
        children: options.map((opt) {
          final bool isSelected = (widget.currentAnswer?.toString() == opt);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: InkWell(
                onTap: () => widget.onAnswerChanged(opt),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 50, // Fixed height for the rectangle
                  decoration: BoxDecoration(
                    color: Colors.white, // Fill stays white
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      // Green if selected, Grey if not
                      color: isSelected ? Colors.green : Colors.grey.shade400,
                      // Thick border if selected (3.0 vs 1.0)
                      width: isSelected ? 3.0 : 1.0,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    opt,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      // Text turns green to match border, or stays grey
                      color: isSelected ? Colors.green : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // 2. NUMERICAL TYPE
  // ===========================================================================
  Widget _buildNumerical() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Enter your numerical answer:",
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _numericalController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: "e.g. 5 or 2.5",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6200EA), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onChanged: (val) {
              widget.onAnswerChanged(val);
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. MULTIPLE CORRECT
  // ===========================================================================
  Widget _buildMultipleCorrect() {
    final options = ['A', 'B', 'C', 'D'];

    List<String> selected = [];
    if (widget.currentAnswer is List) {
      selected = List<String>.from(widget.currentAnswer);
    } else if (widget.currentAnswer is String) {
      selected = [widget.currentAnswer];
    }

    return Column(
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return CheckboxListTile(
          title: Text("Option $opt"),
          value: isSelected,
          activeColor: const Color(0xFF6200EA),
          onChanged: (bool? checked) {
            final newSelection = List<String>.from(selected);
            if (checked == true) {
              newSelection.add(opt);
            } else {
              newSelection.remove(opt);
            }
            newSelection.sort();
            widget.onAnswerChanged(newSelection);
          },
        );
      }).toList(),
    );
  }
}