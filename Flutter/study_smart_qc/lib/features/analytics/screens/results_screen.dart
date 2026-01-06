// lib/features/analytics/screens/results_screen.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/widgets/solution_detail_sheet.dart';

class ResultsScreen extends StatefulWidget {
  final TestResult result;

  const ResultsScreen({super.key, required this.result});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  // Stats
  int marksObtained = 0;
  double accuracy = 0.0;
  double attemptPercentage = 0.0;

  // Basic Categories (For the top chart)
  List<int> correctIndices = [];
  List<int> incorrectIndices = [];
  List<int> skippedIndices = [];
  List<int> reviewIndices = [];

  // Smart Analysis Categories (Key = Category Name, Value = List of Question Indices)
  final Map<String, List<int>> _smartAnalysisGroups = {
    "Perfect Attempt": [],
    "Overtime Correct": [],
    "Careless Mistake": [],
    "Wasted Attempt": [],
    "Good Skip": [],
    "Time Wasted": [],
  };

  // Friendly coaching descriptions for the UI
  final Map<String, String> _categoryDescriptions = {
    "Perfect Attempt": "You nailed it! You got the answer right and managed your time perfectly within the subject's limit.",
    "Overtime Correct": "You got it right! You reached the correct answer, though you spent a bit more time than the ideal limit for this subject.",
    "Careless Mistake": "Slow down a bit! You answered very quickly but unfortunately missed this one. Double-check your work next time.",
    "Wasted Attempt": "Don't get stuck! You spent a lot of time here but didn't quite get the right answer. It might be time to review this concept.",
    "Good Skip": "Great tactical move! You recognized a tough one early and skipped it quickly to save your time for other questions.",
    "Time Wasted": "Careful with the clock! You spent quite a while on this before skipping. Try to decide to move on a little sooner next time.",
  };

  @override
  void initState() {
    super.initState();
    _calculateResults();
  }

  void _calculateResults() {
    correctIndices.clear();
    incorrectIndices.clear();
    skippedIndices.clear();
    reviewIndices.clear();

    for (var key in _smartAnalysisGroups.keys) {
      _smartAnalysisGroups[key] = [];
    }

    int tempCorrectCount = 0;
    int tempIncorrectCount = 0;

    for (int i = 0; i < widget.result.questions.length; i++) {
      final question = widget.result.questions[i];
      final qId = question.id;

      String basicStatus = 'SKIPPED';

      if (widget.result.responses.containsKey(qId)) {
        basicStatus = widget.result.responses[qId]!.status;
      } else {
        final state = widget.result.answerStates[i];
        if (state?.status == AnswerStatus.answered || state?.status == AnswerStatus.answeredAndMarked) {
          final isCorrect = state?.userAnswer?.trim().toLowerCase() == question.correctAnswer.trim().toLowerCase();
          basicStatus = isCorrect ? 'CORRECT' : 'INCORRECT';
        } else if (state?.status == AnswerStatus.markedForReview) {
          basicStatus = 'REVIEW';
        }
      }

      switch (basicStatus) {
        case 'CORRECT':
          correctIndices.add(i);
          tempCorrectCount++;
          break;
        case 'INCORRECT':
          incorrectIndices.add(i);
          tempIncorrectCount++;
          break;
        case 'REVIEW':
          reviewIndices.add(i);
          skippedIndices.add(i);
          break;
        default:
          skippedIndices.add(i);
          break;
      }

      if (widget.result.responses.containsKey(qId)) {
        final response = widget.result.responses[qId]!;
        final tag = response.smartTimeAnalysis;

        if (tag.contains("Perfect Attempt")) {
          _smartAnalysisGroups["Perfect Attempt"]!.add(i);
        } else if (tag.contains("Overtime Correct")) {
          _smartAnalysisGroups["Overtime Correct"]!.add(i);
        } else if (tag.contains("Careless Mistake")) {
          _smartAnalysisGroups["Careless Mistake"]!.add(i);
        } else if (tag.contains("Wasted Attempt")) {
          _smartAnalysisGroups["Wasted Attempt"]!.add(i);
        } else if (tag.contains("Good Skip")) {
          _smartAnalysisGroups["Good Skip"]!.add(i);
        } else if (tag.contains("Time Wasted")) {
          _smartAnalysisGroups["Time Wasted"]!.add(i);
        }
      }
    }

    setState(() {
      int totalAttempted = tempCorrectCount + tempIncorrectCount;
      marksObtained = (tempCorrectCount * 4) - (tempIncorrectCount * 1);
      accuracy = (totalAttempted > 0) ? (tempCorrectCount / totalAttempted) * 100 : 0.0;
      attemptPercentage = (widget.result.questions.isNotEmpty)
          ? (totalAttempted / widget.result.questions.length) * 100
          : 0.0;
    });
  }

