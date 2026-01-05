import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/common/widgets/question_preview_card.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/services/teacher_service.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';

class CurationManagementScreen extends StatefulWidget {
  final String curationId;
  final String title;

  const CurationManagementScreen({
    Key? key,
    required this.curationId,
    required this.title,
  }) : super(key: key);

  @override
  State<CurationManagementScreen> createState() =>
      _CurationManagementScreenState();
}

class _CurationManagementScreenState extends State<CurationManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TeacherService _teacherService = TeacherService();

  // --- DATA STATE ---
  StreamSubscription<DocumentSnapshot>? _curationSubscription;
  List<String> _questionIds = [];
  bool _isLoaded = false;

  // --- CACHE ---
  final Map<String, Question> _questionCache = {};
  final Set<String> _attemptedFetches = {};
  bool _isLoadingQuestions = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _setupFirestoreListener();
  }

  @override
  void dispose() {
    _curationSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // 1. STABLE LISTENER
  void _setupFirestoreListener() {
    _curationSubscription = FirebaseFirestore.instance
        .collection('questions_curation')
        .doc(widget.curationId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;
        final newIds = List<String>.from(data['questionIds'] ?? []);

        setState(() {
          _questionIds = newIds;
          _isLoaded = true;
        });

        _ensureQuestionsLoaded(newIds);
      }
    }, onError: (e) {
      debugPrint("Error listening to curation: $e");
    });
  }

  // 2. BACKGROUND FETCH
  Future<void> _ensureQuestionsLoaded(List<String> questionIds) async {
    final idsToFetch = questionIds.where((id) =>
    !_questionCache.containsKey(id) && !_attemptedFetches.contains(id)
    ).toList();

    if (idsToFetch.isEmpty) return;
    if (_isLoadingQuestions) return;

    Future.microtask(() async {
      if (!mounted) return;
      setState(() => _isLoadingQuestions = true);
      _attemptedFetches.addAll(idsToFetch);

      try {
        final questions = await TestOrchestrationService().getQuestionsByIds(idsToFetch);
        if (mounted) {
          setState(() {
            for (var q in questions) {
              _questionCache[q.id] = q;
            }
          });
        }
      } catch (e) {
        debugPrint("Error loading questions: $e");
      } finally {
        if (mounted) setState(() => _isLoadingQuestions = false);
      }
    });
  }

  // 3. REORDER LOGIC
  Future<void> _handleReorder(int oldIndex, String newIndexStr) async {
    int? newIndex = int.tryParse(newIndexStr);
    if (newIndex == null) {
      _showSafeSnackBar("Please enter a valid number");
      return;
    }

    int targetIndex = newIndex - 1;
    if (targetIndex < 0 || targetIndex >= _questionIds.length) {
      _showSafeSnackBar("Position must be between 1 and ${_questionIds.length}");
      return;
    }

    if (targetIndex == oldIndex) return;

    FocusScope.of(context).unfocus();

    final movedId = _questionIds[oldIndex];
    final newList = List<String>.from(_questionIds);
    newList.removeAt(oldIndex);
    newList.insert(targetIndex, movedId);

    // Optimistic Update
    setState(() {
      _questionIds = newList;
    });

    try {
      await _teacherService.updateQuestionOrder(widget.curationId, newList);
      _showSafeSnackBar("Reordered successfully");
    } catch (e) {
      _showSafeSnackBar("Error saving order: $e");
    }
  }

  // 4. RANDOMIZE LOGIC (New Feature)
  Future<void> _promptAndRandomize() async {
    if (_questionIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Randomize Order"),
        content: const Text(
            "Are you sure you want to shuffle all questions? This cannot be undone."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Shuffle"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Shuffle
    final shuffledList = List<String>.from(_questionIds)..shuffle();

    // Optimistic Update
    setState(() {
      _questionIds = shuffledList;
    });

    // Save
    try {
      await _teacherService.updateQuestionOrder(widget.curationId, shuffledList);
      _showSafeSnackBar("Questions shuffled successfully!");
    } catch (e) {
      _showSafeSnackBar("Error shuffling: $e");
    }
  }

  void _showSafeSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.yellowAccent,
          tabs: const [
            Tab(icon: Icon(Icons.edit_note), text: "Manage Content"),
            Tab(icon: Icon(Icons.bar_chart), text: "Performance"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManageContentTab(),
          _buildPerformanceTab(),
        ],
      ),
    );
  }

  Widget _buildManageContentTab() {
    if (!_isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_questionIds.isEmpty) {
      return const Center(child: Text("No questions in this curation."));
    }

    return Column(
      children: [
        // --- RANDOMIZE BUTTON HEADER ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${_questionIds.length} Questions",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
              ElevatedButton.icon(
                onPressed: _promptAndRandomize,
                icon: const Icon(Icons.shuffle, size: 18),
                label: const Text("Randomize Order"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),

        // --- LIST VIEW ---
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 100,
            ),
            itemCount: _questionIds.length,
            itemBuilder: (context, index) {
              final qId = _questionIds[index];
              final question = _questionCache[qId];

              return QuestionReorderTile(
                key: ValueKey(qId),
                index: index,
                questionId: qId,
                questionData: question,
                onReorder: (newPos) => _handleReorder(index, newPos),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceTab() {
    return const Center(child: Text("Performance metrics coming soon"));
  }
}

// --------------------------------------------------------------------------
// ISOLATED TILE WIDGET (Kept same as before)
// --------------------------------------------------------------------------

class QuestionReorderTile extends StatefulWidget {
  final int index;
  final String questionId;
  final Question? questionData;
  final Function(String) onReorder;

  const QuestionReorderTile({
    Key? key,
    required this.index,
    required this.questionId,
    required this.questionData,
    required this.onReorder,
  }) : super(key: key);

  @override
  State<QuestionReorderTile> createState() => _QuestionReorderTileState();
}

class _QuestionReorderTileState extends State<QuestionReorderTile>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _posController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _posController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Control Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                // Badge
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.deepPurple,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "${widget.index + 1}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Position",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                ),

                const Spacer(),

                // Input Field
                SizedBox(
                  width: 50,
                  height: 35,
                  child: TextField(
                    controller: _posController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: "#",
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onSubmitted: (val) {
                      if (val.isNotEmpty) {
                        widget.onReorder(val);
                        _posController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Move Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    minimumSize: const Size(0, 35),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    if (_posController.text.isNotEmpty) {
                      widget.onReorder(_posController.text);
                      _posController.clear();
                    }
                  },
                  child: const Text("Move"),
                ),
              ],
            ),
          ),

          // Question Preview
          if (widget.questionData != null)
            QuestionPreviewCard(
              question: widget.questionData!,
              isExpanded: true,
            )
          else
            Container(
              height: 150,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 10),
                  Text("Loading QID: ${widget.questionId}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}