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

class _TeacherFilterScreenState extends State<TeacherFilterScreen> with SingleTickerProviderStateMixin {
  final TeacherService _teacherService = TeacherService();
  late TabController _tabController;

  // --- Data & Filters ---
  bool _isLoadingSyllabus = true;
  Map<String, dynamic>? _syllabusData;
  List<String> _subjects = [];

  String? _selectedSubject;
  final Set<String> _selectedChapters = {};
  final Set<String> _selectedTopics = {};
  String? _smartFilter;

  // --- Search & Pagination State ---
  bool _isSearching = false;
  bool _isLoadingMore = false;
  List<Question> _searchResults = [];
  DocumentSnapshot? _lastDocument; // Pagination Cursor
  bool _hasMoreData = true;

  // --- Selection State (The Cart) ---
  // We use a Map to keep the full object, allowing us to display them in the 'Selected' tab
  // even if they disappear from the search results after a new fetch.
  final Map<String, Question> _selectedQuestions = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchSyllabus();
    if (widget.audienceType == 'Particular Student') {
      _smartFilter = 'New Questions';
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  // --- ACTIONS ---

  Future<void> _performSearch({bool isLoadMore = false}) async {
    if (_selectedSubject == null && widget.audienceType != 'Particular Student') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a Subject")));
      return;
    }

    setState(() {
      if (isLoadMore) {
        _isLoadingMore = true;
      } else {
        _isSearching = true;
        _searchResults = [];
        _lastDocument = null;
        _hasMoreData = true;
      }
    });

    try {
      final paginatedResult = await _teacherService.fetchQuestionsPaged(
        audienceType: widget.audienceType,
        studentId: widget.studentId,
        smartFilter: _smartFilter,
        subject: _selectedSubject,
        chapterIds: _selectedChapters.isNotEmpty ? _selectedChapters.toList() : null,
        topicIds: _selectedTopics.isNotEmpty ? _selectedTopics.toList() : null,
        limit: 20, // Strict limit of 20
        startAfter: _lastDocument,
      );

      final newQuestions = paginatedResult.questions;

      // Randomize Client-Side
      newQuestions.shuffle();

      setState(() {
        if (isLoadMore) {
          _searchResults.addAll(newQuestions);
        } else {
          _searchResults = newQuestions;
        }

        _lastDocument = paginatedResult.lastDoc;

        // If we got fewer than limit, we likely reached the end
        if (newQuestions.length < 20) {
          _hasMoreData = false;
        }
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() {
        _isSearching = false;
        _isLoadingMore = false;
      });
    }
  }

  void _toggleSelection(Question q) {
    setState(() {
      if (_selectedQuestions.containsKey(q.id)) {
        _selectedQuestions.remove(q.id);
      } else {
        _selectedQuestions[q.id] = q;
      }
    });
  }

  Future<void> _onAssign() async {
    if (_selectedQuestions.isEmpty) return;
    final teacher = FirebaseAuth.instance.currentUser;
    if (teacher == null) return;

    final titleCtrl = TextEditingController(text: "Homework - ${DateTime.now().toString().split(' ')[0]}");
    final defaultTime = _selectedQuestions.length * 2;
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
                  Text("Assigning ${_selectedQuestions.length} questions."),
                  const SizedBox(height: 15),
                  TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: "Assignment Title", border: OutlineInputBorder())
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: timeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Time Limit (Minutes)", border: OutlineInputBorder(), suffixText: "min"),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      SizedBox(
                        height: 24, width: 24,
                        child: Checkbox(
                          value: isSingleAttempt,
                          onChanged: (val) => setDialogState(() => isSingleAttempt = val ?? false),
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

      int? customTime = int.tryParse(timeCtrl.text.trim());
      await _teacherService.assignQuestionsToStudent(
        studentId: widget.studentId!,
        questions: _selectedQuestions.values.toList(),
        teacherUid: teacher.uid,
        targetAudience: widget.audienceType,
        assignmentTitle: titleCtrl.text,
        onlySingleAttempt: isSingleAttempt,
        timeLimitMinutes: customTime,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Assigned Successfully!")));
        Navigator.pop(context); // Close screen
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // --- UI HELPERS ---
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

  void _showMultiSelectDialog({required String title, required List<String> items, required Set<String> selectedItems, required Function(Set<String>) onConfirm}) {
    showDialog(
      context: context,
      builder: (context) {
        Set<String> localSelected = Set.from(selectedItems);
        String searchQuery = "";
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredItems = items.where((item) => item.toLowerCase().contains(searchQuery.toLowerCase())).toList();
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
                      decoration: const InputDecoration(hintText: "Search...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
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
                            onChanged: (val) => setDialogState(() { val == true ? localSelected.add(item) : localSelected.remove(item); }),
                          );
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${localSelected.length} Selected", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        ElevatedButton(
                          onPressed: () { onConfirm(localSelected); Navigator.pop(context); },
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

  // --- BUILD METHOD ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Filter & Search"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.yellowAccent,
          tabs: [
            const Tab(text: "Search Results"),
            Tab(text: "Selected (${_selectedQuestions.length})"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: FILTERS & RESULTS
          _buildSearchTab(),

          // TAB 2: SELECTED LIST
          _buildSelectedTab(),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- FILTERS SECTION ---
          _buildFilters(),

          const Divider(height: 30),

          // --- SEARCH BUTTON ---
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text("Search Questions"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)
              ),
              onPressed: () => _performSearch(isLoadMore: false),
            ),
          ),

          const SizedBox(height: 20),

          // --- RESULTS LIST ---
          if (_isSearching)
            const Center(child: CircularProgressIndicator())
          else if (_searchResults.isEmpty && _lastDocument == null) // Initial empty state
            const Center(child: Text("Use filters to find questions.", style: TextStyle(color: Colors.grey)))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Showing ${_searchResults.length} Results", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final q = _searchResults[index];
                    final isSelected = _selectedQuestions.containsKey(q.id);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (val) => _toggleSelection(q),
                          ),
                        ),
                        Expanded(child: QuestionPreviewCard(question: q)),
                      ],
                    );
                  },
                ),

                // --- LOAD MORE BUTTON ---
                if (_hasMoreData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: _isLoadingMore
                          ? const CircularProgressIndicator()
                          : FloatingActionButton.extended(
                        heroTag: "loadMore",
                        onPressed: () => _performSearch(isLoadMore: true),
                        label: const Text("Load Next 20"),
                        icon: const Icon(Icons.refresh),
                        backgroundColor: Colors.deepPurple.shade100,
                        foregroundColor: Colors.deepPurple,
                      ),
                    ),
                  ),

                if (!_hasMoreData && _searchResults.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: Text("No more questions matching criteria.", style: TextStyle(color: Colors.grey))),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedTab() {
    if (_selectedQuestions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 60, color: Colors.grey),
            SizedBox(height: 10),
            Text("No questions selected yet.", style: TextStyle(color: Colors.grey)),
            Text("Go to Search Results to add questions.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    final list = _selectedQuestions.values.toList();

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Space for fab
          itemCount: list.length,
          itemBuilder: (context, index) {
            final q = list[index];
            return Stack(
              children: [
                QuestionPreviewCard(question: q),
                Positioned(
                  top: 0, right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _toggleSelection(q),
                  ),
                ),
              ],
            );
          },
        ),
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
            child: Text("Assign ${list.length} Questions", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    // Reusing your existing efficient filter UI logic
    final inputDecoration = InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15));

    return Column(
      children: [
        if (_isLoadingSyllabus) const LinearProgressIndicator(),

        // Subject Dropdown
        DropdownButtonFormField<String>(
          value: _selectedSubject,
          hint: const Text("Select Subject"),
          items: _subjects.map((s) => DropdownMenuItem(value: s, child: Text(_formatName(s)))).toList(),
          onChanged: (val) => setState(() { _selectedSubject = val; _selectedChapters.clear(); _selectedTopics.clear(); }),
          decoration: inputDecoration.copyWith(labelText: "Subject"),
        ),
        const SizedBox(height: 15),

        // Chapter Multi-Select
        InkWell(
          onTap: _selectedSubject == null ? null : () => _showMultiSelectDialog(
            title: "Select Chapters",
            items: _availableChapters,
            selectedItems: _selectedChapters,
            onConfirm: (newSet) => setState(() { _selectedChapters.clear(); _selectedChapters.addAll(newSet); _selectedTopics.clear(); }),
          ),
          child: InputDecorator(
            decoration: inputDecoration.copyWith(labelText: "Chapters", enabled: _selectedSubject != null, suffixIcon: const Icon(Icons.arrow_drop_down)),
            child: Text(_selectedChapters.isEmpty ? "All Chapters" : "${_selectedChapters.length} Selected", maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(height: 15),

        // Topic Multi-Select
        InkWell(
          onTap: _selectedChapters.isEmpty ? null : () => _showMultiSelectDialog(
            title: "Select Topics",
            items: _availableTopics,
            selectedItems: _selectedTopics,
            onConfirm: (newSet) => setState(() { _selectedTopics.clear(); _selectedTopics.addAll(newSet); }),
          ),
          child: InputDecorator(
            decoration: inputDecoration.copyWith(labelText: "Topics", enabled: _selectedChapters.isNotEmpty, suffixIcon: const Icon(Icons.arrow_drop_down)),
            child: Text(_selectedTopics.isEmpty ? "All Topics" : "${_selectedTopics.length} Selected", maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),

        // Smart Filters
        if (widget.audienceType == 'Particular Student') ...[
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: _smartFilter,
            items: ['New Questions', 'Incorrect', 'Unattempted', 'Skipped', 'Correct'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (val) => setState(() => _smartFilter = val),
            decoration: inputDecoration.copyWith(labelText: "Student Status"),
          ),
        ],
      ],
    );
  }
}