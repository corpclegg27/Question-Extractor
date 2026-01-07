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

  // Consistent ordering for behavioral analysis
  final List<String> _behavioralOrder = [
    "Perfect Attempt",
    "Overtime Correct",
    "Careless Mistake",
    "Wasted Attempt",
    "Good Skip",
    "Time Wasted"
  ];

  // Basic Categories
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

        for (var key in _behavioralOrder) {
          if (tag.contains(key)) {
            _smartAnalysisGroups[key]!.add(i);
            break;
          }
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

  String _formatSeconds(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m}m ${s}s';
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
            const SizedBox(height: 30),

            // 1. # Questions by Result
            _buildHeader("# Questions by Result"),
            _buildPerformanceDistributionChart(),
            const SizedBox(height: 30),

            // 2. Time spent by Result
            _buildHeader("Time spent by Result"),
            _buildTimeSpentByResultChart(),
            const SizedBox(height: 30),

            // 3. # Questions by Behavior
            _buildHeader("# Questions by Behavior"),
            _buildSmartAnalysisChart(),
            const SizedBox(height: 30),

            // 4. Time spent by Behavior
            _buildHeader("Time spent by Behavior"),
            _buildTimeSpentByBehaviorChart(),
            const SizedBox(height: 30),

            // 5. Categorized Questions
            _buildHeader("Questions Breakdown"),
            _buildSmartAnalysisList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
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

  // --- CHART 1: # Questions by Result ---
  Widget _buildPerformanceDistributionChart() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  startDegreeOffset: 270,
                  sections: [
                    _buildSection(correctIndices.length.toDouble(), '${correctIndices.length}', Colors.green),
                    _buildSection(incorrectIndices.length.toDouble(), '${incorrectIndices.length}', Colors.red),
                    _buildSection(skippedIndices.length.toDouble(), '${skippedIndices.length}', Colors.grey.shade300, textColor: Colors.black54),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
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

  // --- CHART 2: Time Spent by Result ---
  Widget _buildTimeSpentByResultChart() {
    final Map<String, int> timeMap = {"CORRECT": 0, "INCORRECT": 0, "SKIPPED": 0};
    for (var resp in widget.result.responses.values) {
      String status = (resp.status == "REVIEW") ? "SKIPPED" : resp.status;
      timeMap[status] = (timeMap[status] ?? 0) + resp.timeSpent;
    }
    final total = timeMap.values.fold(0, (sum, item) => sum + item);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              height: 180,
              child: total == 0 ? const Center(child: Text("No time data recorded")) : PieChart(
                PieChartData(
                  sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270,
                  sections: [
                    _buildTimeSection(timeMap["CORRECT"]!, total, Colors.green),
                    _buildTimeSection(timeMap["INCORRECT"]!, total, Colors.red),
                    _buildTimeSection(timeMap["SKIPPED"]!, total, Colors.grey.shade300, textColor: Colors.black54),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
              children: [
                _buildLegendItem(Colors.green, 'Correct (${_formatSeconds(timeMap["CORRECT"]!)})'),
                _buildLegendItem(Colors.red, 'Incorrect (${_formatSeconds(timeMap["INCORRECT"]!)})'),
                _buildLegendItem(Colors.grey.shade300, 'Skipped (${_formatSeconds(timeMap["SKIPPED"]!)})'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- CHART 3: # Questions by Behavior ---
  Widget _buildSmartAnalysisChart() {
    List<PieChartSectionData> sections = [];
    for (var key in _behavioralOrder) {
      final count = _smartAnalysisGroups[key]!.length;
      if (count > 0) {
        sections.add(_buildSection(count.toDouble(), '$count', _getSmartColor(key)));
      }
    }

    if (sections.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text("Not enough behavioral data"))));

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270,
                  sections: sections,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
              children: _behavioralOrder
                  .where((key) => _smartAnalysisGroups[key]!.isNotEmpty)
                  .map((key) => _buildLegendItem(_getSmartColor(key), key))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // --- CHART 4: Time Spent by Behavior ---
  Widget _buildTimeSpentByBehaviorChart() {
    Map<String, int> timeMap = {};
    for (var resp in widget.result.responses.values) {
      String tag = resp.smartTimeAnalysis.split(' (').first.trim();
      if (tag.isNotEmpty) timeMap[tag] = (timeMap[tag] ?? 0) + resp.timeSpent;
    }

    final total = timeMap.values.fold(0, (sum, item) => sum + item);
    List<PieChartSectionData> sections = [];

    for (var key in _behavioralOrder) {
      final time = timeMap[key] ?? 0;
      if (time > 0) {
        sections.add(_buildTimeSection(time, total, _getSmartColor(key)));
      }
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              height: 180,
              child: total == 0 ? const Center(child: Text("No time data recorded")) : PieChart(
                PieChartData(
                  sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270,
                  sections: sections,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
              children: _behavioralOrder
                  .where((key) => (timeMap[key] ?? 0) > 0)
                  .map((key) => _buildLegendItem(_getSmartColor(key), '$key (${_formatSeconds(timeMap[key] ?? 0)})'))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // --- CHART HELPERS ---
  PieChartSectionData _buildSection(double value, String title, Color color, {Color textColor = Colors.white}) {
    return PieChartSectionData(
      value: value, title: title, color: color, radius: 50,
      titleStyle: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
    );
  }

  PieChartSectionData _buildTimeSection(int value, int total, Color color, {Color textColor = Colors.white}) {
    final percent = total > 0 ? (value / total * 100).toStringAsFixed(0) : '0';
    return PieChartSectionData(
      value: value.toDouble(), title: '$percent%', color: color, radius: 50,
      titleStyle: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  // --- LIST BREAKDOWN ---
  Widget _buildSmartAnalysisList() {
    return Column(
      children: _behavioralOrder.map((key) {
        final indices = _smartAnalysisGroups[key] ?? [];
        if (indices.isEmpty) return const SizedBox.shrink();
        final color = _getSmartColor(key);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.label, size: 16, color: color),
                    const SizedBox(width: 8),
                    Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    CircleAvatar(radius: 10, backgroundColor: color, child: Text("${indices.length}", style: const TextStyle(color: Colors.white, fontSize: 10))),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_categoryDescriptions[key] ?? "", style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: indices.map((idx) => GestureDetector(
                    onTap: () => _showSolutionSheet(idx),
                    child: Container(
                      width: 40, height: 30, alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(4)),
                      child: Text("Q${idx + 1}", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}