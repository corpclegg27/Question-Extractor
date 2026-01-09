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

  // Smart Analysis Categories
  final Map<String, List<int>> _smartAnalysisGroups = {
    "Perfect Attempt": [],
    "Overtime Correct": [],
    "Careless Mistake": [],
    "Wasted Attempt": [],
    "Good Skip": [],
    "Time Wasted": [],
  };

  // Friendly coaching descriptions
  final Map<String, String> _categoryDescriptions = {
    "Perfect Attempt": "You nailed it! Correct answer within ideal time.",
    "Overtime Correct": "Correct, but took longer than ideal.",
    "Careless Mistake": "Answered quickly but incorrect. Slow down!",
    "Wasted Attempt": "Spent too much time and still got it wrong.",
    "Good Skip": "Smart move. Skipped a tough one quickly.",
    "Time Wasted": "Spent too long before deciding to skip.",
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

  // --- HELPERS ---

  /// Standard Card Decoration (Grey Border)
  BoxDecoration get _standardCardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade300, width: 1.5),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  String _formatDurationCompact(int totalSeconds) {
    if (totalSeconds == 0) return "0s";
    final duration = Duration(seconds: totalSeconds);
    if (totalSeconds < 60) {
      return "${totalSeconds}s";
    } else if (totalSeconds < 3600) {
      int m = duration.inMinutes;
      int s = totalSeconds % 60;
      return s > 0 ? "${m}m ${s}s" : "${m}m";
    } else {
      int h = duration.inHours;
      int m = duration.inMinutes % 60;
      return m > 0 ? "${h}h ${m}m" : "${h}h";
    }
  }

  String _formatSecondsDetailed(int totalSeconds) {
    if (totalSeconds < 60) return "${totalSeconds}s";
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m}m ${s}s';
  }

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

  ({Color bar, Color text}) _getDynamicColors(double score, double max) {
    if (score < 0) return (bar: const Color(0xFFD32F2F), text: const Color(0xFFB71C1C));
    if (max == 0) return (bar: Colors.grey, text: Colors.grey.shade700);

    final double percentage = (score / max).clamp(0.0, 1.0);
    Color color;

    if (percentage < 0.4) {
      final t = percentage / 0.4;
      color = Color.lerp(Colors.deepOrange, Colors.orange, t)!;
    } else if (percentage < 0.75) {
      final t = (percentage - 0.4) / 0.35;
      color = Color.lerp(Colors.orange, Colors.lightGreen.shade600, t)!;
    } else {
      final t = (percentage - 0.75) / 0.25;
      color = Color.lerp(Colors.green, const Color(0xFF1B5E20), t)!;
    }

    final HSLColor hsl = HSLColor.fromColor(color);
    final Color textColor = hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();
    return (bar: color, text: textColor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Test Analysis'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
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
            // Score Card
            _buildScoreCard(),
            const SizedBox(height: 24),

            // Stats Row
            _buildStatsRow(),
            const SizedBox(height: 32),

            // Charts
            _buildHeader("# Questions by Result"),
            _buildPerformanceDistributionChart(),
            const SizedBox(height: 32),

            _buildHeader("Time spent by Result"),
            _buildTimeSpentByResultChart(),
            const SizedBox(height: 32),

            _buildHeader("# Questions by Behavior"),
            _buildSmartAnalysisChart(),
            const SizedBox(height: 32),

            _buildHeader("Time spent by Behavior"),
            _buildTimeSpentByBehaviorChart(),
            const SizedBox(height: 32),

            // Detailed List
            _buildHeader("Questions Breakdown"),
            _buildSmartAnalysisList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
      ),
    );
  }

  // --- SCORE CARD ---
  Widget _buildScoreCard() {
    final double maxScore = widget.result.totalMarks.toDouble();
    final double score = marksObtained.toDouble();
    final themeColors = _getDynamicColors(score, maxScore);
    double scorePercentage = (maxScore == 0) ? 0 : (score.abs() / maxScore).clamp(0.0, 1.0);

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Score', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.black)),
              Text('$marksObtained / ${widget.result.totalMarks}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: themeColors.text)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: scorePercentage,
              backgroundColor: Colors.grey.shade100,
              color: themeColors.bar,
              minHeight: 12,
            ),
          ),
        ],
      ),
    );
  }

  // --- STATS ROW ---
  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard(
          title: 'Accuracy',
          value: '${accuracy.toStringAsFixed(0)}%',
          percentage: accuracy / 100,
          color: Colors.blue,
          icon: Icons.gps_fixed,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          title: 'Attempt %',
          value: '${attemptPercentage.toStringAsFixed(0)}%',
          percentage: attemptPercentage / 100,
          color: Colors.orange,
          icon: Icons.checklist,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          title: 'Time Taken',
          value: _formatDurationCompact(widget.result.timeTaken.inSeconds),
          percentage: 1.0,
          color: Colors.purple,
          icon: Icons.timer_outlined,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required double percentage,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        decoration: _standardCardDecoration,
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage.clamp(0.0, 1.0),
                backgroundColor: color.withOpacity(0.1),
                color: color,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- CHARTS ---

  Widget _buildPerformanceDistributionChart() {
    int total = widget.result.questions.length;
    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
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
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                        "$total",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
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
    );
  }

  Widget _buildTimeSpentByResultChart() {
    final Map<String, int> timeMap = {"CORRECT": 0, "INCORRECT": 0, "SKIPPED": 0};
    for (var resp in widget.result.responses.values) {
      String status = (resp.status == "REVIEW") ? "SKIPPED" : resp.status;
      timeMap[status] = (timeMap[status] ?? 0) + resp.timeSpent;
    }
    final total = timeMap.values.fold(0, (sum, item) => sum + item);

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: total == 0 ? const Center(child: Text("No data")) : Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270,
                    sections: [
                      _buildTimeSection(timeMap["CORRECT"]!, total, Colors.green),
                      _buildTimeSection(timeMap["INCORRECT"]!, total, Colors.red),
                      _buildTimeSection(timeMap["SKIPPED"]!, total, Colors.grey.shade300, textColor: Colors.black54),
                    ],
                  ),
                ),
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                        _formatDurationCompact(total),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
            children: [
              _buildLegendItem(Colors.green, 'Correct (${_formatSecondsDetailed(timeMap["CORRECT"]!)})'),
              _buildLegendItem(Colors.red, 'Incorrect (${_formatSecondsDetailed(timeMap["INCORRECT"]!)})'),
              _buildLegendItem(Colors.grey.shade300, 'Skipped (${_formatSecondsDetailed(timeMap["SKIPPED"]!)})'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmartAnalysisChart() {
    List<PieChartSectionData> sections = [];
    int totalCount = 0;
    for (var key in _behavioralOrder) {
      final count = _smartAnalysisGroups[key]!.length;
      if (count > 0) {
        sections.add(_buildSection(count.toDouble(), '$count', _getSmartColor(key)));
        totalCount += count;
      }
    }

    if (sections.isEmpty) return Container(decoration: _standardCardDecoration, padding: const EdgeInsets.all(20), child: const Center(child: Text("No behavioral data")));

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270,
                    sections: sections,
                  ),
                ),
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                        "$totalCount",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
            children: _behavioralOrder
                .where((key) => _smartAnalysisGroups[key]!.isNotEmpty)
                .map((key) => _buildLegendItem(_getSmartColor(key), key))
                .toList(),
          ),
        ],
      ),
    );
  }

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

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: total == 0 ? const Center(child: Text("No data")) : Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270,
                    sections: sections,
                  ),
                ),
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                        _formatDurationCompact(total),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
            children: _behavioralOrder
                .where((key) => (timeMap[key] ?? 0) > 0)
                .map((key) => _buildLegendItem(_getSmartColor(key), '$key (${_formatSecondsDetailed(timeMap[key] ?? 0)})'))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartAnalysisList() {
    return Column(
      children: _behavioralOrder.map((key) {
        final indices = _smartAnalysisGroups[key] ?? [];
        if (indices.isEmpty) return const SizedBox.shrink();
        final color = _getSmartColor(key);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          // SPECIFIC DECORATION FOR LIST ITEMS
          // White background, Colored Border (2.0 width), Soft Shadow
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.label, size: 20, color: color), // COLORED ICON
                  const SizedBox(width: 12),
                  Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text("${indices.length}", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Text(
                  _categoryDescriptions[key] ?? "",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: indices.map((idx) => GestureDetector(
                  onTap: () => _showSolutionSheet(idx),
                  child: Container(
                    width: 44, height: 34, alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: color.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]
                    ),
                    child: Text("Q${idx + 1}", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                )).toList(),
              ),
            ],
          ),
        );
      }).toList(),
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
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }
}