// lib/features/teacher/screens/teacher_filter_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/common/widgets/question_preview_card.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/services/teacher_service.dart';

class TeacherFilterScreen extends StatefulWidget {
  final String audienceType;
  final int? studentId;

  const TeacherFilterScreen({
    super.key,
    required this.audienceType,
    this.studentId,
  });

  @override
  State<TeacherFilterScreen> createState() => _TeacherFilterScreenState();
}

class _TeacherFilterScreenState extends State<TeacherFilterScreen> {
  final TeacherService _teacherService = TeacherService();

  // Data
  bool _isLoadingSyllabus = true;
  Map<String, dynamic>? _syllabusData;
  List<String> _subjects = [];

  // Selection
  String? _selectedSubject;
  final Set<String> _selectedChapters = {};
  final Set<String> _selectedTopics = {};
  String? _smartFilter;

  // Search
  bool _isSearching = false;
  List<Question>? _results;
  final Set<String> _selectedQuestionIds = {};

  @override
  void initState() {
    super.initState();
    _fetchSyllabus();
    if (widget.audienceType == 'Particular Student') {
      _smartFilter = 'New Questions';
    }
  }

  Future<void> _fetchSyllabus() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('static_data').doc('syllabus').get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _syllabusData = data['subjects'];
          _subjects = _syllabusData?.keys.toList() ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error loading syllabus: $e");
    } finally {
      if (mounted) setState(() => _isLoadingSyllabus = false);
    }
  }

  // --- HELPERS ---
  List<String> get _availableChapters {
    if (_selectedSubject == null || _syllabusData == null) return [];
    final chaptersMap = _syllabusData![_selectedSubject]['chapters'] as Map<String, dynamic>?;
    return chaptersMap?.keys.toList() ?? [];
  }

  List<String> get _availableTopics {
    if (_selectedSubject == null || _selectedChapters.isEmpty || _syllabusData == null) return [];
    List<String> topics = [];
    final chaptersMap = _syllabusData![_selectedSubject]['chapters'];

    for (var chapId in _selectedChapters) {
      final chapData = chaptersMap[chapId];
      if (chapData != null && chapData['topics'] != null) {
        final topicMap = chapData['topics'] as Map<String, dynamic>;
        topics.addAll(topicMap.keys);
      }
    }
    return topics;
  }

  String _formatName(String id) {
    return id.split('_').map((str) => str.isNotEmpty ? str[0].toUpperCase() + str.substring(1) : '').join(' ');
  }

  String _getSelectionSummary(Set<String> selected) {
    if (selected.isEmpty) return "Select Options";
    if (selected.length == 1) return _formatName(selected.first);
    if (selected.length == 2) return "${_formatName(selected.first)}, ${_formatName(selected.last)}";
    return "${_formatName(selected.first)} (+${selected.length - 1} more)";
  }

  // --- ACTIONS ---

  Future<void> _onSearch() async {
    setState(() {
      _isSearching = true;
      _results = null;
      _selectedQuestionIds.clear();
    });

    try {
      final questions = await _teacherService.fetchQuestions(
        audienceType: widget.audienceType,
        studentId: widget.studentId,
        smartFilter: _smartFilter,
        subject: _selectedSubject,
        chapterIds: _selectedChapters.isNotEmpty ? _selectedChapters.toList() : null,
        topicIds: _selectedTopics.isNotEmpty ? _selectedTopics.toList() : null,
      );
      setState(() => _results = questions);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _onAssign() async {
    if (_selectedQuestionIds.isEmpty) return;
    final teacher = FirebaseAuth.instance.currentUser;
    if (teacher == null) return;

    final titleCtrl = TextEditingController(text: "Homework - ${DateTime.now().toString().split(' ')[0]}");

    // Default time: 2 mins per question
    final defaultTime = _selectedQuestionIds.length * 2;
    final timeCtrl = TextEditingController(text: defaultTime.toString());

    bool isSingleAttempt = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Confirm Assignment"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Assigning ${_selectedQuestionIds.length} questions."),
                  const SizedBox(height: 15),

                  // 1. Title Input
                  TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: "Assignment Title",
                        border: OutlineInputBorder(),
                      )
                  ),
                  const SizedBox(height: 15),

                  // 2. Time Limit Input (NEW)
                  TextField(
                    controller: timeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Time Limit (Minutes)",
                      border: OutlineInputBorder(),
                      suffixText: "min",
                    ),
                  ),
                  const SizedBox(height: 15),

                  // 3. Strict Mode Checkbox
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: isSingleAttempt,
                          onChanged: (val) {
                            setDialogState(() => isSingleAttempt = val ?? false);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(child: Text("Strict Mode (Single Attempt)")),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Assign")),
            ],
          );
        },
      ),
    );

    if (confirm != true) return;

    try {
      if (widget.audienceType != 'Particular Student') {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Batch assignment coming soon!")));
        return;
      }

      // Filter the actual question objects
      final selectedQuestions = _results!.where((q) => _selectedQuestionIds.contains(q.id)).toList();

      // Parse time limit
      int? customTime = int.tryParse(timeCtrl.text.trim());

      await _teacherService.assignQuestionsToStudent(
        studentId: widget.studentId!,
        questions: selectedQuestions,
        teacherUid: teacher.uid,
        targetAudience: widget.audienceType,
        assignmentTitle: titleCtrl.text,
        onlySingleAttempt: isSingleAttempt,
        timeLimitMinutes: customTime, // <--- PASSED TO SERVICE
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Assigned Successfully!")));

        // --- FIX IS HERE ---
        // We only pop ONCE. This closes the Filter Screen and returns to the Dashboard.
        // The previous code popped twice, which closed the Dashboard too.
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // --- CUSTOM MULTI-SELECT DIALOG ---
  void _showMultiSelectDialog({
    required String title,
    required List<String> items,
    required Set<String> selectedItems,
    required Function(Set<String>) onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        Set<String> localSelected = Set.from(selectedItems);
        String searchQuery = "";

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredItems = items.where((item) =>
                item.toLowerCase().contains(searchQuery.toLowerCase())
            ).toList();

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 10),

                    TextField(
                      decoration: const InputDecoration(
                        hintText: "Search...",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) => setDialogState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 10),

                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final isSelected = localSelected.contains(item);
                          return CheckboxListTile(
                            title: Text(_formatName(item)),
                            value: isSelected,
                            activeColor: Colors.deepPurple,
                            onChanged: (val) {
                              setDialogState(() {
                                val == true ? localSelected.add(item) : localSelected.remove(item);
                              });
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${localSelected.length} Selected", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        ElevatedButton(
                          onPressed: () {
                            onConfirm(localSelected);
                            Navigator.pop(context);
                          },
                          child: const Text("Done"),
                        )
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
    );

    return Scaffold(
      appBar: AppBar(title: const Text("Filter & Search"), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Syllabus Filters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 15),

                if (_isLoadingSyllabus)
                  const Center(child: LinearProgressIndicator())
                else ...[
                  // 1. SUBJECT
                  DropdownButtonFormField<String>(
                    value: _selectedSubject,
                    hint: const Text("Select Subject"),
                    items: _subjects.map((s) => DropdownMenuItem(value: s, child: Text(_formatName(s)))).toList(),
                    onChanged: (val) => setState(() {
                      _selectedSubject = val;
                      _selectedChapters.clear();
                      _selectedTopics.clear();
                    }),
                    decoration: inputDecoration.copyWith(labelText: "Subject"),
                  ),
                  const SizedBox(height: 15),

                  // 2. CHAPTERS
                  InkWell(
                    onTap: _selectedSubject == null ? null : () {
                      _showMultiSelectDialog(
                        title: "Select Chapters",
                        items: _availableChapters,
                        selectedItems: _selectedChapters,
                        onConfirm: (newSet) => setState(() {
                          _selectedChapters.clear();
                          _selectedChapters.addAll(newSet);
                          _selectedTopics.clear();
                        }),
                      );
                    },
                    child: InputDecorator(
                      decoration: inputDecoration.copyWith(
                        labelText: "Chapters",
                        enabled: _selectedSubject != null,
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        _getSelectionSummary(_selectedChapters),
                        style: TextStyle(color: _selectedSubject == null ? Colors.grey : Colors.black),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // 3. TOPICS
                  InkWell(
                    onTap: _selectedChapters.isEmpty ? null : () {
                      _showMultiSelectDialog(
                        title: "Select Topics",
                        items: _availableTopics,
                        selectedItems: _selectedTopics,
                        onConfirm: (newSet) => setState(() {
                          _selectedTopics.clear();
                          _selectedTopics.addAll(newSet);
                        }),
                      );
                    },
                    child: InputDecorator(
                      decoration: inputDecoration.copyWith(
                        labelText: "Topics",
                        enabled: _selectedChapters.isNotEmpty,
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        _getSelectionSummary(_selectedTopics),
                        style: TextStyle(color: _selectedChapters.isEmpty ? Colors.grey : Colors.black),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // 4. SMART FILTERS
                if (widget.audienceType == 'Particular Student') ...[
                  const Text("Smart Filters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _smartFilter,
                    items: ['New Questions', 'Incorrect', 'Unattempted', 'Skipped', 'Correct']
                        .map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (val) => setState(() => _smartFilter = val),
                    decoration: inputDecoration.copyWith(labelText: "Status"),
                  ),
                ],

                const SizedBox(height: 30),

                // 5. SEARCH BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text("Search Questions"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16)
                    ),
                    onPressed: _onSearch,
                  ),
                ),

                const Divider(height: 40),

                // 6. RESULTS
                if (_isSearching)
                  const Center(child: CircularProgressIndicator())
                else if (_results != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Found ${_results!.length} Questions", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 10),
                      if (_results!.isEmpty) const Text("No questions found."),

                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _results!.length,
                        itemBuilder: (context, index) {
                          final q = _results![index];
                          final isSelected = _selectedQuestionIds.contains(q.id);

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (val) => setState(() {
                                    val == true ? _selectedQuestionIds.add(q.id) : _selectedQuestionIds.remove(q.id);
                                  }),
                                ),
                              ),
                              Expanded(
                                child: QuestionPreviewCard(question: q),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),

          if (_selectedQuestionIds.isNotEmpty)
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 5,
                ),
                onPressed: _onAssign,
                child: Text("Assign ${_selectedQuestionIds.length} Questions", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}