import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/features/common/widgets/question_preview_card.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/services/teacher_service.dart';


// IMPORTANT: Ensure this import exists to navigate to the edit screen
import 'package:study_smart_qc/features/teacher/screens/modify_question_screen.dart';

// --- Helper Model to store parsed Syllabus Data ---
class SyllabusChapter {
  final String id;
  final String name;
  final Map<String, String> topics; // key: id, value: display name

  SyllabusChapter({required this.id, required this.name, required this.topics});
}

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

class _TeacherFilterScreenState extends State<TeacherFilterScreen>
    with SingleTickerProviderStateMixin {
  final TeacherService _teacherService = TeacherService();
  late TabController _tabController;

  // --- 1. DYNAMIC DATA STATE ---
  bool _isLoadingFilters = true;
  List<String> _examsList = [];
  List<String> _subjectsList = [];

  // Cache: Subject (lowercase) -> List of parsed Chapters
  final Map<String, List<SyllabusChapter>> _syllabusCache = {};

  // --- 2. FILTER STATE ---
  String? _selectedExam;
  String? _selectedSubject;
  final Set<String> _selectedChapters = {};
  final Set<String> _selectedTopics = {};
  bool _isPyqOnly = false;

  // --- 3. SEARCH STATE ---
  bool _isSearching = false;
  List<Question> _searchResults = [];
  int _totalMatchCount = 0;

  // --- 4. SELECTION STATE (The Cart) ---
  final Map<String, Question> _selectedQuestions = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchFilterData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- DATA FETCHING & PARSING ---
  Future<void> _fetchFilterData() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final optionsDoc = await firestore.collection('static_data').doc('option_sets').get();
      if (optionsDoc.exists) {
        final data = optionsDoc.data()!;
        _examsList = List<String>.from(data['exams_list'] ?? []);
        _subjectsList = List<String>.from(data['subjects_list'] ?? []);
      }

      final syllabusDoc = await firestore.collection('static_data').doc('syllabus').get();
      if (syllabusDoc.exists) {
        final data = syllabusDoc.data()!;
        if (data.containsKey('subjects') && data['subjects'] is Map) {
          final subjectsMap = data['subjects'] as Map<String, dynamic>;
          subjectsMap.forEach((subjectKey, subjectVal) {
            if (subjectVal is Map && subjectVal.containsKey('chapters')) {
              final chaptersMap = subjectVal['chapters'] as Map<String, dynamic>;
              List<SyllabusChapter> parsedChapters = [];
              chaptersMap.forEach((chapKey, chapVal) {
                if (chapVal is Map) {
                  String name = chapVal['name'] ?? chapKey;
                  Map<String, String> topics = {};
                  if (chapVal.containsKey('topics') && chapVal['topics'] is Map) {
                    final topicRaw = chapVal['topics'] as Map<String, dynamic>;
                    topicRaw.forEach((tKey, tVal) {
                      topics[tKey] = tVal.toString();
                    });
                  }
                  parsedChapters.add(SyllabusChapter(id: chapKey, name: name, topics: topics));
                }
              });
              parsedChapters.sort((a, b) => a.name.compareTo(b.name));
              _syllabusCache[subjectKey.toLowerCase()] = parsedChapters;
            }
          });
        }
      }
      if (mounted) setState(() { _isLoadingFilters = false; });
    } catch (e) {
      debugPrint("Error loading filters: $e");
      if (mounted) setState(() { _isLoadingFilters = false; });
    }
  }

  // --- CASCADING GETTERS ---
  String _normalizeSubject(String? subject) {
    if (subject == null) return "";
    return subject.toLowerCase().trim();
  }

  List<String> get _currentChaptersList {
    if (_selectedSubject == null) return [];
    String key = _normalizeSubject(_selectedSubject);
    final chapters = _syllabusCache[key] ?? [];
    return chapters.map((c) => c.name).toList();
  }

  List<String> get _currentTopicsList {
    if (_selectedChapters.isEmpty || _selectedSubject == null) return [];
    String key = _normalizeSubject(_selectedSubject);
    final allChapters = _syllabusCache[key] ?? [];
    final selectedChaps = allChapters.where((c) => _selectedChapters.contains(c.name));
    List<String> topics = [];
    for (var chap in selectedChaps) {
      topics.addAll(chap.topics.values);
    }
    return topics.toSet().toList()..sort();
  }

  void _resetFiltersBelow(String level) {
    setState(() {
      if (level == 'Exam') {
        _selectedSubject = null;
        _selectedChapters.clear();
        _selectedTopics.clear();
      } else if (level == 'Subject') {
        _selectedChapters.clear();
        _selectedTopics.clear();
      } else if (level == 'Chapter') {
        _selectedTopics.clear();
      }
    });
  }

  // --- NAVIGATION LOGIC (THE FIX) ---

  // 1. Helper to generate tree for ANY subject (not just the currently filtered one)
  Map<String, dynamic> _buildTreeForSubject(String subjectName) {
    String key = _normalizeSubject(subjectName);
    // If we don't have this subject in cache, return empty map
    if (!_syllabusCache.containsKey(key)) return {};

    final chapters = _syllabusCache[key] ?? [];
    Map<String, dynamic> tree = {};

    for (var chap in chapters) {
      Map<String, dynamic> topicMap = {};
      // Flatten topics (ModifyQuestionScreen expects Map<Topic, List<SubTopic>>)
      for (var topicName in chap.topics.values) {
        topicMap[topicName] = <String>[];
      }
      tree[chap.name] = topicMap;
    }
    return tree;
  }

