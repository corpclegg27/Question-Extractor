// lib/features/analytics/screens/smart_question_review_screen.dart
// Description: Displays list of mistakes with "Not Fixed" vs "Fixed" tabs.
// UPDATED: Added Aggregation Logic. Toggling 'Fixed' now updates counters in 'student_deep_analysis'.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/analytics/widgets/student_question_review_card.dart';
import 'package:study_smart_qc/models/question_model.dart';

class SmartQuestionReviewScreen extends StatefulWidget {
  final String userId;
  final String chapterName;
  final String? topicName;
  final String title;
  final List<String> targetTags;

  const SmartQuestionReviewScreen({
    super.key,
    required this.userId,
    required this.chapterName,
    this.topicName,
    required this.title,
    required this.targetTags,
  });

  @override
  State<SmartQuestionReviewScreen> createState() => _SmartQuestionReviewScreenState();
}

class _SmartQuestionReviewScreenState extends State<SmartQuestionReviewScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allLoadedData = [];
  late TabController _tabController;

  // Track counts for the tabs
  int _notFixedCount = 0;
  int _fixedCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('attempt_items_detailed')
          .where('userId', isEqualTo: widget.userId)
          .where('chapter', isEqualTo: widget.chapterName);

      if (widget.topicName != null && widget.topicName!.isNotEmpty) {
        query = query.where('topic', isEqualTo: widget.topicName);
      }

      // [FIX] Removed limit(100) to ensure we get ALL attempts for this chapter.
      final ledgerQuery = await query
          .orderBy('attemptedAt', descending: true)
          .get();

      List<QueryDocumentSnapshot> matchingDocs = [];

      // Filter locally by tags
      for (var doc in ledgerQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final String tag = data['smartTag'] ?? '';

        bool match = false;
        for (String target in widget.targetTags) {
          if (tag.contains(target)) {
            match = true;
            break;
          }
        }
        if (match) matchingDocs.add(doc);
      }

      if (matchingDocs.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Fetch Question Details
      List<String> qIds = matchingDocs.map((d) => d['questionId'] as String).toSet().toList();
      Map<String, Question> questionMap = {};

      for (var i = 0; i < qIds.length; i += 10) {
        final end = (i + 10 < qIds.length) ? i + 10 : qIds.length;
        final chunk = qIds.sublist(i, end);
        final qSnap = await FirebaseFirestore.instance
            .collection('questions')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (var doc in qSnap.docs) {
          questionMap[doc.id] = Question.fromFirestore(doc);
        }
      }

      List<Map<String, dynamic>> finalData = [];
      int nf = 0;
      int f = 0;

      for (var ledgerDoc in matchingDocs) {
        final lData = ledgerDoc.data() as Map<String, dynamic>;
        final qId = lData['questionId'];
        final question = questionMap[qId];
        final bool isFixed = lData['isMistakeFixed'] ?? false;

        if (question != null) {
          finalData.add({
            'question': question,
            'attempt': lData,
            'docId': ledgerDoc.id,
          });

          // Calculate initial counts
          if (isFixed) {
            f++;
          } else {
            nf++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _allLoadedData = finalData;
          _notFixedCount = nf;
          _fixedCount = f;
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint("Error fetching smart review data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFixedStatus(String docId, bool currentStatus) async {
    // 1. Find the item locally
    final index = _allLoadedData.indexWhere((element) => element['docId'] == docId);
    if (index == -1) return;

    final attemptData = _allLoadedData[index]['attempt'];
    final String fullTag = attemptData['smartTag'] ?? '';

    // Extract Short Key (e.g., "Careless Mistake" from "Careless Mistake (Incorrect...)")
    String shortKey = fullTag.split('(').first.trim();
    if (shortKey.isEmpty) shortKey = "Unknown";

    // 2. Optimistic Update UI
    setState(() {
      bool newStatus = !currentStatus;
      _allLoadedData[index]['attempt']['isMistakeFixed'] = newStatus;

      if (newStatus) {
        _notFixedCount--;
        _fixedCount++;
      } else {
        _notFixedCount++;
        _fixedCount--;
      }
    });

    // 3. Background Update Firestore (Batch)
    try {
      final batch = FirebaseFirestore.instance.batch();

      // A. Update the specific attempt item
      final attemptRef = FirebaseFirestore.instance.collection('attempt_items_detailed').doc(docId);
      batch.update(attemptRef, {'isMistakeFixed': !currentStatus});

      // B. Update Aggregates in 'student_deep_analysis'
      final analysisRef = FirebaseFirestore.instance.collection('student_deep_analysis').doc(widget.userId);

      int change = !currentStatus ? 1 : -1; // +1 if fixing, -1 if unfixing

      // Update Chapter Level
      // Note: We use dot notation for nested fields
      batch.update(analysisRef, {
        'breakdownByChapter.${widget.chapterName}.smartTimeAnalysisFixedCounts.$shortKey': FieldValue.increment(change)
      });

      // Update Topic Level (if context exists and topic is known)
      // We use the topic from the attempt item itself to be safe, or fall back to widget.topicName
      String? actualTopic = attemptData['topic'] ?? widget.topicName;

      if (actualTopic != null && actualTopic.isNotEmpty) {
        batch.update(analysisRef, {
          'breakdownByTopic.${widget.chapterName}.$actualTopic.smartTimeAnalysisFixedCounts.$shortKey': FieldValue.increment(change)
        });
      }

      await batch.commit();
      debugPrint("✅ Synced fixed status for $shortKey");

    } catch (e) {
      debugPrint("❌ Error updating fixed status: $e");
      // Optionally revert UI here if strict consistency is needed
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TabBar(
              controller: _tabController,
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
              tabs: [
                Tab(text: "Not Fixed ($_notFixedCount)"),
                Tab(text: "Fixed ($_fixedCount)"),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildQuestionList(showFixedOnly: false), // Tab 1: Pending
          _buildQuestionList(showFixedOnly: true),  // Tab 2: Fixed
        ],
      ),
    );
  }

  Widget _buildQuestionList({required bool showFixedOnly}) {
    final filtered = _allLoadedData.where((item) {
      final isFixed = item['attempt']['isMistakeFixed'] ?? false;
      return showFixedOnly ? isFixed : !isFixed;
    }).toList();

    if (filtered.isEmpty) {
      return _buildEmptyState(showFixedOnly);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        final Question q = item['question'];
        final Map<String, dynamic> a = item['attempt'];
        final String docId = item['docId'];
        final bool isFixed = a['isMistakeFixed'] ?? false;

        return QuestionReviewCard(
          key: ValueKey(docId),
          questionId: q.id,
          index: index,
          questionType: q.type.name,
          imageUrl: q.imageUrl,
          solutionUrl: q.solutionUrl,
          aiSolutionText: q.aiGenSolutionText,
          status: a['status'] ?? 'SKIPPED',
          timeSpent: a['timeSpent'] ?? 0,
          smartTag: a['smartTag'] ?? '',
          userOption: a['selectedOption'] ?? 'Not Answered',
          correctOption: a['correctOption'] ?? q.correctAnswer.toString(),
          marks: (a['status'] == 'CORRECT') ? 4 : (a['status'] == 'INCORRECT' ? -1 : 0),
          isFixed: isFixed,
          onFixToggle: () => _toggleFixedStatus(docId, isFixed),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isFixedTab) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
              isFixedTab ? Icons.assignment_outlined : Icons.check_circle_outline,
              size: 64,
              color: isFixedTab ? Colors.grey.shade300 : Colors.green.shade200
          ),
          const SizedBox(height: 16),
          Text(
            isFixedTab
                ? "No fixed items yet."
                : "All issues fixed!",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isFixedTab
                ? "Mark items as fixed to see them here."
                : "Great job clearing your backlog!",
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}