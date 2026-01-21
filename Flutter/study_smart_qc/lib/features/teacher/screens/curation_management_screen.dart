import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For clipboard
import 'package:intl/intl.dart';

// MODELS
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/services/teacher_service.dart';

// WIDGETS
import 'package:study_smart_qc/features/common/widgets/teacher_question_preview_card.dart';

class CurationManagementScreen extends StatefulWidget {
  final String curationId; // This is the Firestore Document ID
  final String title;

  const CurationManagementScreen({
    super.key,
    required this.curationId,
    required this.title,
  });

  @override
  State<CurationManagementScreen> createState() =>
      _CurationManagementScreenState();
}

class _CurationManagementScreenState extends State<CurationManagementScreen> {
  final TeacherService _teacherService = TeacherService();

  // --- DATA STATE ---
  StreamSubscription<DocumentSnapshot>? _curationSubscription;
  List<String> _questionIds = []; // Stores Business IDs (e.g., "9338")
  String _assignmentCode = ""; // Stores the display code
  bool _isLoaded = false;

  // --- METADATA STATE ---
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _timeLimitController = TextEditingController();
  DateTime? _deadline;
  bool _isSaving = false;

  // --- QUESTION CACHE ---
  final Map<String, Question> _questionCache = {};
  final Set<String> _attemptedFetches = {};
  final Set<String> _notFoundIds = {};
  bool _isLoadingQuestions = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.title;
    _setupFirestoreListener();
  }

  @override
  void dispose() {
    _curationSubscription?.cancel();
    _titleController.dispose();
    _timeLimitController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // 1. DATA LOADING & LISTENER
  // ===========================================================================

  void _setupFirestoreListener() {
    _curationSubscription = FirebaseFirestore.instance
        .collection('questions_curation')
        .doc(widget.curationId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;

        // 1. Update List
        final rawIds = List<String>.from(data['questionIds'] ?? []);
        final newIds = rawIds.where((id) => id.isNotEmpty).toList();

        // 2. Get Assignment Code
        final code = data['assignmentCode'] ?? data['assignment_code'] ?? '';

        // 3. Update Metadata (First load only)
        if (!_isLoaded) {
          _titleController.text = data['title'] ?? '';
          if (data['timeLimitMinutes'] != null) {
            _timeLimitController.text = data['timeLimitMinutes'].toString();
          }
          if (data['deadline'] != null) {
            _deadline = (data['deadline'] as Timestamp).toDate();
          }
        }

        setState(() {
          _questionIds = newIds;
          _assignmentCode = code;
          _isLoaded = true;
        });

        // 4. Trigger Question Fetch
        _ensureQuestionsLoaded(newIds);
      }
    }, onError: (e) {
      debugPrint("Error listening to curation: $e");
    });
  }

  Future<void> _ensureQuestionsLoaded(List<String> questionIds) async {
    final idsToFetch = questionIds.where((id) =>
    !_questionCache.containsKey(id) &&
        !_attemptedFetches.contains(id) &&
        !_notFoundIds.contains(id)
    ).toList();

    if (idsToFetch.isEmpty) return;
    if (_isLoadingQuestions) return;

    setState(() => _isLoadingQuestions = true);
    _attemptedFetches.addAll(idsToFetch);

    try {
      const int batchSize = 10;
      for (var i = 0; i < idsToFetch.length; i += batchSize) {
        final end = (i + batchSize < idsToFetch.length) ? i + batchSize : idsToFetch.length;
        final batch = idsToFetch.sublist(i, end);

        final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
            .collection('questions')
            .where('question_id', whereIn: batch)
            .get();

        if (mounted) {
          setState(() {
            final foundIds = <String>{};

            // A. Process found docs
            for (var doc in querySnapshot.docs) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                // Get the Business ID (e.g. "9338") to map it correctly
                final String qIdField = data['question_id']?.toString() ?? '';

                if (qIdField.isNotEmpty) {
                  foundIds.add(qIdField);

                  // --- FIX: Pass qIdField as the ID so the UI shows "QID: 9338" ---
                  // If we passed doc.id, it would show "QID: Ktc..."
                  final q = Question.fromMap(data, qIdField);

                  _questionCache[qIdField] = q;
                }
              } catch (e) {
                debugPrint("Error parsing question ${doc.id}: $e");
              }
            }

            // B. Identify missing
            for (var id in batch) {
              if (!foundIds.contains(id)) {
                _notFoundIds.add(id);
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching questions batch: $e");
    } finally {
      if (mounted) setState(() => _isLoadingQuestions = false);
    }
  }

  // ===========================================================================
  // 2. ACTIONS
  // ===========================================================================

  Future<void> _saveMetadata() async {
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      int? timeLimit = int.tryParse(_timeLimitController.text.trim());

      await FirebaseFirestore.instance
          .collection('questions_curation')
          .doc(widget.curationId)
          .update({
        'title': _titleController.text.trim(),
        'deadline': _deadline != null ? Timestamp.fromDate(_deadline!) : null,
        'timeLimitMinutes': timeLimit,
      });

      _showSafeSnackBar("Updated successfully!");
    } catch (e) {
      _showSafeSnackBar("Error updating: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteCuration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Curation"),
        content: const Text("Are you sure? This will permanently delete this assignment."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete Forever"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('questions_curation').doc(widget.curationId).delete();
        if (mounted) Navigator.pop(context);
      } catch (e) {
        _showSafeSnackBar("Error deleting: $e");
      }
    }
  }

  Future<void> _removeQuestion(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove Question"),
        content: const Text("Remove this question from the assignment?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final newList = List<String>.from(_questionIds);
    newList.removeAt(index);
    setState(() => _questionIds = newList);

    try {
      await _teacherService.updateQuestionOrder(widget.curationId, newList);
    } catch (e) {
      _showSafeSnackBar("Error removing question: $e");
    }
  }

  Future<void> _handleReorder(int oldIndex, String newIndexStr) async {
    int? newIndex = int.tryParse(newIndexStr);
    if (newIndex == null) return;

    int targetIndex = newIndex - 1;
    if (targetIndex < 0 || targetIndex >= _questionIds.length) {
      _showSafeSnackBar("Invalid Position (1-${_questionIds.length})");
      return;
    }
    if (targetIndex == oldIndex) return;

    FocusScope.of(context).unfocus();
    final movedId = _questionIds[oldIndex];
    final newList = List<String>.from(_questionIds);
    newList.removeAt(oldIndex);
    newList.insert(targetIndex, movedId);

    setState(() => _questionIds = newList);
    await _teacherService.updateQuestionOrder(widget.curationId, newList);
  }

  Future<void> _promptAndRandomize() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Randomize Order"),
        content: const Text("Shuffle all questions?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Shuffle"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final shuffled = List<String>.from(_questionIds)..shuffle();
      setState(() => _questionIds = shuffled);
      await _teacherService.updateQuestionOrder(widget.curationId, shuffled);
    }
  }

  // ===========================================================================
  // UI HELPERS
  // ===========================================================================

  void _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline ?? now),
    );
    if (time == null) return;

    setState(() {
      _deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _showSafeSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ===========================================================================
  // MAIN BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // --- FIX: Display Code inline in Title ---
        title: GestureDetector(
          onTap: () {
            if (_assignmentCode.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: _assignmentCode));
              _showSafeSnackBar("Code copied!");
            }
          },
          child: Text(
            "Manage Assignment ${_assignmentCode.isNotEmpty ? '($_assignmentCode)' : ''}",
            style: const TextStyle(fontSize: 18),
          ),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: "Delete Assignment",
            onPressed: _deleteCuration,
          )
        ],
      ),
      body: !_isLoaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildSettingsSection(),
          const Divider(height: 1, thickness: 1),
          _buildListHeader(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: _questionIds.length,
              itemBuilder: (context, index) {
                final qId = _questionIds[index];
                final question = _questionCache[qId];
                final isNotFound = _notFoundIds.contains(qId);

                return QuestionReorderTile(
                  key: ValueKey(qId),
                  index: index,
                  questionId: qId,
                  questionData: question,
                  isNotFound: isNotFound,
                  onReorder: (newPos) => _handleReorder(index, newPos),
                  onRemove: () => _removeQuestion(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: "Assignment Title",
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: _pickDeadline,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: "Deadline",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(
                      _deadline == null
                          ? "Set Date"
                          : DateFormat('MMM d, h:mm a').format(_deadline!),
                      style: TextStyle(
                        color: _deadline == null ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _timeLimitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Time (min)",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixText: "m",
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveMetadata,
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(_isSaving ? "Saving..." : "Update"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Questions (${_questionIds.length})",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          TextButton.icon(
            onPressed: _promptAndRandomize,
            icon: const Icon(Icons.shuffle, size: 16),
            label: const Text("Shuffle Order"),
          )
        ],
      ),
    );
  }
}

class QuestionReorderTile extends StatefulWidget {
  final int index;
  final String questionId;
  final Question? questionData;
  final bool isNotFound;
  final Function(String) onReorder;
  final VoidCallback onRemove;

  const QuestionReorderTile({
    super.key,
    required this.index,
    required this.questionId,
    required this.questionData,
    this.isNotFound = false,
    required this.onReorder,
    required this.onRemove,
  });

  @override
  State<QuestionReorderTile> createState() => _QuestionReorderTileState();
}

class _QuestionReorderTileState extends State<QuestionReorderTile> {
  final TextEditingController _posController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.deepPurple,
                  child: Text(
                    "${widget.index + 1}",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  height: 30,
                  child: TextField(
                    controller: _posController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: "#",
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onSubmitted: (val) {
                      if (val.isNotEmpty) widget.onReorder(val);
                      _posController.clear();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    if (_posController.text.isNotEmpty) {
                      widget.onReorder(_posController.text);
                      _posController.clear();
                    }
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(40, 30),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text("Move", style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  tooltip: "Remove from list",
                  onPressed: widget.onRemove,
                )
              ],
            ),
          ),
          if (widget.questionData != null)
            Padding(
              padding: const EdgeInsets.all(0),
              child: QuestionPreviewCard(
                question: widget.questionData!,
              ),
            )
          else if (widget.isNotFound)
            Container(
              height: 80,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    "Question ID not found or deleted.\nID: ${widget.questionId}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 100,
              alignment: Alignment.center,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(height: 8),
                  Text("Loading details...", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}