// 2. The function that handles the "Edit" click
  void _navigateToEdit(Question q) {
    // A. Generate the specific syllabus tree for THIS question's subject
    final Map<String, dynamic> specificTree = _buildTreeForSubject(q.subject);

    // B. Reconstruct the raw Map data from the Question object
    final Map<String, dynamic> manualDataMap = {
      'id': q.id,
      'customId': q.customId,

      // --- EXAM & SUBJECT ---
      'Exam': q.exam,
      'Subject': q.subject,
      'Chapter': q.chapter,
      'Topic': q.topic,
      'TopicL2': q.topicL2,

      // --- CRITICAL FIX: QUESTION TYPE ---
      // Pass the Enum directly. We pass it with TWO keys to be safe
      // because your Model uses 'Question type' but the Screen might use 'QuestionType'.
      'QuestionType': q.type,
      'Question type': q.type,

      // --- IMAGES ---
      // We map to 'image_url' because that is the first key your Model looks for.
      'image_url': q.imageUrl,
      'solution_url': q.solutionUrl,

      // --- DATA ---
      'Difficulty': q.difficulty,
      'Correct Answer': q.correctAnswer,

      // --- PYQ FIX ---
      // Your model looks for "Yes", so we convert the boolean back to "Yes"/"No"
      'PYQ': q.isPyq ? "Yes" : "No",
      'PYQ_Year': q.pyqYear,

      // --- NUMERICALS ---
      'Question No.': q.questionNo,
      'Difficulty_score': q.difficultyScore,
    };

    // C. Navigate
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ModifyQuestionScreen(
          questionId: q.id,
          questionData: manualDataMap, // Now contains the actual Enum
          syllabusTree: specificTree,
        ),
      ),
    ).then((_) {
      // Optional: Refresh search results if needed
      // setState(() {});
    });
  }

  // --- SEARCH LOGIC ---
  String _generateRandomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(20, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _performSearch() async {
    if (_selectedExam == null || _selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select Exam and Subject")));
      return;
    }

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _totalMatchCount = 0;
    });

    try {
      Query query = FirebaseFirestore.instance.collection('questions');

      query = query.where('Exam', isEqualTo: _selectedExam);
      query = query.where('Subject', isEqualTo: _selectedSubject);

      if (_selectedChapters.isNotEmpty && _selectedChapters.length <= 10) {
        query = query.where('Chapter', whereIn: _selectedChapters.toList());
      }
      if (_selectedTopics.isNotEmpty && _selectedTopics.length <= 10) {
        query = query.where('Topic', whereIn: _selectedTopics.toList());
      }
      if (_isPyqOnly) {
        query = query.where('PYQ', isEqualTo: "Yes");
      }

      AggregateQuerySnapshot countSnapshot = await query.count().get();
      int totalCount = countSnapshot.count ?? 0;

      String randomAnchor = _generateRandomId();
      Query randomQuery = query.orderBy(FieldPath.documentId).startAt([randomAnchor]).limit(50);

      QuerySnapshot snapshot = await randomQuery.get();
      if (snapshot.docs.isEmpty) {
        snapshot = await query.limit(50).get();
      }

      List<Question> fetched = snapshot.docs
          .map((doc) => Question.fromFirestore(doc))
          .toList();

      if (_selectedChapters.length > 10) {
        fetched = fetched.where((q) => _selectedChapters.contains(q.chapter)).toList();
      }
      if (_selectedTopics.length > 10) {
        fetched = fetched.where((q) => _selectedTopics.contains(q.topic)).toList();
      }

      fetched.shuffle();
      if (fetched.length > 20) fetched = fetched.sublist(0, 20);

      setState(() {
        _searchResults = fetched;
        _totalMatchCount = totalCount;
      });

    } catch (e) {
      debugPrint("Search Error: $e");
      String msg = "Error fetching data.";
      if (e.toString().contains("failed-precondition")) msg = "Missing Index. Check debug console.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      setState(() {
        _isSearching = false;
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

  // --- ASSIGNMENT LOGIC ---
  Future<void> _onAssign() async {
    if (_selectedQuestions.isEmpty) return;
    final teacher = FirebaseAuth.instance.currentUser;
    if (teacher == null) return;

    final titleCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: "${_selectedQuestions.length * 2}");
    bool isSingleAttempt = false;
    DateTime? selectedDeadline;

    Future<void> pickDateTime(StateSetter setDialogState, BuildContext ctx) async {
      final date = await showDatePicker(
        context: ctx,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (date == null) return;

      if (!ctx.mounted) return;
      final time = await showTimePicker(
        context: ctx,
        initialTime: const TimeOfDay(hour: 17, minute: 0),
      );
      if (time == null) return;

      setDialogState(() {
        selectedDeadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      });
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Confirm Assignment"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Assigning ${_selectedQuestions.length} questions.", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: "Assignment Title",
                      hintText: "e.g. Optics Homework",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => titleCtrl.clear()),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: timeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Time Limit (Min)",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => timeCtrl.clear()),
                    ),
                  ),
                  const SizedBox(height: 15),
                  InkWell(
                    onTap: () => pickDateTime(setDialogState, ctx),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: "Deadline (Optional)", border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)),
                      child: Text(
                        selectedDeadline == null ? "Tap to select date & time" : DateFormat('MMM d, yyyy h:mm a').format(selectedDeadline!),
                        style: TextStyle(color: selectedDeadline == null ? Colors.grey : Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    title: const Text("Strict Mode (Single Attempt)"),
                    value: isSingleAttempt,
                    onChanged: (val) => setDialogState(() => isSingleAttempt = val ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
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
      int? customTime = int.tryParse(timeCtrl.text.trim());
      await _teacherService.assignQuestionsToStudent(
        studentId: widget.studentId!,
        questions: _selectedQuestions.values.toList(),
        teacherUid: teacher.uid,
        targetAudience: widget.audienceType,
        assignmentTitle: titleCtrl.text.trim(),
        onlySingleAttempt: isSingleAttempt,
        timeLimitMinutes: customTime,
        deadline: selectedDeadline,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Assigned Successfully!")));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // --- UI COMPONENTS ---
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
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
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
                            title: Text(item),
                            value: isSelected,
                            activeColor: Colors.deepPurple,
                            onChanged: (val) => setDialogState(() { val == true ? localSelected.add(item) : localSelected.remove(item); }),
                          );
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () { onConfirm(localSelected); Navigator.pop(context); },
                          child: const Text("Done"),
                        ),
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
    // We removed the _getSyllabusTreeForCurrentSubject call here because
    // we now generate it specifically per question inside _navigateToEdit

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
      body: _isLoadingFilters
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 10), Text("Loading Syllabus...")]))
          : TabBarView(
        controller: _tabController,
        children: [
          _buildSearchTab(),
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
          _buildFilters(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text("Search & Shuffle"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _performSearch,
            ),
          ),
          const Divider(height: 40),
          if (_isSearching)
            const Center(child: CircularProgressIndicator())
          else if (_searchResults.isEmpty && _totalMatchCount == 0)
            const Center(child: Text("Adjust filters and click Search.", style: TextStyle(color: Colors.grey)))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Showing ${_searchResults.length} of $_totalMatchCount Results (Randomized)", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final q = _searchResults[index];
                    final isSelected = _selectedQuestions.containsKey(q.id);

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _toggleSelection(q),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IgnorePointer(
                                child: Checkbox(value: isSelected, onChanged: (val) {}),
                              ),
                              Expanded(
                                // --- CHANGE HERE: Added onEditPressed ---
                                child: QuestionPreviewCard(
                                  question: q
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text("Get More Questions"),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: Colors.deepPurple)),
                    onPressed: _performSearch,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedTab() {
    if (_selectedQuestions.isEmpty) return const Center(child: Text("No questions selected."));
    final selectedList = _selectedQuestions.values.toList();

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: selectedList.length,
          itemBuilder: (context, index) {
            final q = selectedList[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      // --- CHANGE HERE: Added onEditPressed ---
                      child: QuestionPreviewCard(
                        question: q,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _toggleSelection(q),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), elevation: 4),
            onPressed: _onAssign,
            child: Text("Assign ${_selectedQuestions.length} Questions", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    final decoration = InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15));
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _selectedExam,
          hint: const Text("Select Exam"),
          items: _examsList.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (val) => setState(() { _selectedExam = val; _resetFiltersBelow('Exam'); }),
          decoration: decoration.copyWith(labelText: "Exam"),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _selectedSubject,
          hint: const Text("Select Subject"),
          items: _subjectsList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (val) => setState(() { _selectedSubject = val; _resetFiltersBelow('Subject'); }),
          decoration: decoration.copyWith(labelText: "Subject"),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: _selectedSubject == null || _currentChaptersList.isEmpty
              ? null
              : () => _showMultiSelectDialog(
            title: "Select Chapters",
            items: _currentChaptersList,
            selectedItems: _selectedChapters,
            onConfirm: (set) => setState(() { _selectedChapters.clear(); _selectedChapters.addAll(set); _resetFiltersBelow('Chapter'); }),
          ),
          child: InputDecorator(
            decoration: decoration.copyWith(labelText: "Chapters", suffixIcon: const Icon(Icons.arrow_drop_down)),
            child: Text(_selectedChapters.isEmpty ? "All" : "${_selectedChapters.length} Selected", maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: _selectedChapters.isEmpty || _currentTopicsList.isEmpty
              ? null
              : () => _showMultiSelectDialog(
            title: "Select Topics",
            items: _currentTopicsList,
            selectedItems: _selectedTopics,
            onConfirm: (set) => setState(() { _selectedTopics.clear(); _selectedTopics.addAll(set); }),
          ),
          child: InputDecorator(
            decoration: decoration.copyWith(labelText: "Topics", suffixIcon: const Icon(Icons.arrow_drop_down)),
            child: Text(_selectedTopics.isEmpty ? "All" : "${_selectedTopics.length} Selected", maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          title: const Text("Previous Year Questions (PYQ) Only"),
          value: _isPyqOnly,
          onChanged: (val) => setState(() => _isPyqOnly = val ?? false),
          contentPadding: EdgeInsets.zero,
          activeColor: Colors.deepPurple,
        ),
      ],
    );
  }
}