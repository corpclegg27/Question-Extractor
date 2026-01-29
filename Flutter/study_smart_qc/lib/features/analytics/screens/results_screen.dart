// lib/features/analytics/screens/results_screen.dart
// Description: Detailed analysis screen.
// UPDATED: Implemented Custom 'Segmented' Tab Bar to match UI design.
// UPDATED: Hides breakdown list in Score Card if only 1 question type exists.
// UPDATED: Removed redundant section headers inside tabs.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/widgets/solution_detail_sheet.dart';
import 'package:study_smart_qc/features/analytics/widgets/student_question_review_card.dart';

class ResultsScreen extends StatefulWidget {
  final TestResult result;

  const ResultsScreen({super.key, required this.result});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'All';

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
    _tabController = TabController(length: 3, vsync: this);
    // Listen to changes to rebuild the custom tab bar UI
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _groupQuestionsForList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Test Analysis'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // [UPDATED] Custom Segmented Tab Bar
          _buildCustomTabBar(),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(),
                _buildBreakdownTab(),
                _buildFullReviewTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- CUSTOM TAB BAR WIDGET ---
  Widget _buildCustomTabBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildTabItem("Summary", 0),
          _buildTabItem("Q Breakdown", 1),
          _buildTabItem("Paper Review", 2),
        ],
      ),
    );
  }

  Widget _buildTabItem(String title, int index) {
    final bool isSelected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _tabController.animateTo(index);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                : [],
          ),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.deepPurple : Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // --- TAB 1: SUMMARY ---
  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildScoreCard(),
          const SizedBox(height: 24),
          _buildStatsRow(),
          const SizedBox(height: 32),
          _buildQuestionsByResultChart(),
          const SizedBox(height: 32),
          _buildTimeByResultChart(),
          const SizedBox(height: 32),
          _buildBehaviorCountChart(),
          const SizedBox(height: 32),
          _buildBehaviorTimeChart(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- TAB 2: QUESTION BREAKDOWN ---
  Widget _buildBreakdownTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // [UPDATED] Removed redundant header
          _buildSmartAnalysisList(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- TAB 3: FULL PAPER REVIEW ---
  Widget _buildFullReviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // [UPDATED] Removed redundant header
          _buildFilterChips(),
          const SizedBox(height: 16),
          _buildFullPaperReview(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- HELPERS & WIDGETS ---

  // NOTE: Kept for usage inside charts if needed, but removed from main flow tabs
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple),
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

    // [UPDATED] Check question types count to conditionally show breakdown
    bool showBreakdown = false;
    final breakdownMap = attempt.marksBreakdown;

    // Logic: Iterate subjects, count total unique question types across all subjects
    int typeCount = 0;
    breakdownMap.forEach((subject, data) {
      if (subject != "Overall" && data is Map) {
        data.forEach((key, val) {
          if (key != "maxMarks" && key != "marksObtained") typeCount++;
        });
      }
    });

    if (typeCount > 1) showBreakdown = true;

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
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: percent),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.grey.shade100,
                  color: theme.bar,
                  minHeight: 12,
                );
              },
            ),
          ),

          // [UPDATED] Only show breakdown if we have more than 1 type
          if (showBreakdown)
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
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 800),
                          builder: (context, val, _) => Container(
                              height: 8,
                              width: double.infinity,
                              decoration: BoxDecoration(color: theme.bar, borderRadius: BorderRadius.circular(4))
                          ),
                        ),
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
        }),
      ],
    );
  }

  Widget _buildStatsRow() {
    int correct = 0;
    int partial = 0;
    int incorrect = 0;

    widget.result.attempt.responses.forEach((k, v) {
      if (v.status == 'CORRECT') {
        correct++;
      } else if (v.status == 'PARTIALLY_CORRECT') partial++;
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

  // --- CHARTS ---

  Widget _buildQuestionsByResultChart() {
    int c = 0; int p = 0; int i = 0; int s = 0;

    widget.result.attempt.responses.forEach((k, v) {
      if (v.status == 'CORRECT') c++;
      else if (v.status == 'PARTIALLY_CORRECT') p++;
      else if (v.status == 'INCORRECT') i++;
      else s++;
    });

    // Fallback if manual counts exist
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

    int total = c + p + i + s;
    if (total == 0) return _buildEmptyChartPlaceholder();

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Text("# Questions by Result", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const SizedBox(height: 24),
          _buildHorizontalBar(c, p, i, s),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
            children: [
              if (c > 0) _buildLegendItem(Colors.green, 'Correct ($c)'),
              if (p > 0) _buildLegendItem(Colors.orange, 'Partial ($p)'),
              if (i > 0) _buildLegendItem(Colors.red, 'Incorrect ($i)'),
              if (s > 0) _buildLegendItem(Colors.grey.shade300, 'Unattempted ($s)'),
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

    if ((c+p+i+s) == 0) return _buildEmptyChartPlaceholder();

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Text("Time spent by Result", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const SizedBox(height: 24),
          _buildHorizontalBar(c, p, i, s),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
            children: [
              if (c > 0) _buildLegendItem(Colors.green, 'Correct (${_formatSecondsDetailed(c)})'),
              if (p > 0) _buildLegendItem(Colors.orange, 'Partial (${_formatSecondsDetailed(p)})'),
              if (i > 0) _buildLegendItem(Colors.red, 'Incorrect (${_formatSecondsDetailed(i)})'),
              if (s > 0) _buildLegendItem(Colors.grey.shade300, 'Skipped (${_formatSecondsDetailed(s)})'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorCountChart() {
    final Map<String, int> counts = widget.result.attempt.smartTimeAnalysisCounts;
    int totalCount = 0;
    for (var key in _behavioralOrder) {
      String? actualKey = counts.keys.firstWhere((k) => k.startsWith(key), orElse: () => '');
      if (actualKey.isNotEmpty) totalCount += (counts[actualKey] ?? 0);
    }

    if (totalCount == 0) return _buildEmptyChartPlaceholder("No behavioral data");

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Text("# Questions by Behavior", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const SizedBox(height: 24),
          _buildStackedBar(counts, isTime: false),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
            children: _behavioralOrder.map((key) {
              String? actualKey = counts.keys.firstWhere((k) => k.startsWith(key), orElse: () => '');
              int val = (actualKey.isNotEmpty) ? counts[actualKey] ?? 0 : 0;
              if (val > 0) return _buildLegendItem(_getSmartColor(key), '$key ($val)');
              return const SizedBox.shrink();
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorTimeChart() {
    final Map<String, int> times = widget.result.attempt.secondsBreakdownSmartTimeAnalysis;
    int totalTime = 0;
    for (var key in _behavioralOrder) {
      String? actualKey = times.keys.firstWhere((k) => k.startsWith(key), orElse: () => '');
      if (actualKey.isNotEmpty) totalTime += (times[actualKey] ?? 0);
    }

    if (totalTime == 0) return _buildEmptyChartPlaceholder("No time data available");

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Text("Time spent by Behavior", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const SizedBox(height: 24),
          _buildStackedBar(times, isTime: true),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
            children: _behavioralOrder.map((key) {
              String? actualKey = times.keys.firstWhere((k) => k.startsWith(key), orElse: () => '');
              int val = (actualKey.isNotEmpty) ? times[actualKey] ?? 0 : 0;
              if (val > 0) return _buildLegendItem(_getSmartColor(key), '$key (${_formatSecondsDetailed(val)})');
              return const SizedBox.shrink();
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalBar(int c, int p, int i, int s) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutQuart,
        builder: (context, value, _) {
          return SizedBox(
            width: double.infinity,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    if (c > 0) Expanded(flex: c, child: Container(color: Colors.green)),
                    if (p > 0) Expanded(flex: p, child: Container(color: Colors.orange)),
                    if (i > 0) Expanded(flex: i, child: Container(color: Colors.red)),
                    if (s > 0) Expanded(flex: s, child: Container(color: Colors.grey.shade300)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStackedBar(Map<String, int> data, {required bool isTime}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutQuart,
        builder: (context, value, _) {
          return SizedBox(
            width: double.infinity,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: SizedBox(
                height: 16,
                child: Row(
                  children: _behavioralOrder.map((key) {
                    String? actualKey = data.keys.firstWhere((k) => k.startsWith(key), orElse: () => '');
                    int val = (actualKey.isNotEmpty) ? data[actualKey] ?? 0 : 0;
                    if (val == 0) return const SizedBox.shrink();
                    return Expanded(
                      flex: val,
                      child: Container(color: _getSmartColor(key)),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyChartPlaceholder([String text = "No data"]) {
    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(text)),
    );
  }

  // --- SMART ANALYSIS LIST ---
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

  // --- FILTERS ---
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

  // --- FULL PAPER REVIEW ---
  Widget _buildFullPaperReview() {
    // 1. Filter the questions locally
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
      if (_selectedFilter == 'All') {
        matches = true;
      } else if (_selectedFilter == 'Correct' && status == 'CORRECT') {
        matches = true;
      } else if (_selectedFilter == 'Incorrect' && (status == 'INCORRECT' || status == 'PARTIALLY_CORRECT')) {
        matches = true;
      } else if (_selectedFilter == 'Skipped' && (status == 'SKIPPED' || status == 'NOT_VISITED')) {
        matches = true;
      }

      if (matches) filteredIndices.add(i);
    }

    if (filteredIndices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text("No questions match '$_selectedFilter' filter.", style: const TextStyle(color: Colors.grey))),
      );
    }

    return Column(
      children: filteredIndices.map((realIndex) {
        final question = widget.result.questions[realIndex];
        String keyToUse = question.id;
        if (!widget.result.attempt.responses.containsKey(keyToUse)) {
          keyToUse = question.customId;
        }
        final response = widget.result.attempt.responses[keyToUse];

        final status = response?.status ?? 'SKIPPED';
        final timeSpent = response?.timeSpent ?? 0;
        final smartTag = response?.smartTimeAnalysis ?? '';
        final userOption = response?.selectedOption?.toString() ?? 'Not Answered';
        final correctOption = question.actualCorrectAnswers.isNotEmpty
            ? question.actualCorrectAnswers.join(", ")
            : (response?.correctOption?.toString() ?? "N/A");

        final marks = (response?.marksObtained ?? 0).toInt();

        final questionImage = (response?.imageUrl != null && response!.imageUrl!.isNotEmpty)
            ? response.imageUrl
            : question.imageUrl;

        final solutionImage = (response?.solutionUrl != null && response!.solutionUrl!.isNotEmpty)
            ? response.solutionUrl
            : question.solutionUrl;

        final aiSolution = question.aiGenSolutionText;

        return QuestionReviewCard(
          questionId: question.id,
          index: realIndex,
          questionType: question.type.name,
          imageUrl: questionImage,
          solutionUrl: solutionImage,
          aiSolutionText: aiSolution,
          status: status,
          timeSpent: timeSpent,
          smartTag: smartTag,
          userOption: userOption,
          correctOption: correctOption,
          marks: marks,
          isFixed: false,
          onFixToggle: null,
        );
      }).toList(),
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
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: percentage.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    backgroundColor: color.withOpacity(0.1),
                    color: color,
                    minHeight: 6,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
}