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
  final List<String> _behavioralOrder = [
    "Perfect Attempt", "Overtime Correct", "Careless Mistake",
    "Wasted Attempt", "Good Skip", "Time Wasted"
  ];

  final Map<String, List<int>> _smartAnalysisGroups = {};
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
    _groupQuestionsForList();
  }

  void _groupQuestionsForList() {
    for (var key in _behavioralOrder) {
      _smartAnalysisGroups[key] = [];
    }

    for (int i = 0; i < widget.result.questions.length; i++) {
      final qId = widget.result.questions[i].id;
      // Also try customId if docId not found, though attempt normally uses docId keys
      String keyToUse = qId;
      if (!widget.result.responses.containsKey(keyToUse)) {
        keyToUse = widget.result.questions[i].customId;
      }

      final response = widget.result.responses[keyToUse];

      if (response != null) {
        final tag = response.smartTimeAnalysis;
        for (var key in _behavioralOrder) {
          if (tag.contains(key)) {
            _smartAnalysisGroups[key]!.add(i);
            break;
          }
        }
      }
    }
  }

  void _showSolutionSheet(int initialIndex, {String? category, List<int>? subset}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: SolutionDetailSheet(
            result: widget.result,
            initialIndex: initialIndex,
            // PASS THE NEW DATA HERE
            categoryTitle: category,
            validQuestionIndices: subset,
          ),
        );
      },
    );
  }

  // --- HELPERS & WIDGETS ---

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

  Widget _buildScoreCard() {
    final double max = widget.result.maxMarks.toDouble();
    final double score = widget.result.score.toDouble();
    final double percent = (max > 0) ? (score.abs() / max).clamp(0.0, 1.0) : 0.0;
    final theme = _getDynamicColors(score, max);

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Score', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.black)),
              Text('${widget.result.score} / ${widget.result.maxMarks}',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: theme.text)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.grey.shade100,
              color: theme.bar,
              minHeight: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final int correct = widget.result.correctCount;
    final int incorrect = widget.result.incorrectCount;
    final int totalQs = widget.result.totalQuestions;
    final int attempted = correct + incorrect;

    final double accuracy = (attempted > 0) ? (correct / attempted) * 100 : 0.0;
    final double attemptPercent = (totalQs > 0) ? (attempted / totalQs) * 100 : 0.0;
    final String timeStr = _formatTimeHHMMSS(widget.result.timeTakenSeconds);

    double timeBarPercent = 1.0;
    if (widget.result.timeLimitMinutes != null && widget.result.timeLimitMinutes! > 0) {
      timeBarPercent = (widget.result.timeTakenSeconds / (widget.result.timeLimitMinutes! * 60)).clamp(0.0, 1.0);
    }

    return Row(
      children: [
        _buildStatCard('Accuracy', '${accuracy.toStringAsFixed(0)}%', accuracy / 100, Colors.blue, Icons.gps_fixed),
        const SizedBox(width: 16),
        _buildStatCard('Attempt %', '${attemptPercent.toStringAsFixed(0)}%', attemptPercent / 100, Colors.orange, Icons.checklist),
        const SizedBox(width: 16),
        _buildStatCard('Time Taken', timeStr, timeBarPercent, Colors.purple, Icons.timer_outlined),
      ],
    );
  }

  Widget _buildQuestionsByResultChart() {
    final int c = widget.result.correctCount;
    final int i = widget.result.incorrectCount;
    final int s = widget.result.skippedCount;

    final bool isEmpty = (c == 0 && i == 0 && s == 0);

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: isEmpty ? const Center(child: Text("No data")) : PieChart(
              PieChartData(
                sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270,
                sections: [
                  _buildSection(c.toDouble(), '$c', Colors.green),
                  _buildSection(i.toDouble(), '$i', Colors.red),
                  _buildSection(s.toDouble(), '$s', Colors.grey.shade300, textColor: Colors.black54),
                ],
              ),
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

  Widget _buildTimeByResultChart() {
    final Map<String, int> data = widget.result.secondsBreakdownHighLevel;
    int c = data['CORRECT'] ?? 0;
    int i = data['INCORRECT'] ?? 0;
    int s = (data['SKIPPED'] ?? 0) + (data['REVIEW_ANSWERED'] ?? 0) + (data['REVIEW'] ?? 0);

    final total = c + i + s;

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: total == 0 ? const Center(child: Text("No data")) : PieChart(
              PieChartData(
                sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270,
                sections: [
                  _buildTimeSection(c, total, Colors.green),
                  _buildTimeSection(i, total, Colors.red),
                  _buildTimeSection(s, total, Colors.grey.shade300, textColor: Colors.black54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
            children: [
              _buildLegendItem(Colors.green, 'Correct (${_formatSecondsDetailed(c)})'),
              _buildLegendItem(Colors.red, 'Incorrect (${_formatSecondsDetailed(i)})'),
              _buildLegendItem(Colors.grey.shade300, 'Skipped (${_formatSecondsDetailed(s)})'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorCountChart() {
    final Map<String, int> counts = widget.result.smartTimeAnalysisCounts;
    List<PieChartSectionData> sections = [];
    int totalCount = 0;

    // 1. Build Sections
    for (var key in _behavioralOrder) {
      String? actualKey = counts.keys.firstWhere(
              (k) => k.startsWith(key), orElse: () => ''
      );

      if (actualKey.isNotEmpty) {
        int val = counts[actualKey] ?? 0;
        if (val > 0) {
          // Title on Chart: Just the number
          sections.add(_buildSection(val.toDouble(), '$val', _getSmartColor(key)));
          totalCount += val;
        }
      }
    }

    // 2. Build Legend (Corrected to show "Category Name (Count)")
    Widget legend = Wrap(
      spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
      children: _behavioralOrder.map((key) {
        String? actualKey = counts.keys.firstWhere(
                (k) => k.startsWith(key), orElse: () => ''
        );
        int val = (actualKey.isNotEmpty) ? counts[actualKey] ?? 0 : 0;

        if (val > 0) {
          // LEGEND TEXT: "Perfect Attempt (4)"
          return _buildLegendItem(_getSmartColor(key), '$key ($val)');
        }
        return const SizedBox.shrink();
      }).toList(),
    );

    if (totalCount == 0) {
      return Container(
          decoration: _standardCardDecoration,
          padding: const EdgeInsets.all(20),
          child: const Center(child: Text("No behavioral data"))
      );
    }

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  startDegreeOffset: 270,
                  sections: sections
              ),
            ),
          ),
          const SizedBox(height: 24),
          legend, // <--- Corrected Legend
        ],
      ),
    );
  }
  Widget _buildBehaviorTimeChart() {
    final Map<String, int> times = widget.result.secondsBreakdownSmartTimeAnalysis;
    final total = times.values.fold(0, (sum, item) => sum + item);
    List<PieChartSectionData> sections = [];

    for (var key in _behavioralOrder) {
      // Logic to find key even if suffix differs
      String? actualKey = times.keys.firstWhere(
              (k) => k.startsWith(key), orElse: () => ''
      );

      if (actualKey.isNotEmpty) {
        int val = times[actualKey] ?? 0;
        if (val > 0) {
          sections.add(_buildTimeSection(val, total, _getSmartColor(key)));
        }
      }
    }

    Widget legend = Wrap(
      spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
      children: _behavioralOrder.map((key) {
        String? actualKey = times.keys.firstWhere(
                (k) => k.startsWith(key), orElse: () => ''
        );
        int val = (actualKey.isNotEmpty) ? times[actualKey] ?? 0 : 0;
        if (val > 0) {
          return _buildLegendItem(_getSmartColor(key), '$key (${_formatSecondsDetailed(val)})');
        }
        return const SizedBox.shrink();
      }).toList(),
    );

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: total == 0 ? const Center(child: Text("No data")) : PieChart(
              PieChartData(sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270, sections: sections),
            ),
          ),
          const SizedBox(height: 24),
          legend,
        ],
      ),
    );
  }

  Widget _buildSmartAnalysisList() {
    return Column(
      children: _behavioralOrder.map((key) {
        final indices = _smartAnalysisGroups[key] ?? [];
        final color = _getSmartColor(key);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2.0),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.label, size: 20, color: color),
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
              Text(_categoryDescriptions[key] ?? "", style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)),
              const SizedBox(height: 16),
              if (indices.isNotEmpty)
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: indices.map((idx) => GestureDetector(
                    // UPDATED: Pass the Category Key and the List of Indices
                    onTap: () => _showSolutionSheet(
                        idx,
                        category: key,      // e.g. "Perfect Attempt"
                        subset: indices     // e.g. [0, 2, 5]
                    ),
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
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text("No questions in this category.", style: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic, fontSize: 13)),
                )
            ],
          ),
        );
      }).toList(),
    );
  }

  // --- UTILS ---

  Widget _buildGenericPieChart(List<PieChartSectionData> sections, int total, String emptyMsg) {
    if (sections.isEmpty) return Container(decoration: _standardCardDecoration, padding: const EdgeInsets.all(20), child: Center(child: Text(emptyMsg)));
    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270, sections: sections),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
            // Simple legend for count chart
            children: sections.map((s) => _buildLegendItem(s.color, s.title)).toList(),
          ),
        ],
      ),
    );
  }

  String _formatTimeHHMMSS(int totalSeconds) {
    if (totalSeconds < 0) return "00:00";
    final int h = totalSeconds ~/ 3600;
    final int m = (totalSeconds % 3600) ~/ 60;
    final int s = totalSeconds % 60;
    if (h > 0) return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String _formatSecondsDetailed(int totalSeconds) {
    if (totalSeconds < 60) return "${totalSeconds}s";
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m}m ${s}s';
  }

  BoxDecoration get _standardCardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade300, width: 1.5),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
  );

  Widget _buildStatCard(String title, String value, double percentage, Color color, IconData icon) {
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
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: percentage.clamp(0.0, 1.0), backgroundColor: color.withOpacity(0.1), color: color, minHeight: 6),
            ),
          ],
        ),
      ),
    );
  }

  PieChartSectionData _buildSection(double value, String title, Color color, {Color textColor = Colors.white}) {
    return PieChartSectionData(value: value, title: title, color: color, radius: 50, titleStyle: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14));
  }

  PieChartSectionData _buildTimeSection(int value, int total, Color color, {Color textColor = Colors.white}) {
    final percent = total > 0 ? (value / total * 100).toStringAsFixed(0) : '0';
    return PieChartSectionData(value: value.toDouble(), title: '$percent%', color: color, radius: 50, titleStyle: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12));
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87))]);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(title: const Text('Test Analysis'), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildScoreCard(),
            const SizedBox(height: 24),
            _buildStatsRow(),
            const SizedBox(height: 32),
            _buildHeader("# Questions by Result"),
            _buildQuestionsByResultChart(),
            const SizedBox(height: 32),
            _buildHeader("Time spent by Result"),
            _buildTimeByResultChart(),
            const SizedBox(height: 32),
            _buildHeader("# Questions by Behavior"),
            _buildBehaviorCountChart(),
            const SizedBox(height: 32),
            _buildHeader("Time spent by Behavior"),
            _buildBehaviorTimeChart(),
            const SizedBox(height: 32),
            _buildHeader("Questions Breakdown"),
            _buildSmartAnalysisList(),
          ],
        ),
      ),
    );
  }
}