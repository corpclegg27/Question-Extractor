// lib/features/analytics/screens/student_chapter_detailed_view.dart
// Description: Detailed Chapter View.
// - Zone A: Chapter Card (Overview + Stacked Bar).
// - Zone B: Smart Action Grid (Chapter Level).
// - Zone C: Topic List (Topic Cards + Stacked Bar + Topic Smart Actions).
// UPDATED: Added a subtle divider above "Topic Breakdown" for better visual separation.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/features/analytics/screens/smart_question_review_screen.dart';

class StudentChapterDetailedView extends StatelessWidget {
  final String userId;
  final String chapterName;
  final String subjectName;
  final Map<String, dynamic> analysisDoc;

  const StudentChapterDetailedView({
    super.key,
    required this.userId,
    required this.chapterName,
    required this.subjectName,
    required this.analysisDoc,
  });

  @override
  Widget build(BuildContext context) {
    final chapterStats = _safeGet(analysisDoc, ['breakdownByChapter', chapterName]);
    final topicsMap = _safeGet(analysisDoc, ['breakdownByTopic', chapterName]);
    final smartCounts = chapterStats['smartTimeAnalysisCounts'] as Map<String, dynamic>? ?? {};

    List<MapEntry<String, dynamic>> topicList = [];
    if (topicsMap is Map) {
      final typedMap = Map<String, dynamic>.from(topicsMap);
      topicList = typedMap.entries.toList();
      topicList.sort((a, b) {
        final double accA = (a.value['accuracyPercentage'] ?? 0).toDouble();
        final double accB = (b.value['accuracyPercentage'] ?? 0).toDouble();
        return accA.compareTo(accB);
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: Text(chapterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ZONE A: CHAPTER OVERVIEW
            _ChapterCard(name: chapterName, stats: chapterStats),
            const SizedBox(height: 24),

            // ZONE B: CHAPTER SMART ACTIONS
            const Text("Smart Actions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            const SizedBox(height: 12),
            SmartActionGrid(
              userId: userId,
              chapterName: chapterName,
              counts: smartCounts,
              topicName: null, // Chapter Level
            ),

            // [UPDATED] Subtle Divider Section
            const SizedBox(height: 24),
            const Divider(color: Color(0xFFEEEEEE), thickness: 1.5),
            const SizedBox(height: 16),

            // ZONE C: TOPIC HEATMAP
            const Text("Topic Breakdown", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            const SizedBox(height: 12),
            if (topicList.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("No topic data available yet.")))
            else
              ...topicList.map((e) => _TopicCard(
                name: e.key,
                stats: e.value,
                userId: userId,
                chapterName: chapterName,
              )),
          ],
        ),
      ),
    );
  }

  dynamic _safeGet(Map<String, dynamic> data, List<String> path) {
    dynamic current = data;
    for (var key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return {};
      }
    }
    return current;
  }
}

// =============================================================================
// REUSABLE SMART ACTION GRID (With Positive Reinforcement)
// =============================================================================

class SmartActionGrid extends StatelessWidget {
  final String userId;
  final String chapterName;
  final String? topicName;
  final Map<String, dynamic> counts;

  const SmartActionGrid({
    super.key,
    required this.userId,
    required this.chapterName,
    required this.counts,
    this.topicName,
  });

