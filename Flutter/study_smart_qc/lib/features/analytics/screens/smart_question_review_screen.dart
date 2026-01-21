// lib/features/analytics/screens/smart_question_review_screen.dart
// Description: Displays list of mistakes.
// UPDATED:
// 1. Removed external "Mark as Fixed" button.
// 2. Passes fix-logic directly into QuestionReviewCard.
// 3. Maintains 'Sticky' visibility to prevent UI jumping.

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
  final List<String> tabLabels;

  const SmartQuestionReviewScreen({
    super.key,
    required this.userId,
    required this.chapterName,
    this.topicName,
    required this.title,
    required this.targetTags,
    required this.tabLabels,
  });

  @override
  State<SmartQuestionReviewScreen> createState() => _SmartQuestionReviewScreenState();
}

class _SmartQuestionReviewScreenState extends State<SmartQuestionReviewScreen> with TickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allLoadedData = [];
  late TabController _tabController;

  bool _hideFixedMistakes = true;
  final Set<String> _recentlyToggledIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.tabLabels.length > 1) {
      _tabController = TabController(length: widget.tabLabels.length, vsync: this);
    }
    _fetchData();
  }

  @override
  void dispose() {
    if (widget.tabLabels.length > 1) {
      _tabController.dispose();
    }
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

      final ledgerQuery = await query
          .orderBy('attemptedAt', descending: true)
          .limit(100)
          .get();

      List<QueryDocumentSnapshot> matchingDocs = [];

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
      for (var ledgerDoc in matchingDocs) {
        final lData = ledgerDoc.data() as Map<String, dynamic>;
        final qId = lData['questionId'];
        final question = questionMap[qId];

        if (question != null) {
          finalData.add({
            'question': question,
            'attempt': lData,
            'docId': ledgerDoc.id,
          });
        }
      }

      if (mounted) {
        setState(() {
          _allLoadedData = finalData;
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint("Error fetching smart review data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFixedStatus(String docId, bool currentStatus) async {
    setState(() {
      final index = _allLoadedData.indexWhere((element) => element['docId'] == docId);
      if (index != -1) {
        _allLoadedData[index]['attempt']['isMistakeFixed'] = !currentStatus;
        // Keep visible during this session
        _recentlyToggledIds.add(docId);
      }
    });

    try {
      await FirebaseFirestore.instance
          .collection('attempt_items_detailed')
          .doc(docId)
          .update({'isMistakeFixed': !currentStatus});
    } catch (e) {
      debugPrint("Error updating fixed status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool useTabs = widget.tabLabels.length > 1;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          Row(
            children: [
              Text(
                _hideFixedMistakes ? "Hide Fixed" : "Show Fixed",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
              ),
              Switch(
                value: _hideFixedMistakes,
                activeThumbColor: Colors.deepPurple,
                onChanged: (val) => setState(() => _hideFixedMistakes = val),
              ),
              const SizedBox(width: 8),
            ],
          )
        ],
        bottom: useTabs ? PreferredSize(
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
              tabs: widget.tabLabels.map((label) => Tab(text: label)).toList(),
            ),
          ),
        ) : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : useTabs
          ? TabBarView(
        controller: _tabController,
        children: widget.tabLabels.map((label) {
          return _buildQuestionList(_allLoadedData, label);
        }).toList(),
      )
          : _buildQuestionList(_allLoadedData, widget.tabLabels.first),
    );
  }

  Widget _buildQuestionList(List<Map<String, dynamic>> allData, String activeLabel) {
    var filtered = allData.where((item) {
      final tag = item['attempt']['smartTag'] ?? '';
      return tag.contains(activeLabel);
    }).toList();

    if (_hideFixedMistakes) {
      filtered = filtered.where((item) {
        final docId = item['docId'];
        final isFixed = item['attempt']['isMistakeFixed'] ?? false;
        // Show if NOT fixed OR if recently toggled
        return !isFixed || _recentlyToggledIds.contains(docId);
      }).toList();
    }

    if (filtered.isEmpty) return _buildEmptyState(activeLabel);

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
          index: index,
          questionType: q.type.name,
          imageUrl: q.imageUrl,
          solutionUrl: q.solutionUrl,
          status: a['status'] ?? 'SKIPPED',
          timeSpent: a['timeSpent'] ?? 0,
          smartTag: a['smartTag'] ?? '',
          userOption: a['selectedOption'] ?? 'Not Answered',
          correctOption: a['correctOption'] ?? q.correctAnswer.toString(),
          marks: (a['status'] == 'CORRECT') ? 4 : (a['status'] == 'INCORRECT' ? -1 : 0),

          // [NEW] Pass State & Callback
          isFixed: isFixed,
          onFixToggle: () => _toggleFixedStatus(docId, isFixed),
        );
      },
    );
  }

  Widget _buildEmptyState(String label) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade200),
          const SizedBox(height: 16),
          Text(
            _hideFixedMistakes ? "All '$label' issues fixed!" : "No '$label' items found!",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text("Great job!", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}