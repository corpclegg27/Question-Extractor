// lib/features/teacher/screens/curation_management_screen.dart
// Description: Manages a specific curation (View Results & Edit Paper).
// UPDATED: Implemented navigation to ResultsScreen by fetching questions on tap.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// WIDGETS & SCREENS
import 'package:study_smart_qc/features/analytics/widgets/attempt_display_card.dart';
import 'package:study_smart_qc/features/analytics/screens/results_screen.dart'; // [NEW]

// MODELS & SERVICES
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/question_model.dart'; // [NEW]
import 'package:study_smart_qc/models/test_result.dart';   // [NEW]
import 'package:study_smart_qc/services/test_orchestration_service.dart'; // [NEW]

class CurationManagementScreen extends StatefulWidget {
  final String curationId;
  final String title;

  const CurationManagementScreen({
    super.key,
    required this.curationId,
    required this.title,
  });

  @override
  State<CurationManagementScreen> createState() => _CurationManagementScreenState();
}

class _CurationManagementScreenState extends State<CurationManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TestOrchestrationService _testService = TestOrchestrationService(); // [NEW] Service instance

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // [NEW] Logic to fetch questions and navigate to Results
  Future<void> _handleAttemptClick(AttemptModel attempt) async {
    // 1. Show Loading Indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 2. Extract Question IDs from the attempt's responses
      // (This ensures we fetch exactly what was attempted/seen)
      List<String> questionIds = attempt.responses.keys.toList();

      if (questionIds.isEmpty) {
        throw Exception("No questions found in this attempt.");
      }

      // 3. Fetch Question Objects
      List<Question> questions = await _testService.getQuestionsByIds(questionIds);

      // 4. Create TestResult Object
      final testResult = TestResult(
        attempt: attempt,
        questions: questions,
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss Loading

      // 5. Navigate
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsScreen(result: testResult),
        ),
      );

    } catch (e) {
      if (mounted) Navigator.pop(context); // Dismiss Loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading results: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: "View Results"),
            Tab(icon: Icon(Icons.edit_note), text: "Edit Paper"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildResultsTab(),
          const Center(child: Text("Manage content logic goes here")),
        ],
      ),
    );
  }

  Widget _buildResultsTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('questions_curation')
          .doc(widget.curationId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text("Assignment not found"));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> attemptRefs = data['attemptDocRefs'] ?? [];

        if (attemptRefs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text("No submissions yet", style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
              ],
            ),
          );
        }

        return FutureBuilder<List<_AttemptWithUser>>(
          future: _resolveAttempts(attemptRefs),
          builder: (context, asyncSnapshot) {
            if (asyncSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (asyncSnapshot.hasError) {
              return Center(child: Text("Error loading results: ${asyncSnapshot.error}"));
            }

            final results = asyncSnapshot.data ?? [];
            results.sort((a, b) => b.attempt.score.compareTo(a.attempt.score)); // Sort by score

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final item = results[index];

                return AttemptDisplayCard(
                  attempt: item.attempt,
                  studentName: item.studentName,
                  studentId: item.studentId,
                  // [UPDATED] Wire up the tap handler
                  onTap: () => _handleAttemptClick(item.attempt),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<List<_AttemptWithUser>> _resolveAttempts(List<dynamic> refs) async {
    List<_AttemptWithUser> loaded = [];
    for (var ref in refs) {
      try {
        DocumentSnapshot attemptSnap;
        if (ref is DocumentReference) {
          attemptSnap = await ref.get();
        } else {
          attemptSnap = await FirebaseFirestore.instance.collection('attempts').doc(ref.toString()).get();
        }

        if (attemptSnap.exists) {
          final attempt = AttemptModel.fromFirestore(attemptSnap);
          String name = "Unknown Student";
          String sid = "N/A";
          try {
            final userSnap = await FirebaseFirestore.instance.collection('users').doc(attempt.userId).get();
            if (userSnap.exists) {
              final userData = userSnap.data()!;
              name = userData['displayName'] ?? "Unknown";
              sid = (userData['studentId'] ?? "N/A").toString();
            }
          } catch (e) {
            debugPrint("Error fetching user for attempt: $e");
          }
          loaded.add(_AttemptWithUser(attempt, name, sid));
        }
      } catch (e) {
        debugPrint("Error resolving attempt ref: $e");
      }
    }
    return loaded;
  }
}

class _AttemptWithUser {
  final AttemptModel attempt;
  final String studentName;
  final String studentId;
  _AttemptWithUser(this.attempt, this.studentName, this.studentId);
}