  void _showSolutionSheet(int initialIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: SolutionDetailSheet(
            result: widget.result,
            initialIndex: initialIndex,
          ),
        );
      },
    );
  }

  String get _formattedTimeTaken {
    final minutes = widget.result.timeTaken.inMinutes.toString().padLeft(2, '0');
    final seconds = (widget.result.timeTaken.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Color _getSmartColor(String category) {
    switch (category) {
      case "Perfect Attempt": return Colors.green.shade800;
      case "Overtime Correct": return Colors.green.shade300;
      case "Careless Mistake": return Colors.red.shade200;
      case "Wasted Attempt": return Colors.red.shade900;
      case "Good Skip": return Colors.grey.shade400;
      case "Time Wasted": return Colors.grey.shade700;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Analysis'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildScoreCard(),
            const SizedBox(height: 20),
            _buildStatsRow(),
            const SizedBox(height: 20),
            _buildPerformanceDistributionChart(),
            const SizedBox(height: 24),
            const Divider(thickness: 2),
            const SizedBox(height: 24),
            const Text(
              "Smart Time Analysis",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
            ),
            const SizedBox(height: 20),
            _buildSmartAnalysisChart(),
            const SizedBox(height: 20),
            _buildSmartAnalysisList(),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    double percentage = (widget.result.totalMarks > 0)
        ? (marksObtained / widget.result.totalMarks) * 100
        : 0;
    String motivation = percentage >= 75 ? 'Excellent Work!' : percentage >= 50 ? 'Good Effort!' : 'Keep Improving!';
    return Card(
      color: Colors.deepPurple.shade700,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text('Marks Obtained', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16)),
            const SizedBox(height: 8),
            Text('$marksObtained / ${widget.result.totalMarks}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(motivation, style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard('Accuracy', '${accuracy.toStringAsFixed(0)}%', Icons.track_changes, Colors.blue),
        _buildStatCard('Attempt %', '${attemptPercentage.toStringAsFixed(0)}%', Icons.rule, Colors.orange),
        _buildStatCard('Time Taken', _formattedTimeTaken, Icons.timer_outlined, Colors.purple),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPerformanceDistributionChart() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Performance Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  startDegreeOffset: 270, // Starts at 12 o'clock
                  sections: [
                    PieChartSectionData(
                        value: correctIndices.length.toDouble(),
                        title: '${correctIndices.length}',
                        color: Colors.green,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                    PieChartSectionData(
                        value: incorrectIndices.length.toDouble(),
                        title: '${incorrectIndices.length}',
                        color: Colors.red,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                    PieChartSectionData(
                        value: skippedIndices.length.toDouble(),
                        title: '${skippedIndices.length}',
                        color: Colors.grey.shade300,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildLegendItem(Colors.green, 'Correct'),
                _buildLegendItem(Colors.red, 'Incorrect'),
                _buildLegendItem(Colors.grey.shade300, 'Unattempted'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartAnalysisChart() {
    final activeCategories = _smartAnalysisGroups.entries.where((e) => e.value.isNotEmpty).toList();

    if (activeCategories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text("Not enough data for smart analysis.")),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  startDegreeOffset: 270, // Starts at 12 o'clock
                  sections: activeCategories.map((entry) {
                    final color = _getSmartColor(entry.key);
                    return PieChartSectionData(
                      value: entry.value.length.toDouble(),
                      title: '${entry.value.length}',
                      color: color,
                      radius: 60,
                      titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: activeCategories.map((entry) {
                return _buildLegendItem(_getSmartColor(entry.key), entry.key);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildSmartAnalysisList() {
    final orderedKeys = [
      "Perfect Attempt",
      "Overtime Correct",
      "Careless Mistake",
      "Wasted Attempt",
      "Good Skip",
      "Time Wasted"
    ];

    return Column(
      children: orderedKeys.map((key) {
        final indices = _smartAnalysisGroups[key] ?? [];
        if (indices.isEmpty) return const SizedBox.shrink();

        final color = _getSmartColor(key);
        final description = _categoryDescriptions[key] ?? "";

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                      child: Icon(Icons.label, size: 16, color: color),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      key,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${indices.length}",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Coaching full text
                Text(
                  description,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: indices.map((index) {
                    return GestureDetector(
                      onTap: () => _showSolutionSheet(index),
                      child: Container(
                        width: 45,
                        height: 35,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: color.withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: color.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))
                            ]
                        ),
                        child: Text(
                          'Q${index + 1}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}