  @override
  Widget build(BuildContext context) {
    int careless = _getCount(counts, "Careless Mistake");
    int wasted = _getCount(counts, "Wasted Attempt") + _getCount(counts, "Time Wasted");
    int overtime = _getCount(counts, "Overtime Correct");
    int goodSkip = _getCount(counts, "Good Skip");

    // Counts for cards
    int fixMistakesCount = careless + _getCount(counts, "Wasted Attempt");
    int skippedCount = goodSkip + _getCount(counts, "Time Wasted");

    // Calculate total activity
    int totalActivity = 0;
    counts.forEach((_, value) => totalActivity += (value as num).toInt());

    // --- POSITIVE REINFORCEMENT LOGIC ---
    bool isCleanStreak = totalActivity > 0 && fixMistakesCount == 0;
    bool isPerfectSpeed = totalActivity > 0 && overtime == 0;

    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            title: isCleanStreak ? "Clean Streak" : "Fix Mistakes",
            count: fixMistakesCount,
            color: isCleanStreak ? Colors.amber.shade700 : Colors.red.shade400,
            icon: isCleanStreak ? Icons.emoji_events_rounded : Icons.bug_report_outlined,
            tags: const ["Careless Mistake", "Wasted Attempt"],
            tabLabels: const ["Careless Mistake", "Wasted Attempt"],
            subtitle: isCleanStreak ? "No silly errors!" : "Review errors",
            userId: userId,
            chapterName: chapterName,
            topicName: topicName,
            isSuccessState: isCleanStreak,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionCard(
            title: isPerfectSpeed ? "Perfect Pace" : "Speed Up",
            count: overtime,
            color: isPerfectSpeed ? Colors.green.shade600 : Colors.blue.shade400,
            icon: isPerfectSpeed ? Icons.timer_off_outlined : Icons.speed,
            tags: const ["Overtime Correct"],
            tabLabels: const ["Overtime Correct"],
            subtitle: isPerfectSpeed ? "Fast & accurate" : "Solve quickly",
            userId: userId,
            chapterName: chapterName,
            topicName: topicName,
            isSuccessState: isPerfectSpeed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionCard(
            title: "Try Skipped",
            count: skippedCount,
            color: Colors.orange.shade400,
            icon: Icons.redo,
            tags: const ["Good Skip", "Time Wasted"],
            tabLabels: const ["Good Skip", "Time Wasted"],
            subtitle: "Attempt now",
            userId: userId,
            chapterName: chapterName,
            topicName: topicName,
            isSuccessState: false,
          ),
        ),
      ],
    );
  }

  int _getCount(Map<String, dynamic> counts, String key) {
    return (counts[key] as num?)?.toInt() ?? 0;
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final IconData icon;
  final List<String> tags;
  final List<String> tabLabels;
  final String subtitle;
  final String userId;
  final String chapterName;
  final String? topicName;
  final bool isSuccessState;

  const _ActionCard({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
    required this.tags,
    required this.tabLabels,
    required this.subtitle,
    required this.userId,
    required this.chapterName,
    this.topicName,
    this.isSuccessState = false,
  });

  @override
  Widget build(BuildContext context) {
    bool isEmpty = count == 0 && !isSuccessState;

    VoidCallback? onTap = (isEmpty || isSuccessState) ? null : () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SmartQuestionReviewScreen(
            userId: userId,
            chapterName: chapterName,
            topicName: topicName,
            title: topicName != null ? "$title ($topicName)" : title,
            targetTags: tags,
          ),
        ),
      );
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isEmpty ? Colors.grey.shade200 : color.withOpacity(isSuccessState ? 0.6 : 0.3),
              width: 1.5
          ),
          boxShadow: [
            if (!isEmpty)
              BoxShadow(color: color.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: isEmpty ? Colors.grey.shade300 : color, size: 20),
                if (!isEmpty)
                  isSuccessState
                      ? Icon(Icons.check_circle, size: 16, color: color)
                      : Text("$count", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isEmpty ? Colors.grey : Colors.black87), overflow: TextOverflow.ellipsis),
                Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// REUSABLE CARD LOGIC (Shared Style for Chapter & Topic)
// =============================================================================

class _ChapterCard extends StatelessWidget {
  final String name;
  final Map<String, dynamic> stats;

  const _ChapterCard({required this.name, required this.stats});

  @override
  Widget build(BuildContext context) {
    return _BaseDetailCard(name: name, stats: stats, isChapter: true);
  }
}

class _TopicCard extends StatelessWidget {
  final String name;
  final Map<String, dynamic> stats;
  final String userId;
  final String chapterName;

  const _TopicCard({
    required this.name,
    required this.stats,
    required this.userId,
    required this.chapterName,
  });

  @override
  Widget build(BuildContext context) {
    return _BaseDetailCard(
      name: name,
      stats: stats,
      isChapter: false,
      userId: userId,
      chapterName: chapterName,
    );
  }
}

class _BaseDetailCard extends StatelessWidget {
  final String name;
  final Map<String, dynamic> stats;
  final bool isChapter;
  final String? userId;
  final String? chapterName;

  const _BaseDetailCard({
    required this.name,
    required this.stats,
    required this.isChapter,
    this.userId,
    this.chapterName,
  });

  final List<String> _behavioralOrder = const [
    "Perfect Attempt", "Overtime Correct", "Careless Mistake",
    "Wasted Attempt", "Good Skip", "Time Wasted"
  ];

  @override
  Widget build(BuildContext context) {
    final int total = stats['total'] ?? 0;

    if (total == 0) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(child: Text(name, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
            Text("Not practiced", style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
          ],
        ),
      );
    }

    final int timeSpent = stats['timeSpent'] ?? 0;
    final double accuracy = (stats['accuracyPercentage'] ?? 0.0).toDouble();
    final double attemptPct = (stats['attemptPercentage'] ?? 0.0).toDouble();
    final Timestamp? lastSolved = stats['lastCorrectlySolvedAt'];
    final behaviorCounts = stats['smartTimeAnalysisCounts'] as Map<String, dynamic>? ?? {};

    String lastSolvedStr = "Never";
    if (lastSolved != null) {
      final date = lastSolved.toDate();
      final now = DateTime.now();
      final diff = now.difference(date);
      String timeAgo = "";
      if (diff.inDays > 365) {
        timeAgo = "${(diff.inDays/365).round()}y ago";
      } else if (diff.inDays > 30) timeAgo = "${(diff.inDays/30).round()}mo ago";
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isChapter ? 18 : 15,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (!isChapter)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text("Last solved correctly: $lastSolvedStr", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 16),

          // Animated Bars
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

          if (!isChapter && userId != null && chapterName != null) ...[
            const SizedBox(height: 24),
            const Text("Topic Actions", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            SmartActionGrid(
              userId: userId!,
              chapterName: chapterName!,
              topicName: name,
              counts: behaviorCounts,
            ),
          ],
        ],
      ),
    );
  }

  // --- HORIZONTAL STACKED BAR LOGIC ---

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
        Text("$text ($count)", style: const TextStyle(fontSize: 11, color: Colors.black87)),
      ],
    );
  }

  Widget _buildSlimBar(String label, double pct, Color color) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: pct / 100),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
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