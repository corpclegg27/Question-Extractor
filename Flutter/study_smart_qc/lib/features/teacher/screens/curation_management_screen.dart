// lib/features/teacher/screens/curation_management_screen.dart
// Description: Manages a specific curation (View Results & Edit Paper).
// UPDATED: Added 'Move' button for reordering.
// UPDATED: Fixed parsing of 'attemptDocRefs' array of maps.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// WIDGETS & SCREENS
import 'package:study_smart_qc/features/analytics/widgets/attempt_display_card.dart';
import 'package:study_smart_qc/features/analytics/screens/results_screen.dart';
import 'package:study_smart_qc/features/common/widgets/teacher_question_preview_card.dart';

// MODELS & SERVICES
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';

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
  final TestOrchestrationService _testService = TestOrchestrationService();

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

  // --- NAVIGATION LOGIC ---
  Future<void> _handleAttemptClick(AttemptModel attempt) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      List<String> questionIds = attempt.responses.keys.toList();
      if (questionIds.isEmpty) throw Exception("No questions found.");

      List<Question> questions = await _testService.getQuestionsByIds(questionIds);

      final testResult = TestResult(
        attempt: attempt,
        questions: questions,
      );

      if (!mounted) return;
      Navigator.pop(context);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsScreen(result: testResult),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('questions_curation')
            .doc(widget.curationId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Curation not found"));
          }

          final curationData = snapshot.data!.data() as Map<String, dynamic>;

          return TabBarView(
            controller: _tabController,
            children: [
              _ViewResultsTab(
                curationData: curationData,
                onAttemptTap: _handleAttemptClick,
              ),
              _EditPaperTab(
                curationId: widget.curationId,
                curationData: curationData,
                testService: _testService,
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// TAB 1: VIEW RESULTS
// =============================================================================

class _ViewResultsTab extends StatelessWidget {
  final Map<String, dynamic> curationData;
  final Function(AttemptModel) onAttemptTap;

  const _ViewResultsTab({
    required this.curationData,
    required this.onAttemptTap,
  });

  @override
  Widget build(BuildContext context) {
    // Parsing logic for array of maps
    final rawRefs = curationData['attemptDocRefs'];
    List<dynamic> attemptRefs = [];

    if (rawRefs is List) {
      attemptRefs = rawRefs;
    }

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
        results.sort((a, b) => b.attempt.score.compareTo(a.attempt.score));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item = results[index];
            return AttemptDisplayCard(
              attempt: item.attempt,
              studentName: item.studentName,
              studentId: item.studentId,
              onTap: () => onAttemptTap(item.attempt),
            );
          },
        );
      },
    );
  }

  Future<List<_AttemptWithUser>> _resolveAttempts(List<dynamic> refs) async {
    List<_AttemptWithUser> loaded = [];
    for (var item in refs) {
      try {
        DocumentReference? attemptRef;
        DocumentReference? userRef;

        // Correctly handle the Map structure from Firestore
        if (item is Map) {
          // Firestore maps might have keys as String
          if (item['attemptDocRef'] is DocumentReference) {
            attemptRef = item['attemptDocRef'];
          }
          if (item['userId'] is DocumentReference) {
            userRef = item['userId'];
          }
        }
        // Fallback if it's just a reference directly
        else if (item is DocumentReference) {
          attemptRef = item;
        }

        if (attemptRef == null) continue;

        final attemptSnap = await attemptRef.get();
        if (attemptSnap.exists) {
          final attempt = AttemptModel.fromFirestore(attemptSnap);
          String name = "Unknown Student";
          String sid = "N/A";

          // Fetch user details
          if (userRef != null) {
            final userSnap = await userRef.get();
            if(userSnap.exists) {
              final uData = userSnap.data() as Map<String, dynamic>;
              name = uData['displayName'] ?? "Unknown";
              sid = (uData['studentId'] ?? "N/A").toString();
            }
          } else {
            // Fallback: fetch from attempt.userId
            try {
              final userSnap = await FirebaseFirestore.instance.collection('users').doc(attempt.userId).get();
              if(userSnap.exists) {
                final uData = userSnap.data()!;
                name = uData['displayName'] ?? "Unknown";
                sid = (uData['studentId'] ?? "N/A").toString();
              }
            } catch (_) {}
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

// =============================================================================
// TAB 2: EDIT PAPER
// =============================================================================

class _EditPaperTab extends StatefulWidget {
  final String curationId;
  final Map<String, dynamic> curationData;
  final TestOrchestrationService testService;

  const _EditPaperTab({
    required this.curationId,
    required this.curationData,
    required this.testService,
  });

  @override
  State<_EditPaperTab> createState() => _EditPaperTabState();
}

class _EditPaperTabState extends State<_EditPaperTab> {
  // Form Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  // Move Controller (one shared or transient, handled in list builder)

  // State
  DateTime? _deadline;
  bool _isLive = false;
  List<String> _questionIds = [];

  // Cache for loaded questions
  Map<String, Question> _questionCache = {};
  bool _isLoadingQuestions = true;

  // Track text input for move operations per row if needed,
  // but simpler to use a transient controller inside the builder or just a value.
  // We'll use a map of controllers for row-based input.
  final Map<int, TextEditingController> _moveControllers = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant _EditPaperTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.curationData != widget.curationData) {
      _syncFromData(widget.curationData);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _timeController.dispose();
    for (var c in _moveControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadInitialData() {
    _syncFromData(widget.curationData);
    _fetchQuestions();
  }

  void _syncFromData(Map<String, dynamic> data) {
    _titleController.text = data['title'] ?? '';
    _timeController.text = (data['timeLimitMinutes'] ?? 0).toString();

    _isLive = (data['status'] == 'assigned');

    if (data['deadline'] != null) {
      _deadline = (data['deadline'] as Timestamp).toDate();
    }

    final rawIds = data['questionIds'];
    if (rawIds is List) {
      _questionIds = rawIds.map((e) => e.toString()).toList();
    }
  }

  Future<void> _fetchQuestions() async {
    if (_questionIds.isEmpty) {
      setState(() => _isLoadingQuestions = false);
      return;
    }

    try {
      List<String> missingIds = _questionIds.where((id) => !_questionCache.containsKey(id)).toList();

      if (missingIds.isNotEmpty) {
        List<Question> fetched = await widget.testService.getQuestionsByIds(missingIds);
        for (var q in fetched) {
          _questionCache[q.id] = q;
          if(q.customId.isNotEmpty) _questionCache[q.customId] = q;
        }
      }
    } catch (e) {
      debugPrint("Error fetching questions: $e");
    } finally {
      if (mounted) setState(() => _isLoadingQuestions = false);
    }
  }

  // --- ACTIONS ---

  Future<void> _updateField(String key, dynamic value) async {
    await FirebaseFirestore.instance
        .collection('questions_curation')
        .doc(widget.curationId)
        .update({key: value});
  }

  Future<void> _toggleLive(bool value) async {
    String newStatus = value ? 'assigned' : 'draft';
    setState(() => _isLive = value);
    await _updateField('status', newStatus);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(_deadline ?? now)
      );

      if (pickedTime != null) {
        final fullDate = DateTime(
            pickedDate.year, pickedDate.month, pickedDate.day,
            pickedTime.hour, pickedTime.minute
        );
        setState(() => _deadline = fullDate);
        await _updateField('deadline', Timestamp.fromDate(fullDate));
      }
    }
  }

  Future<void> _moveQuestion(int currentIndex, String rawTargetPos) async {
    int? targetPos = int.tryParse(rawTargetPos);
    if (targetPos == null || targetPos < 1 || targetPos > _questionIds.length) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid position")));
      return;
    }

    int targetIndex = targetPos - 1; // 0-based
    if (targetIndex == currentIndex) return;

    List<String> newList = List.from(_questionIds);
    String id = newList.removeAt(currentIndex);
    newList.insert(targetIndex, id);

    // Optimistic Update
    setState(() => _questionIds = newList);

    // Clear input
    _moveControllers[currentIndex]?.clear();

    // Write to DB
    await _updateField('questionIds', newList);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. BASIC DETAILS CARD
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),

                // Title Field
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: "Title",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onSubmitted: (val) => _updateField('title', val),
                ),
                const SizedBox(height: 12),

                // Time Limit
                TextField(
                  controller: _timeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Time Limit (Minutes)",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    suffixText: "min",
                  ),
                  onSubmitted: (val) {
                    int? min = int.tryParse(val);
                    if (min != null) _updateField('timeLimitMinutes', min);
                  },
                ),
                const SizedBox(height: 12),

                // Live Switch
                SwitchListTile(
                  title: const Text("Is Live?", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_isLive ? "Students can attempt" : "Hidden from students"),
                  value: _isLive,
                  activeColor: Colors.green,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _toggleLive,
                ),

                // Deadline
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Deadline", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_deadline != null ? DateFormat('MMM d, h:mm a').format(_deadline!) : "No deadline set"),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: _pickDeadline,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        const Text("Questions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
        const SizedBox(height: 12),

        // 2. QUESTION LIST
        if (_isLoadingQuestions)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (_questionIds.isEmpty)
          const Center(child: Text("No questions added yet."))
        else
          ..._buildQuestionList(),
      ],
    );
  }

  List<Widget> _buildQuestionList() {
    return List.generate(_questionIds.length, (index) {
      final qId = _questionIds[index];

      // Initialize controller for this row if not exists
      _moveControllers.putIfAbsent(index, () => TextEditingController());

      Question? q = _questionCache[qId];
      if (q == null) {
        try {
          q = _questionCache.values.firstWhere((element) => element.id == qId || element.customId == qId || element.questionNo.toString() == qId);
        } catch (_) {}
      }

      if (q == null) {
        return Card(child: ListTile(title: Text("Error loading QID: $qId")));
      }

      // 3. WRAPPER FOR REORDERING
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            // Move Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
                    child: Text("${index + 1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  const Text("Move to:", style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    height: 30,
                    child: TextField(
                      controller: _moveControllers[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // [NEW] MOVE BUTTON
                  SizedBox(
                    height: 30,
                    child: ElevatedButton(
                      onPressed: () => _moveQuestion(index, _moveControllers[index]!.text),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)
                      ),
                      child: const Text("Move"),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),

            // The Question Card
            QuestionPreviewCard(question: q),
          ],
        ),
      );
    });
  }
}