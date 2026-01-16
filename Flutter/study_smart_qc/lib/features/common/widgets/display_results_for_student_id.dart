// lib/features/common/widgets/display_results_for_student_id.dart
// Description: Reusable widget that displays the analytics dashboard.
// Updated: Behavioral breakdown row order changed to Text -> Graph -> Number.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/features/analytics/widgets/attempt_list_widget.dart';

class DisplayResultsForStudentId extends StatefulWidget {
  final String? targetStudentUid; // If null, defaults to current user

  const DisplayResultsForStudentId({
    super.key,
    this.targetStudentUid,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. MAIN TAB BAR
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
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicatorPadding: const EdgeInsets.all(4),
            tabs: const [
              Tab(text: "Dashboard"),
              Tab(text: "Assignments"),
              Tab(text: "Tests"),
            ],
          ),
        ),

        // 2. TAB VIEW
        Expanded(
          child: TabBarView(
            controller: _mainTabController,
            children: [
              _DashboardTab(targetUserId: widget.targetStudentUid),
              _buildAssignmentsAnalysisTab(),
              AttemptListWidget(
                filterMode: 'Test',
                onlySingleAttempt: true,
                targetUserId: widget.targetStudentUid,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssignmentsAnalysisTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            height: 36,
            child: const TabBar(
              isScrollable: false,
              labelColor: Colors.deepPurple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.deepPurple,
              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
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
// INTERNAL WIDGET: DASHBOARD TAB
// =============================================================================

class _DashboardTab extends StatefulWidget {
  final String? targetUserId;
  const _DashboardTab({this.targetUserId});
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

        final data = snapshot.data!.data() as Map<String, dynamic>;

        final summary = data['summary'] as Map<String, dynamic>? ?? {};
        final lastMonth = data['summary_lastMonth'] as Map<String, dynamic>? ?? {};
        final lastWeek = data['summary_lastWeek'] as Map<String, dynamic>? ?? {};
        final chapterData = data['breakdownByChapter'] as Map<String, dynamic>? ?? {};

        final Timestamp? lastUpdated = data['lastUpdated'];
        String lastUpdatedStr = "Unknown";
        if (lastUpdated != null) {
          lastUpdatedStr = DateFormat('d MMM y, h:mm a').format(lastUpdated.toDate());
        }

        return Column(
          children: [
            // --- HEADER: ANALYSIS AS ON ---
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

            // --- NESTED TIME PERIOD TABS ---
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                tabs: const [
                  Tab(text: "All Time"),
                  Tab(text: "Last Month"),
                  Tab(text: "Last Week"),
                ],
              ),
            ),

            // --- CONTENT AREA ---
            Expanded(
              child: TabBarView(
                controller: _timeTabController,
                children: [
                  _buildSinglePageView(summary, chapterData, "No activity yet."),
                  _buildSinglePageView(lastMonth, null, "No activity in the last 30 days."),
                  _buildSinglePageView(lastWeek, null, "No activity in the last 7 days."),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSinglePageView(Map<String, dynamic> stats, Map<String, dynamic>? chapterData, String emptyMsg) {
    if ((stats['total'] ?? 0) == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(emptyMsg, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
    }

    List<MapEntry<String, dynamic>> sortedChapters = [];
    if (chapterData != null) {
      sortedChapters = chapterData.entries.toList();
      sortedChapters.sort((a, b) {
        final totalA = a.value['total'] ?? 0;
        final totalB = b.value['total'] ?? 0;
        return totalB.compareTo(totalA);
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetricSection(stats),
          const SizedBox(height: 32),

          if (sortedChapters.isNotEmpty) ...[
            _buildHeader("Chapter Breakdown"),
            ...sortedChapters.map((entry) {
              return _ChapterCard(
                  name: entry.key,
                  stats: entry.value
              );
            }),
          ],
        ],
      ),
    );
  }

  // --- TOP LEVEL METRICS ---
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
        _buildHeader("Questions by Result"),
        _buildResultPieChart(correct, incorrect, skipped),
        const SizedBox(height: 24),
        _buildHeader("Questions by Behavior"),
        _buildBehaviorPieChart(behaviorCounts),
      ],
    );
  }

  // --- HELPERS ---
  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)
      ),
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

  Widget _buildResultPieChart(int correct, int incorrect, int skipped) {
    final bool isEmpty = (correct == 0 && incorrect == 0 && skipped == 0);
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
                  if(correct > 0) _buildSection(correct.toDouble(), '$correct', Colors.green),
                  if(incorrect > 0) _buildSection(incorrect.toDouble(), '$incorrect', Colors.red),
                  if(skipped > 0) _buildSection(skipped.toDouble(), '$skipped', Colors.grey.shade300, textColor: Colors.black54),
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

  Widget _buildBehaviorPieChart(Map<String, dynamic> counts) {
    // Fixed order
    final List<String> order = ["Perfect Attempt", "Overtime Correct", "Careless Mistake", "Wasted Attempt", "Good Skip", "Time Wasted"];
    List<PieChartSectionData> sections = [];
    int totalCount = 0;

    for (var key in order) {
      int val = (counts[key] is int) ? counts[key] : (counts[key] as num?)?.toInt() ?? 0;
      if (val > 0) {
        sections.add(_buildSection(val.toDouble(), '$val', _getSmartColor(key)));
        totalCount += val;
      }
    }

    if (totalCount == 0) {
      return Container(width: double.infinity, decoration: _standardCardDecoration, padding: const EdgeInsets.all(24), child: const Center(child: Text("No behavioral data")));
    }

    Widget legend = Wrap(
      spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
      children: order.map((key) {
        int val = (counts[key] is int) ? counts[key] : (counts[key] as num?)?.toInt() ?? 0;
        if (val > 0) return _buildLegendItem(_getSmartColor(key), '$key ($val)');
        return const SizedBox.shrink();
      }).toList(),
    );

    return Container(
      decoration: _standardCardDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Column(children: [SizedBox(height: 200, child: PieChart(PieChartData(sectionsSpace: 2, centerSpaceRadius: 40, startDegreeOffset: 270, sections: sections))), const SizedBox(height: 24), legend]),
    );
  }

  PieChartSectionData _buildSection(double value, String title, Color color, {Color textColor = Colors.white}) {
    return PieChartSectionData(value: value, title: title, color: color, radius: 50, titleStyle: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14));
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87))]);
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
// SEPARATE WIDGET: CHAPTER CARD (With State for Expansion)
// =============================================================================

class _ChapterCard extends StatefulWidget {
  final String name;
  final Map<String, dynamic> stats;

  const _ChapterCard({required this.name, required this.stats});

  @override
  State<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends State<_ChapterCard> {
  bool _isExpanded = false;

  final List<String> _behavioralOrder = const [
    "Perfect Attempt", "Overtime Correct", "Careless Mistake",
    "Wasted Attempt", "Good Skip", "Time Wasted"
  ];

  @override
  Widget build(BuildContext context) {
    final int total = widget.stats['total'] ?? 0;

    // --- CASE 1: UNATTEMPTED ---
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

    // --- CASE 2: ATTEMPTED ---
    final int timeSpent = widget.stats['timeSpent'] ?? 0;
    final double accuracy = (widget.stats['accuracyPercentage'] ?? 0.0).toDouble();
    final double attemptPct = (widget.stats['attemptPercentage'] ?? 0.0).toDouble();
    final Timestamp? lastSolved = widget.stats['lastCorrectlySolvedAt'];
    final behaviorCounts = widget.stats['smartTimeAnalysisCounts'] as Map<String, dynamic>? ?? {};

    // Calculate Max Count for scaling bars
    int maxBehaviorCount = 0;
    behaviorCounts.forEach((k, v) {
      int c = (v as num).toInt();
      if (c > maxBehaviorCount) maxBehaviorCount = c;
    });
    if (maxBehaviorCount == 0) maxBehaviorCount = 1;

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

    return Container(
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
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text("Last solved correctly: $lastSolvedStr", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 16),

          // Row 1: Accuracy Bar
          _buildSlimBar("Accuracy", accuracy, Colors.blue),
          const SizedBox(height: 12),

          // Row 2: Attempt Bar
          _buildSlimBar("Attempt", attemptPct, Colors.orange),
          const SizedBox(height: 16),

          // Row 3: Big Stats
          Row(
            children: [
              _buildBoldStat("$total", "Total Qs"),
              const SizedBox(width: 32),
              _buildBoldStat(_formatTime(timeSpent), "Time Spent"),
            ],
          ),
          const SizedBox(height: 16),

          // Row 4: Expand Button
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              width: double.infinity,
              color: Colors.transparent,
              child: Row(
                children: [
                  Text(_isExpanded ? "Hide behavioral analysis" : "View behavioral analysis",
                      style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(_isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.deepPurple, size: 18),
                ],
              ),
            ),
          ),

          // EXPANDED CONTENT
          if (_isExpanded) ...[
            const Divider(height: 24),
            ..._behavioralOrder.map((key) {
              int count = (behaviorCounts[key] is int) ? behaviorCounts[key] : (behaviorCounts[key] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildBehaviorRow(key, count, maxBehaviorCount, _getSmartColor(key)),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildSlimBar(String label, double pct, Color color) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 6,
              backgroundColor: color.withOpacity(0.1),
              color: color,
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

  Widget _buildBehaviorRow(String label, int count, int maxCount, Color color) {
    // Scaling relative to MAX value in the set, not total.
    double pct = maxCount > 0 ? count / maxCount : 0;

    return Row(
      children: [
        // 1. Label (First)
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),

        // 2. Bar (Middle)
        Expanded(
          child: Stack(
            children: [
              // No background track as requested ("no gray areas")
              Container(height: 8),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // 3. Count (Last)
        SizedBox(
          width: 24,
          child: Text("$count", textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
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