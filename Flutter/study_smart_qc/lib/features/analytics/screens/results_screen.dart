// lib/features/analytics/screens/results_screen.dart
// Description: Detailed analysis screen. Added "Full Paper Review" with Filters (All, Correct, Incorrect, Skipped).
// UI matches solution_detail_sheet for consistency (Time box, Tags, Answer Status).
// Solutions are now hidden inside an expandable section, only shown on click.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/widgets/solution_detail_sheet.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart';

class ResultsScreen extends StatefulWidget {
  final TestResult result;

  const ResultsScreen({super.key, required this.result});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String _selectedFilter = 'All'; // Options: All, Correct, Incorrect, Skipped

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

    final responses = widget.result.attempt.responses;

    for (int i = 0; i < widget.result.questions.length; i++) {
      final qId = widget.result.questions[i].id;
      String keyToUse = qId;

      if (!responses.containsKey(keyToUse)) {
        keyToUse = widget.result.questions[i].customId;
      }

      final response = responses[keyToUse];

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
    final attempt = widget.result.attempt;
    double max = attempt.maxMarks.toDouble();
    double score = attempt.score.toDouble();

    if (attempt.marksBreakdown.containsKey('Overall')) {
      final overall = attempt.marksBreakdown['Overall'];
      if (overall != null) {
        if (overall['maxMarks'] != null) max = (overall['maxMarks'] as num).toDouble();
        if (overall['marksObtained'] != null) score = (overall['marksObtained'] as num).toDouble();
      }
    }

    final double percent = (max > 0) ? (score.abs() / max).clamp(0.0, 1.0) : 0.0;
    final theme = _getDynamicColors(score, max);
    final String scoreText = "${score.toStringAsFixed(0)} / ${max.toStringAsFixed(0)}";

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Score', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.black)),
              Text(scoreText,
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
          _buildTypeBreakdownList(attempt.marksBreakdown),
        ],
      ),
    );
  }

  Widget _buildTypeBreakdownList(Map<String, dynamic> breakdown) {
    if (breakdown.isEmpty) return const SizedBox.shrink();

    Map<String, Map<String, double>> typeStats = {};

    breakdown.forEach((subjectKey, subjectValue) {
      if (subjectKey == "Overall") return;
      if (subjectValue is Map) {
        subjectValue.forEach((typeKey, typeData) {
          if (typeData is Map && typeKey != "maxMarks" && typeKey != "marksObtained") {
            if (!typeStats.containsKey(typeKey)) {
              typeStats[typeKey] = {"max": 0.0, "obtained": 0.0};
            }
            double m = (typeData["maxMarks"] as num? ?? 0).toDouble();
            double o = (typeData["marksObtained"] as num? ?? 0).toDouble();

            typeStats[typeKey]!["max"] = (typeStats[typeKey]!["max"]!) + m;
            typeStats[typeKey]!["obtained"] = (typeStats[typeKey]!["obtained"]!) + o;
          }
        });
      }
    });

    if (typeStats.isEmpty) return const SizedBox.shrink();

    List<MapEntry<String, Map<String, double>>> sortedStats = typeStats.entries.toList()
      ..sort((a, b) => b.value["max"]!.compareTo(a.value["max"]!));

    return Column(
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        ...sortedStats.map((e) {
          final String label = e.key;
          final double max = e.value["max"]!;
          final double obtained = e.value["obtained"]!;

          final theme = _getDynamicColors(obtained, max);
          final double percent = (max > 0) ? (obtained / max).clamp(0.0, 1.0) : 0.0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(height: 8, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4))),
                      FractionallySizedBox(
                        widthFactor: percent,
                        child: Container(height: 8, decoration: BoxDecoration(color: theme.bar, borderRadius: BorderRadius.circular(4))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 50,
                  child: Text(
                      "${obtained.toStringAsFixed(0)} / ${max.toStringAsFixed(0)}",
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.bar)
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildStatsRow() {
    int correct = 0;
    int partial = 0;
    int incorrect = 0;

    widget.result.attempt.responses.forEach((k, v) {
      if (v.status == 'CORRECT') correct++;
      else if (v.status == 'PARTIALLY_CORRECT') partial++;
      else if (v.status == 'INCORRECT') incorrect++;
    });

    final int attempted = correct + partial + incorrect;
    final int totalQs = widget.result.attempt.totalQuestions;

    final double accuracy = (attempted > 0) ? (correct / attempted) * 100 : 0.0;
    final double attemptPercent = (totalQs > 0) ? (attempted / totalQs) * 100 : 0.0;
    final String timeStr = _formatTimeHHMMSS(widget.result.attempt.timeTakenSeconds);

    double timeBarPercent = 1.0;
    if (widget.result.attempt.timeLimitMinutes != null && widget.result.attempt.timeLimitMinutes! > 0) {
      timeBarPercent = (widget.result.attempt.timeTakenSeconds / (widget.result.attempt.timeLimitMinutes! * 60)).clamp(0.0, 1.0);
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
    int c = 0;
    int p = 0;
    int i = 0;
    int s = 0;

    widget.result.attempt.responses.forEach((k, v) {
      if (v.status == 'CORRECT') c++;
      else if (v.status == 'PARTIALLY_CORRECT') p++;
      else if (v.status == 'INCORRECT') i++;
      else s++;
    });

    if (c == 0 && p == 0 && i == 0 && s == 0) {
      c = widget.result.attempt.correctCount;
      i = widget.result.attempt.incorrectCount;
      s = widget.result.attempt.skippedCount;
    } else {
      int calculated = c + p + i + s;
      if (calculated < widget.result.attempt.totalQuestions) {
        s += (widget.result.attempt.totalQuestions - calculated);
      }
    }

    final bool isEmpty = (c == 0 && p == 0 && i == 0 && s == 0);

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
                  if(c>0) _buildSection(c.toDouble(), '$c', Colors.green),
                  if(p>0) _buildSection(p.toDouble(), '$p', Colors.orange),
                  if(i>0) _buildSection(i.toDouble(), '$i', Colors.red),
                  if(s>0) _buildSection(s.toDouble(), '$s', Colors.grey.shade300, textColor: Colors.black54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
            children: [
              _buildLegendItem(Colors.green, 'Correct'),
              if(p>0) _buildLegendItem(Colors.orange, 'Partial'),
              _buildLegendItem(Colors.red, 'Incorrect'),
              _buildLegendItem(Colors.grey.shade300, 'Unattempted'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeByResultChart() {
    final Map<String, int> data = widget.result.attempt.secondsBreakdownHighLevel;
    int c = data['CORRECT'] ?? 0;
    int p = data['PARTIALLY_CORRECT'] ?? 0;
    int i = data['INCORRECT'] ?? 0;
    int s = (data['SKIPPED'] ?? 0) + (data['REVIEW_ANSWERED'] ?? 0) + (data['REVIEW'] ?? 0);

    final total = c + p + i + s;

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
                  if(c>0) _buildTimeSection(c, total, Colors.green),
                  if(p>0) _buildTimeSection(p, total, Colors.orange),
                  if(i>0) _buildTimeSection(i, total, Colors.red),
                  if(s>0) _buildTimeSection(s, total, Colors.grey.shade300, textColor: Colors.black54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
            children: [
              _buildLegendItem(Colors.green, 'Correct (${_formatSecondsDetailed(c)})'),
              if(p>0) _buildLegendItem(Colors.orange, 'Partial (${_formatSecondsDetailed(p)})'),
              _buildLegendItem(Colors.red, 'Incorrect (${_formatSecondsDetailed(i)})'),
              _buildLegendItem(Colors.grey.shade300, 'Skipped (${_formatSecondsDetailed(s)})'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorCountChart() {
    final Map<String, int> counts = widget.result.attempt.smartTimeAnalysisCounts;
    List<PieChartSectionData> sections = [];
    int totalCount = 0;

    for (var key in _behavioralOrder) {
      String? actualKey = counts.keys.firstWhere(
              (k) => k.startsWith(key), orElse: () => ''
      );

      if (actualKey.isNotEmpty) {
        int val = counts[actualKey] ?? 0;
        if (val > 0) {
          sections.add(_buildSection(val.toDouble(), '$val', _getSmartColor(key)));
          totalCount += val;
        }
      }
    }

    Widget legend = Wrap(
      spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
      children: _behavioralOrder.map((key) {
        String? actualKey = counts.keys.firstWhere(
                (k) => k.startsWith(key), orElse: () => ''
        );
        int val = (actualKey.isNotEmpty) ? counts[actualKey] ?? 0 : 0;

        if (val > 0) {
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
          legend,
        ],
      ),
    );
  }

  Widget _buildBehaviorTimeChart() {
    final Map<String, int> times = widget.result.attempt.secondsBreakdownSmartTimeAnalysis;
    final total = times.values.fold(0, (sum, item) => sum + item);
    List<PieChartSectionData> sections = [];

    for (var key in _behavioralOrder) {
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
                    onTap: () => _showSolutionSheet(
                        idx,
                        category: key,
                        subset: indices
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

  // [NEW] Filters for Paper Review
  Widget _buildFilterChips() {
    final options = ['All', 'Correct', 'Incorrect', 'Skipped'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: options.map((option) {
          final isSelected = _selectedFilter == option;
          Color activeColor = Colors.deepPurple;
          if (option == 'Correct') activeColor = Colors.green;
          if (option == 'Incorrect') activeColor = Colors.red;
          if (option == 'Skipped') activeColor = Colors.grey;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _selectedFilter = option);
              },
              backgroundColor: Colors.white,
              selectedColor: activeColor.withOpacity(0.2),
              checkmarkColor: activeColor,
              labelStyle: TextStyle(
                color: isSelected ? activeColor : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: isSelected ? activeColor : Colors.grey.shade300),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // [NEW] Full Paper Review Section with Matched UI and Expandable Solution
  Widget _buildFullPaperReview() {
    // 1. Filter Questions
    List<int> filteredIndices = [];
    for (int i = 0; i < widget.result.questions.length; i++) {
      final question = widget.result.questions[i];
      String keyToUse = question.id;
      if (!widget.result.attempt.responses.containsKey(keyToUse)) {
        keyToUse = question.customId;
      }
      final response = widget.result.attempt.responses[keyToUse];
      final status = response?.status ?? 'SKIPPED';

      bool matches = false;
      if (_selectedFilter == 'All') matches = true;
      else if (_selectedFilter == 'Correct' && status == 'CORRECT') matches = true;
      else if (_selectedFilter == 'Incorrect' && (status == 'INCORRECT' || status == 'PARTIALLY_CORRECT')) matches = true;
      else if (_selectedFilter == 'Skipped' && (status == 'SKIPPED' || status == 'NOT_VISITED')) matches = true;

      if (matches) filteredIndices.add(i);
    }

    if (filteredIndices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text("No questions match '$_selectedFilter' filter.", style: const TextStyle(color: Colors.grey))),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredIndices.length,
      itemBuilder: (context, index) {
        final realIndex = filteredIndices[index];
        final question = widget.result.questions[realIndex];
        String keyToUse = question.id;
        if (!widget.result.attempt.responses.containsKey(keyToUse)) {
          keyToUse = question.customId;
        }
        final response = widget.result.attempt.responses[keyToUse];

        // Safe Fallbacks
        final status = response?.status ?? 'SKIPPED';
        final isCorrect = status == 'CORRECT';
        final isPartial = status == 'PARTIALLY_CORRECT';
        final timeSpent = response?.timeSpent ?? 0;
        final smartTag = response?.smartTimeAnalysis ?? '';
        final userOption = response?.selectedOption ?? 'Not Answered';
        final correctOption = response?.correctOption ?? question.correctAnswer;
        final marks = response?.marksObtained ?? 0;

        // Image Sources
        final questionImage = response?.imageUrl ?? question.imageUrl;
        final solutionImage = response?.solutionUrl ?? question.solutionUrl;

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: _standardCardDecoration,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header (Q No + Type + Marks)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text("Q.${realIndex + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(question.type.name.toUpperCase().replaceAll("_", " "), style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: marks > 0 ? Colors.green.shade50 : (marks < 0 ? Colors.red.shade50 : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: marks > 0 ? Colors.green.shade200 : (marks < 0 ? Colors.red.shade200 : Colors.grey.shade300)),
                    ),
                    child: Text("${marks > 0 ? '+' : ''}${marks.toStringAsFixed(marks.truncateToDouble() == marks ? 0 : 1)}",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: marks > 0 ? Colors.green : (marks < 0 ? Colors.red : Colors.grey))),
                  ),
                ],
              ),
              const Divider(height: 24),

              // 2. Question Image
              if (questionImage != null && questionImage.isNotEmpty)
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ExpandableImage(imageUrl: questionImage),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text("Image not available", style: TextStyle(color: Colors.grey))),
                ),
              const SizedBox(height: 16),

              // 3. Time Box (Matches Solution Sheet)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100)
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text("Time Spent: ", style: TextStyle(fontSize: 14, color: Colors.black54)),
                    Text(_formatDuration(timeSpent), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                  ],
                ),
              ),

              // 4. Smart Tag (Matches Solution Sheet)
              if (smartTag.isNotEmpty)
                Builder(builder: (context) {
                  final shortTag = smartTag.split('(').first.trim();
                  final color = _getSmartColor(shortTag);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color)
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.label, size: 16, color: color),
                        const SizedBox(width: 8),
                        Flexible(child: Text(shortTag, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
                      ],
                    ),
                  );
                }),

              // 5. Your Answer
              _buildAnswerStatus(
                'Your Answer: $userOption',
                isCorrect,
                isPartial,
                status,
              ),
              const SizedBox(height: 8),

              // 6. Correct Answer
              _buildAnswerStatus(
                'Correct Answer: $correctOption',
                true, // Force Green for Correct Answer row
                false,
                'CORRECT',
              ),

              // 7. Expandable Solution (Only if available)
              if (solutionImage != null && solutionImage.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: const Text("Show solution", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    initiallyExpanded: false,
                    trailing: const SizedBox.shrink(), // Remove trailing arrow
                    children: [
                      const SizedBox(height: 8),
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Solution:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ExpandableImage(imageUrl: solutionImage),
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            ],
          ),
        );
      },
    );
  }

  // --- ANSWER STATUS WIDGET (Replicated from Solution Sheet) ---
  Widget _buildAnswerStatus(String text, bool isCorrect, bool isPartial, String statusStr) {
    Color color = Colors.grey;
    IconData icon = Icons.help_outline;

    if (statusStr == 'SKIPPED' || statusStr == 'NOT_VISITED') {
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
    } else {
      if (isPartial) {
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
      } else {
        color = isCorrect ? Colors.green : Colors.red;
        icon = isCorrect ? Icons.check_circle : Icons.cancel;
      }
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // --- UTILS ---

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

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
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

            // [NEW] Full Paper Review Section
            const SizedBox(height: 32),
            _buildHeader("Full Paper Review"),
            _buildFilterChips(), // Added Filters
            const SizedBox(height: 16),
            _buildFullPaperReview(),
          ],
        ),
      ),
    );
  }
}