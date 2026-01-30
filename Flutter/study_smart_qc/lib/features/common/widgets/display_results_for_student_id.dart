// lib/features/common/widgets/display_results_for_student_id.dart
// Description: Main Dashboard Widget.
// FULL CODE: Contains Dashboard, Chapter Insights, Results Tabs, and all Chart Widgets.
// UPDATED: Fixed Bar Chart rounding (top-only) and added total daily count to Chapter Breakdown header.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/features/analytics/widgets/attempt_list_widget.dart';
import 'package:study_smart_qc/features/analytics/screens/student_chapter_detailed_view.dart';

enum DashboardViewType { dashboard, chapters }

class DisplayResultsForStudentId extends StatefulWidget {
  final String? targetStudentUid;
  final bool isVisible;

  const DisplayResultsForStudentId({
    super.key,
    this.targetStudentUid,
    this.isVisible = true,
  });

  @override
  State<DisplayResultsForStudentId> createState() => _DisplayResultsForStudentIdState();
}

class _DisplayResultsForStudentIdState extends State<DisplayResultsForStudentId> with SingleTickerProviderStateMixin {
  late TabController _mainTabController;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  Widget _buildPillTabBar({
    required TabController? controller,
    required List<Tab> tabs,
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.deepPurple.shade100),
        ),
        labelColor: Colors.deepPurple,
        unselectedLabelColor: Colors.grey,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelPadding: EdgeInsets.zero,
        tabs: tabs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          height: 48,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _mainTabController,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            labelColor: const Color(0xFF6200EA),
            unselectedLabelColor: Colors.grey.shade600,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: const [
              Tab(text: "Dashboard"),
              Tab(text: "Chapter Insights"),
              Tab(text: "Results"),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _mainTabController,
            children: [
              _DashboardTab(
                targetUserId: widget.targetStudentUid,
                isActive: widget.isVisible,
                viewType: DashboardViewType.dashboard,
              ),
              _DashboardTab(
                targetUserId: widget.targetStudentUid,
                isActive: widget.isVisible,
                viewType: DashboardViewType.chapters,
              ),
              _buildResultsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _buildPillTabBar(
              controller: null,
              tabs: const [
                Tab(text: "Assignments"),
                Tab(text: "Tests"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAssignmentsSubTabs(),
                AttemptListWidget(
                  filterMode: 'Test',
                  onlySingleAttempt: true,
                  targetUserId: widget.targetStudentUid,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentsSubTabs() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _buildPillTabBar(
              controller: null,
              tabs: const [
                Tab(text: "Practice Mode"),
                Tab(text: "Test Mode"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                AttemptListWidget(
                  filterMode: 'Practice',
                  onlySingleAttempt: false,
                  targetUserId: widget.targetStudentUid,
                ),
                AttemptListWidget(
                  filterMode: 'Test',
                  onlySingleAttempt: false,
                  targetUserId: widget.targetStudentUid,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INTERNAL WIDGET: DASHBOARD TAB WRAPPER
// =============================================================================

class _DashboardTab extends StatefulWidget {
  final String? targetUserId;
  final bool isActive;
  final DashboardViewType viewType;

  const _DashboardTab({
    this.targetUserId,
    required this.isActive,
    required this.viewType,
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> with SingleTickerProviderStateMixin {
  late TabController _timeTabController;

  @override
  void initState() {
    super.initState();
    _timeTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _timeTabController.dispose();
    super.dispose();
  }

  Widget _buildTimeTabBar() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TabBar(
        controller: _timeTabController,
        indicator: BoxDecoration(
          color: Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.deepPurple.shade100),
        ),
        labelColor: Colors.deepPurple,
        unselectedLabelColor: Colors.grey,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelPadding: EdgeInsets.zero,
        tabs: const [
          Tab(text: "Last Week"),
          Tab(text: "Last Month"),
          Tab(text: "All Time"),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.targetUserId ?? FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return const Center(child: Text("User not found"));

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('student_deep_analysis')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(
            child: Text(
              "No analytics data generated yet.\nRun the backend script.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return _buildContent(snapshot.data!.data() as Map<String, dynamic>, uid);
      },
    );
  }

  Widget _buildContent(Map<String, dynamic> data, String uid) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final lastMonth = data['summary_lastMonth'] as Map<String, dynamic>? ?? {};
    final lastWeek = data['summary_lastWeek'] as Map<String, dynamic>? ?? {};
    final chapterData = data['breakdownByChapter'] as Map<String, dynamic>? ?? {};

    // Daily Breakdown (Counts & Time)
    final dailyData = (data['dailyQuestionsBreakdown'] ?? data['dailyQuestionsBreakdownbyStatus']) as Map<String, dynamic>? ?? {};

    // Daily Chapter Breakdown
    final dailyChapterData = data['dailyQuestionsBreakdownbyChapter'] as Map<String, dynamic>? ?? {};

    final Timestamp? lastUpdated = data['lastUpdated'];
    String lastUpdatedStr = "Unknown";
    if (lastUpdated != null) {
      lastUpdatedStr = DateFormat('d MMM y, h:mm a').format(lastUpdated.toDate());
    }

    // CASE 1: CHAPTER INSIGHTS
    if (widget.viewType == DashboardViewType.chapters) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.sync, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  "Analysis as on $lastUpdatedStr",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          Expanded(
            child: _DashboardPageView(
              stats: summary,
              chapterData: chapterData,
              dailyData: dailyData,
              dailyChapterData: dailyChapterData, // Pass data
              viewType: widget.viewType,
              emptyMsg: "No chapter data found.",
              fullDoc: data,
              userId: uid,
            ),
          ),
        ],
      );
    }

    // CASE 2: DASHBOARD
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.sync, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                "Analysis as on $lastUpdatedStr",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: _buildTimeTabBar(),
        ),

        Expanded(
          child: TabBarView(
            controller: _timeTabController,
            children: [
              _DashboardPageView(
                stats: lastWeek,
                dailyData: dailyData,
                dailyChapterData: dailyChapterData, // Pass data
                viewType: widget.viewType,
                emptyMsg: "No activity in the last 7 days.",
                chartDays: 7,
              ),
              _DashboardPageView(
                stats: lastMonth,
                dailyData: dailyData,
                dailyChapterData: dailyChapterData, // Pass data
                viewType: widget.viewType,
                emptyMsg: "No activity in the last 30 days.",
                chartDays: 30,
              ),
              _DashboardPageView(
                stats: summary,
                chapterData: chapterData,
                dailyData: dailyData,
                dailyChapterData: dailyChapterData, // Pass data
                viewType: widget.viewType,
                emptyMsg: "No activity yet.",
                fullDoc: data,
                userId: uid,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// ISOLATED PAGE WIDGET
// =============================================================================

class _DashboardPageView extends StatefulWidget {
  final Map<String, dynamic> stats;
  final Map<String, dynamic>? chapterData;
  final Map<String, dynamic> dailyData;
  final Map<String, dynamic> dailyChapterData;
  final DashboardViewType viewType;
  final String emptyMsg;
  final int? chartDays;
  final Map<String, dynamic>? fullDoc;
  final String? userId;

  const _DashboardPageView({
    required this.stats,
    required this.dailyData,
    required this.dailyChapterData,
    required this.viewType,
    required this.emptyMsg,
    this.chapterData,
    this.chartDays,
    this.fullDoc,
    this.userId,
  });

  @override
  State<_DashboardPageView> createState() => _DashboardPageViewState();
}

class _DashboardPageViewState extends State<_DashboardPageView> {
  bool _playAnimation = false;

  final List<String> _behavioralOrder = const [
    "Perfect Attempt", "Overtime Correct", "Careless Mistake",
    "Wasted Attempt", "Good Skip", "Time Wasted"
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _playAnimation = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if ((widget.stats['total'] ?? 0) == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(widget.emptyMsg, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
    }

    if (widget.viewType == DashboardViewType.dashboard) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          children: [
            if (widget.chartDays != null) ...[
              _buildDailyActivityChart(widget.dailyData, widget.chartDays!),
              const SizedBox(height: 16),
              _buildTimeSpentChart(widget.dailyData, widget.chartDays!),
              const SizedBox(height: 16),
              // Chapter Breakdown Widget
              _buildChapterBreakdown(widget.dailyChapterData, widget.chartDays!),
              const SizedBox(height: 24),
            ],
            _buildMetricSection(widget.stats),
          ],
        ),
      );
    }

    // Chapter List Logic
    List<MapEntry<String, dynamic>> sortedChapters = [];
    if (widget.chapterData != null) {
      sortedChapters = widget.chapterData!.entries.toList();
      sortedChapters.sort((a, b) {
        final totalA = a.value['total'] ?? 0;
        final totalB = b.value['total'] ?? 0;
        return totalB.compareTo(totalA);
      });
    }

    if (sortedChapters.isEmpty) {
      return const Center(child: Text("No chapter data available."));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (widget.fullDoc != null && widget.userId != null)
          ...sortedChapters.map((entry) {
            return _ChapterCard(
              name: entry.key,
              stats: entry.value,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StudentChapterDetailedView(
                      userId: widget.userId!,
                      chapterName: entry.key,
                      subjectName: entry.value['subject'] ?? 'Unknown',
                    ),
                  ),
                );
              },
            );
          })
        else
          ...sortedChapters.map((entry) {
            return _ChapterCard(name: entry.key, stats: entry.value);
          })
      ],
    );
  }

  // --- CHAPTER BREAKDOWN EXPANSION TILE ---
  Widget _buildChapterBreakdown(Map<String, dynamic> dailyChapterData, int days) {
    final now = DateTime.now();
    List<DateTime> dateRange = [];
    for (int i = 0; i < days; i++) {
      dateRange.add(now.subtract(Duration(days: i)));
    }

    // Check if we have data to show
    bool hasData = false;
    for (var date in dateRange) {
      String key = DateFormat('yyyy-MM-dd').format(date);
      if (dailyChapterData.containsKey(key)) {
        hasData = true;
        break;
      }
    }

    if (!hasData) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: const Text(
            "Show Chapters Studied",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.deepPurple),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: dateRange.map((date) {
                  String key = DateFormat('yyyy-MM-dd').format(date);
                  if (!dailyChapterData.containsKey(key)) return const SizedBox.shrink();

                  Map<String, dynamic> chapters = dailyChapterData[key] as Map<String, dynamic>;
                  String niceDate = DateFormat('EEE, d MMM').format(date);

                  // [UPDATED] Calculate Total Questions for this day
                  int dayTotal = 0;
                  chapters.forEach((k, v) {
                    if (v is int) {
                      dayTotal += v;
                    } else if (v is num) {
                      dayTotal += v.toInt();
                    }
                  });

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // [UPDATED] Display Date AND Total Count
                        Text(
                            "$niceDate ($dayTotal qs)",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)
                        ),
                        const SizedBox(height: 8),
                        ...chapters.entries.map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      e.key,
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                      "${e.value} qs",
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)
                                  ),
                                )
                              ],
                            ),
                          );
                        }),
                        Divider(color: Colors.grey.shade100),
                      ],
                    ),
                  );
                }).toList(),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- CHART 1: QUESTIONS ---
  Widget _buildDailyActivityChart(Map<String, dynamic> dailyData, int days) {
    final now = DateTime.now();
    List<DateTime> dateRange = [];
    for (int i = 0; i < days; i++) {
      dateRange.add(now.subtract(Duration(days: i)));
    }
    dateRange = dateRange.reversed.toList();

    List<BarChartGroupData> barGroups = [];
    double maxY = 0;

    double multiplier = _playAnimation ? 1.0 : 0.0;

    for (int i = 0; i < dateRange.length; i++) {
      final dateStr = DateFormat('yyyy-MM-dd').format(dateRange[i]);
      final dayStats = dailyData[dateStr] ?? {};

      double correct = (dayStats['correct'] ?? 0).toDouble() * multiplier;
      double incorrect = (dayStats['incorrect'] ?? 0).toDouble() * multiplier;
      double skipped = (dayStats['skipped'] ?? 0).toDouble() * multiplier;
      double total = correct + incorrect + skipped;

      double actualTotal = ((dayStats['correct'] ?? 0) + (dayStats['incorrect'] ?? 0) + (dayStats['skipped'] ?? 0)).toDouble();
      if (actualTotal > maxY) maxY = actualTotal;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: total,
              rodStackItems: [
                BarChartRodStackItem(0, correct, Colors.green),
                BarChartRodStackItem(correct, correct + incorrect, Colors.red),
                BarChartRodStackItem(correct + incorrect, total, Colors.grey.shade300),
              ],
              width: days == 7 ? 16 : 8,
              // [UPDATED] Rounded only at the top to fix "detached" look
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              color: Colors.transparent,
            ),
          ],
          showingTooltipIndicators: days == 7 && total > 0 ? [0] : [],
        ),
      );
    }

    double interval = _calculateYInterval(maxY, isTime: false);
    double adjustedMaxY = (maxY > 0) ? (maxY / interval).ceil() * interval : 5;

    return Container(
      height: 220,
      width: double.infinity,
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                days == 7 ? "# Questions" : "# Questions",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),
              ),
              Row(
                children: [
                  _buildChartLegend(Colors.green, "Correct"),
                  const SizedBox(width: 8),
                  _buildChartLegend(Colors.red, "Incorrect"),
                  const SizedBox(width: 8),
                  _buildChartLegend(Colors.grey.shade300, "Skipped"),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: adjustedMaxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => days == 7 ? Colors.transparent : Colors.blueGrey,
                    tooltipPadding: days == 7 ? EdgeInsets.zero : const EdgeInsets.all(8),
                    tooltipMargin: days == 7 ? 2 : 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final date = dateRange[group.x.toInt()];
                      if (days == 7) {
                        return BarTooltipItem(
                          rod.toY < 1 ? '' : rod.toY.toInt().toString(),
                          const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 11),
                        );
                      }
                      final dateStr = DateFormat('d MMM').format(date);
                      return BarTooltipItem(
                        '$dateStr\n',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        children: [TextSpan(text: 'Total: ${rod.toY.toInt()}', style: const TextStyle(color: Colors.yellowAccent))],
                      );
                    },
                  ),
                ),
                titlesData: _buildChartTitles(dateRange, days, interval, showLeftTitles: days == 30),
                borderData: FlBorderData(
                  show: true,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
                ),
                gridData: FlGridData(
                  show: days == 30,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                barGroups: barGroups,
              ),
              swapAnimationDuration: const Duration(milliseconds: 1000),
              swapAnimationCurve: Curves.easeOutQuart,
            ),
          ),
        ],
      ),
    );
  }

  // --- CHART 2: TIME SPENT ---
  Widget _buildTimeSpentChart(Map<String, dynamic> dailyData, int days) {
    final now = DateTime.now();
    List<DateTime> dateRange = [];
    for (int i = 0; i < days; i++) {
      dateRange.add(now.subtract(Duration(days: i)));
    }
    dateRange = dateRange.reversed.toList();

    List<BarChartGroupData> barGroups = [];
    double maxY = 0;

    double multiplier = _playAnimation ? 1.0 : 0.0;

    for (int i = 0; i < dateRange.length; i++) {
      final dateStr = DateFormat('yyyy-MM-dd').format(dateRange[i]);
      final dayStats = dailyData[dateStr] ?? {};

      double seconds = (dayStats['timeSpent'] ?? 0).toDouble();
      double minutes = (seconds / 60.0);

      if (minutes > maxY) maxY = minutes;

      minutes = minutes * multiplier;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: minutes,
              width: days == 7 ? 16 : 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              color: Colors.deepPurple.shade300,
            ),
          ],
          showingTooltipIndicators: days == 7 && minutes > 0 ? [0] : [],
        ),
      );
    }

    double interval = _calculateYInterval(maxY, isTime: true);
    double adjustedMaxY = (maxY > 0) ? (maxY / interval).ceil() * interval : 10;

    return Container(
      height: 220,
      width: double.infinity,
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            days == 7 ? "Time Invested (Mins)" : "Time Invested (Mins)",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: adjustedMaxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => days == 7 ? Colors.transparent : Colors.blueGrey,
                    tooltipPadding: days == 7 ? EdgeInsets.zero : const EdgeInsets.all(8),
                    tooltipMargin: days == 7 ? 2 : 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final date = dateRange[group.x.toInt()];
                      if (days == 7) {
                        return BarTooltipItem(
                          rod.toY < 1 ? '' : '${rod.toY.toInt()}m',
                          const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 11),
                        );
                      }
                      final dateStr = DateFormat('d MMM').format(date);
                      return BarTooltipItem(
                        '$dateStr\n',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        children: [TextSpan(text: '${rod.toY.toInt()} mins', style: const TextStyle(color: Colors.yellowAccent))],
                      );
                    },
                  ),
                ),
                titlesData: _buildChartTitles(dateRange, days, interval, showLeftTitles: days == 30),
                borderData: FlBorderData(
                  show: true,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
                ),
                gridData: FlGridData(
                  show: days == 30,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                barGroups: barGroups,
              ),
              swapAnimationDuration: const Duration(milliseconds: 1000),
              swapAnimationCurve: Curves.easeOutQuart,
            ),
          ),
        ],
      ),
    );
  }

  double _calculateYInterval(double max, {required bool isTime}) {
    if (max <= 0) return 10;

    if (isTime) {
      if (max <= 30) return 10;
      if (max <= 60) return 15;
      if (max <= 120) return 30;
      if (max <= 300) return 60;
      return 120;
    } else {
      if (max <= 10) return 2;
      if (max <= 20) return 5;
      if (max <= 50) return 10;
      if (max <= 100) return 25;
      if (max <= 200) return 50;
      return 100;
    }
  }

  FlTitlesData _buildChartTitles(List<DateTime> dateRange, int days, double interval, {bool showLeftTitles = false}) {
    return FlTitlesData(
      show: true,
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: showLeftTitles,
            reservedSize: 30,
            interval: interval,
            getTitlesWidget: (value, meta) {
              if (value == 0) return const SizedBox.shrink();
              return Text(value.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 10));
            },
          )
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (double value, TitleMeta meta) {
            int index = value.toInt();
            if (index < 0 || index >= dateRange.length) return const SizedBox.shrink();

            DateTime date = dateRange[index];
            if (days == 7) {
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(DateFormat('E').format(date)[0], style: const TextStyle(fontSize: 11, color: Colors.grey)),
              );
            } else {
              if (index % 5 == 0) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(DateFormat('d/M').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              }
              return const SizedBox.shrink();
            }
          },
          reservedSize: 30,
        ),
      ),
    );
  }

  Widget _buildChartLegend(Color color, String text) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildMetricSection(Map<String, dynamic> stats) {
    final int total = stats['total'] ?? 0;
    final int correct = stats['correct'] ?? 0;
    final int incorrect = stats['incorrect'] ?? 0;
    final int skipped = stats['skipped'] ?? 0;
    final int timeSpent = stats['timeSpent'] ?? 0;
    final double accuracy = (stats['accuracyPercentage'] ?? 0.0).toDouble();
    final double attemptPct = (stats['attemptPercentage'] ?? 0.0).toDouble();
    final behaviorCounts = stats['smartTimeAnalysisCounts'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildStatCard('Accuracy', '${accuracy.toStringAsFixed(1)}%', accuracy / 100, Colors.blue, Icons.gps_fixed),
            const SizedBox(width: 16),
            _buildStatCard('Attempt %', '${attemptPct.toStringAsFixed(1)}%', attemptPct / 100, Colors.orange, Icons.checklist),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildStatCard('Time Spent', _formatTime(timeSpent), 1.0, Colors.purple, Icons.timer_outlined),
            const SizedBox(width: 16),
            _buildStatCard('Total Qs', '$total', 1.0, Colors.teal, Icons.format_list_numbered),
          ],
        ),

        const SizedBox(height: 24),
        _buildResultHorizontalBar(correct, incorrect, skipped),

        const SizedBox(height: 24),
        _buildBehavioralHorizontalBar(behaviorCounts),
      ],
    );
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
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
            const SizedBox(height: 12),
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

  Widget _buildResultHorizontalBar(int correct, int incorrect, int skipped) {
    int total = correct + incorrect + skipped;
    if (total == 0) {
      return Container(
        width: double.infinity,
        decoration: _standardCardDecoration,
        padding: const EdgeInsets.all(24),
        child: const Center(child: Text("No data")),
      );
    }
    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Text("Questions by Result", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const SizedBox(height: 24),
          ClipRRect(
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
                          if (correct > 0) Expanded(flex: correct, child: Container(color: Colors.green)),
                          if (incorrect > 0) Expanded(flex: incorrect, child: Container(color: Colors.red)),
                          if (skipped > 0) Expanded(flex: skipped, child: Container(color: Colors.grey.shade300)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 8, alignment: WrapAlignment.center,
            children: [
              if (correct > 0) _buildLegendItem(Colors.green, 'Correct', correct),
              if (incorrect > 0) _buildLegendItem(Colors.red, 'Incorrect', incorrect),
              if (skipped > 0) _buildLegendItem(Colors.grey.shade300, 'Unattempted', skipped),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBehavioralHorizontalBar(Map<String, dynamic> counts) {
    int totalCount = 0;
    for (var key in _behavioralOrder) {
      totalCount += (counts[key] is int) ? (counts[key] as int) : (counts[key] as num?)?.toInt() ?? 0;
    }
    if (totalCount == 0) {
      return Container(
        width: double.infinity,
        decoration: _standardCardDecoration,
        padding: const EdgeInsets.all(24),
        child: const Center(child: Text("No behavioral data")),
      );
    }
    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text("Questions by Behavior", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const SizedBox(height: 24),
          ClipRRect(
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
                          int val = (counts[key] is int) ? counts[key] : (counts[key] as num?)?.toInt() ?? 0;
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
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: _behavioralOrder.map((key) {
              int val = (counts[key] is int) ? counts[key] : (counts[key] as num?)?.toInt() ?? 0;
              if (val > 0) return _buildLegendItem(_getSmartColor(key), key, val);
              return const SizedBox.shrink();
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text("$text ($count)", style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }

  Widget _buildSlimBar(String label, double pct, Color color) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: pct / 100),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 12,
                  backgroundColor: color.withOpacity(0.1),
                  color: color,
                );
              },
            ),
          ),
        ),
        SizedBox(width: 45, child: Text(" ${pct.toStringAsFixed(0)}%", textAlign: TextAlign.end, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color))),
      ],
    );
  }

  Widget _buildBoldStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  String _formatTime(int totalSeconds) {
    if (totalSeconds < 60) return "${totalSeconds}s";
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    return "${m}m";
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

// =============================================================================
// SEPARATE WIDGET: CHAPTER CARD
// =============================================================================

class _ChapterCard extends StatefulWidget {
  final String name;
  final Map<String, dynamic> stats;
  final VoidCallback? onTap;

  const _ChapterCard({required this.name, required this.stats, this.onTap});

  @override
  State<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends State<_ChapterCard> {
  final List<String> _behavioralOrder = const [
    "Perfect Attempt", "Overtime Correct", "Careless Mistake",
    "Wasted Attempt", "Good Skip", "Time Wasted"
  ];

  @override
  Widget build(BuildContext context) {
    final int total = widget.stats['total'] ?? 0;

    if (total == 0) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(child: Text(widget.name, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
            Text("Not practiced", style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
          ],
        ),
      );
    }

    final int timeSpent = widget.stats['timeSpent'] ?? 0;
    final double accuracy = (widget.stats['accuracyPercentage'] ?? 0.0).toDouble();
    final double attemptPct = (widget.stats['attemptPercentage'] ?? 0.0).toDouble();
    final Timestamp? lastSolved = widget.stats['lastCorrectlySolvedAt'];
    final behaviorCounts = widget.stats['smartTimeAnalysisCounts'] as Map<String, dynamic>? ?? {};

    String lastSolvedStr = "Never";
    if (lastSolved != null) {
      final date = lastSolved.toDate();
      final now = DateTime.now();
      final diff = now.difference(date);
      String timeAgo = "";
      if (diff.inDays > 365) timeAgo = "${(diff.inDays/365).round()}y ago";
      else if (diff.inDays > 30) timeAgo = "${(diff.inDays/30).round()}mo ago";
      else if (diff.inDays > 0) timeAgo = "${diff.inDays}d ago";
      else if (diff.inHours > 0) timeAgo = "${diff.inHours}h ago";
      else timeAgo = "Just now";
      lastSolvedStr = "${DateFormat('d MMM').format(date)} ($timeAgo)";
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                ),
                if (widget.onTap != null)
                  const Icon(Icons.navigate_next, color: Colors.deepPurple, size: 24),
              ],
            ),
            const SizedBox(height: 4),
            Text("Last solved correctly: $lastSolvedStr", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            const SizedBox(height: 16),

            _buildSlimBar("Accuracy", accuracy, Colors.blue),
            const SizedBox(height: 12),
            _buildSlimBar("Attempt", attemptPct, Colors.orange),
            const SizedBox(height: 16),

            Row(
              children: [
                _buildBoldStat("$total", "Total Qs"),
                const SizedBox(width: 32),
                _buildBoldStat(_formatTime(timeSpent), "Time Spent"),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            const Text("Behavioral Analysis", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            _buildBehavioralHorizontalBar(behaviorCounts),
          ],
        ),
      ),
    );
  }

  Widget _buildBehavioralHorizontalBar(Map<String, dynamic> counts) {
    int totalCount = 0;
    for (var key in _behavioralOrder) {
      totalCount += (counts[key] is int) ? (counts[key] as int) : (counts[key] as num?)?.toInt() ?? 0;
    }

    if (totalCount == 0) {
      return const Center(child: Text("No behavioral data", style: TextStyle(color: Colors.grey, fontSize: 12)));
    }

    return Column(
      children: [
        ClipRRect(
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
                    height: 12,
                    child: Row(
                      children: _behavioralOrder.map((key) {
                        int val = (counts[key] is int) ? counts[key] : (counts[key] as num?)?.toInt() ?? 0;
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
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: _behavioralOrder.map((key) {
            int val = (counts[key] is int) ? counts[key] : (counts[key] as num?)?.toInt() ?? 0;
            if (val == 0) return const SizedBox.shrink();
            return _buildLegendItem(_getSmartColor(key), key, val);
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text("$text ($count)", style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }

  Widget _buildSlimBar(String label, double pct, Color color) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: pct / 100),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 12,
                  backgroundColor: color.withOpacity(0.1),
                  color: color,
                );
              },
            ),
          ),
        ),
        SizedBox(width: 45, child: Text(" ${pct.toStringAsFixed(0)}%", textAlign: TextAlign.end, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color))),
      ],
    );
  }

  Widget _buildBoldStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  String _formatTime(int totalSeconds) {
    if (totalSeconds < 60) return "${totalSeconds}s";
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    return "${m}m";
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