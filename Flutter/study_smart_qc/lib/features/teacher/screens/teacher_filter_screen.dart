// lib/features/teacher/screens/teacher_filter_screen.dart
// Description: Teacher Filter Screen. Implements "Fetch All & Shuffle" for results < 500 to ensure perfect randomization and completeness.

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/features/common/widgets/question_preview_card.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/services/teacher_service.dart';
import 'package:study_smart_qc/features/teacher/screens/modify_question_screen.dart';
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/models/marking_configuration.dart';

class SyllabusChapter {
  final String id;
  final String name;
  final Map<String, String> topics;

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

  bool _isLoadingFilters = true;
  List<String> _examsList = [];
  List<String> _subjectsList = [];

  // Master list of tags
  List<String> _tagsList = [];

  final List<String> _questionTypesList = [
    'Single Correct',
    'One or more options correct',
    'Numerical type',
    'Single Matrix Match',
    'Multi Matrix Match'
  ];

  final Map<String, List<SyllabusChapter>> _syllabusCache = {};

  String? _selectedExam;
  String? _selectedSubject;
  String? _selectedQuestionType;

  final Set<String> _selectedChapters = {};
  final Set<String> _selectedTopics = {};

  // Selected tags
  final Set<String> _selectedTags = {};

  bool _isPyqOnly = false;

  bool _isSearching = false;
  List<Question> _searchResults = [];
  int _totalMatchCount = 0;

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

  Future<void> _fetchFilterData() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final optionsDoc = await firestore.collection('static_data').doc('option_sets').get();

      if (optionsDoc.exists) {
        final data = optionsDoc.data()!;
        _examsList = List<String>.from(data['exams_list'] ?? []);
        _subjectsList = List<String>.from(data['subjects_list'] ?? []);

        // Fetch 'tags' (lowercase)
        if (data.containsKey('tags')) {
          _tagsList = List<String>.from(data['tags'] ?? []);
        }
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

  Map<String, dynamic> _buildTreeForSubject(String subjectName) {
    String key = _normalizeSubject(subjectName);
    if (!_syllabusCache.containsKey(key)) return {};
    final chapters = _syllabusCache[key] ?? [];
    Map<String, dynamic> tree = {};
    for (var chap in chapters) {
      Map<String, dynamic> topicMap = {};
      for (var topicName in chap.topics.values) {
        topicMap[topicName] = <String>[];
      }
      tree[chap.name] = topicMap;
    }
    return tree;
  }

  String _generateRandomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(20, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _performSearch() async {
    bool hasBasicContext = _selectedExam != null && _selectedSubject != null;
    bool hasTags = _selectedTags.isNotEmpty;

    if (!hasBasicContext && !hasTags) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select (Exam & Subject) OR Tags")));
      return;
    }

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _totalMatchCount = 0;
    });

    try {
      Query query = FirebaseFirestore.instance.collection('questions');

      if (_selectedExam != null) {
        query = query.where('Exam', isEqualTo: _selectedExam);
      }
      if (_selectedSubject != null) {
        query = query.where('Subject', isEqualTo: _selectedSubject);
      }

      if (_selectedQuestionType != null) {
        query = query.where('Question type', isEqualTo: _selectedQuestionType);
      }
      if (_isPyqOnly) {
        query = query.where('PYQ', isEqualTo: "Yes");
      }

      // Priority Branching Logic
      bool isFilteringChaptersClientSide = false;
      bool isFilteringTopicsClientSide = false;

      if (_selectedTags.isNotEmpty) {
        final cleanTags = _selectedTags.map((e) => e.trim()).toList();

        debugPrint("🔍 Searching Tags: $cleanTags");
        query = query.where('tags', arrayContainsAny: cleanTags);

        // Defer Chapter/Topic filtering to client-side
        if (_selectedChapters.isNotEmpty) isFilteringChaptersClientSide = true;
        if (_selectedTopics.isNotEmpty) isFilteringTopicsClientSide = true;

      } else {
        if (_selectedChapters.isNotEmpty && _selectedChapters.length <= 10) {
          query = query.where('Chapter', whereIn: _selectedChapters.toList());
        } else if (_selectedChapters.length > 10) {
          isFilteringChaptersClientSide = true;
        }

        if (_selectedTopics.isNotEmpty && _selectedTopics.length <= 10) {
          query = query.where('Topic', whereIn: _selectedTopics.toList());
        } else if (_selectedTopics.length > 10) {
          isFilteringTopicsClientSide = true;
        }
      }

      // 1. Get Total Count
      AggregateQuerySnapshot countSnapshot = await query.count().get();
      int totalCount = countSnapshot.count ?? 0;
      debugPrint("🔍 Total Matches Found in Firestore: $totalCount");

      QuerySnapshot snapshot;

      // [CRITICAL CHANGE] "Fetch All & Shuffle" Strategy
      // If results are <= 500, we fetch ALL of them. This allows us to show the user
      // every possible question (perfect completeness) and shuffle them perfectly (perfect randomness).
      if (totalCount <= 500) {
        snapshot = await query.limit(500).get();
      } else {
        // If results > 500, downloading all is too slow.
        // We use the "Random Anchor" strategy to jump into the middle of the dataset and fetch a slice.
        String randomAnchor = _generateRandomId();
        snapshot = await query.orderBy(FieldPath.documentId).startAt([randomAnchor]).limit(20).get();

        if (snapshot.docs.length < 20) {
          QuerySnapshot fallbackSnapshot = await query.limit(20).get();
          if (snapshot.docs.isEmpty) {
            snapshot = fallbackSnapshot;
          } else if (snapshot.docs.length < 5) {
            snapshot = fallbackSnapshot;
          }
        }
      }

      List<Question> fetched = snapshot.docs
          .map((doc) => Question.fromFirestore(doc))
          .toList();

      // 3. Client-Side Filtering
      if (isFilteringChaptersClientSide) {
        fetched = fetched.where((q) => _selectedChapters.contains(q.chapter)).toList();
      }
      if (isFilteringTopicsClientSide) {
        fetched = fetched.where((q) => _selectedTopics.contains(q.topic)).toList();
      }

      // 4. Shuffle locally
      fetched.shuffle();

      // [FIX] NO slicing if we are in "Fetch All" mode.
      // If we fetched 120 documents, we display all 120.
      // We only slice if we intentionally did a partial fetch (the >500 case).
      // Since the >500 query uses limit(20), fetched.length is naturally 20, so no slicing needed there either.
      // The logic self-regulates.

      setState(() {
        _searchResults = fetched;
        _totalMatchCount = totalCount;
      });

    } catch (e) {
      debugPrint("❌ Search Error: $e");
      String msg = "Error fetching data.";
      if (e.toString().contains("failed-precondition")) {
        msg = "Missing Index. Check debug console for link.";
      }
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

  Future<void> _onAssign() async {
    if (_selectedQuestions.isEmpty) return;
    final teacher = FirebaseAuth.instance.currentUser;
    if (teacher == null) return;

    final titleCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: "${_selectedQuestions.length * 2}");
    bool isSingleAttempt = false;

    final now = DateTime.now();
    DateTime? selectedDeadline = DateTime(now.year, now.month, now.day + 1, 23, 59);

    Set<QuestionType> presentTypes = _selectedQuestions.values.map((q) => q.type).toSet();

    Map<QuestionType, MarkingConfiguration> markingConfigs = {};
    for (var type in presentTypes) {
      if (type == QuestionType.oneOrMoreOptionsCorrect) {
        markingConfigs[type] = MarkingConfiguration.jeeAdvanced();
      } else if (type == QuestionType.numerical) {
        markingConfigs[type] = const MarkingConfiguration(correctScore: 4, incorrectScore: 0);
      } else {
        markingConfigs[type] = MarkingConfiguration.jeeMain();
      }
    }

    Future<void> pickDateTime(StateSetter setDialogState, BuildContext ctx) async {
      final date = await showDatePicker(
        context: ctx,
        initialDate: selectedDeadline!,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (date == null) return;
      if (!ctx.mounted) return;
      final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(selectedDeadline!));
      if (time == null) return;
      setDialogState(() => selectedDeadline = DateTime(date.year, date.month, date.day, time.hour, time.minute));
    }

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Confirm Assignment"),
            content: Container(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Assigning ${_selectedQuestions.length} questions.", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Assignment Title", border: OutlineInputBorder())),
                    const SizedBox(height: 15),
                    TextField(controller: timeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Time Limit (Min)", border: OutlineInputBorder())),
                    const SizedBox(height: 15),
                    InkWell(
                      onTap: () => pickDateTime(setDialogState, ctx),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: "Deadline", border: OutlineInputBorder()),
                        child: Text(selectedDeadline == null ? "Optional" : DateFormat('MMM d, h:mm a').format(selectedDeadline!)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(title: const Text("Strict Mode (Single Attempt)"), value: isSingleAttempt, onChanged: (val) => setDialogState(() => isSingleAttempt = val ?? false)),

                    const Divider(),
                    const Text("Marking Scheme", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),

                    ...markingConfigs.keys.map((type) {
                      MarkingConfiguration cfg = markingConfigs[type]!;
                      String initCorrect = cfg.correctScore.toString().replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '');
                      String initIncorrect = cfg.incorrectScore.toString().replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 15),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_getLabelForType(type), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: initCorrect,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: "Correct (+)", isDense: true),
                                    onChanged: (val) {
                                      double v = double.tryParse(val) ?? 4.0;
                                      markingConfigs[type] = _updateConfig(cfg, correct: v);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: initIncorrect,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: "Wrong (-)", isDense: true),
                                    onChanged: (val) {
                                      double v = double.tryParse(val) ?? -1.0;
                                      if (v > 0) v = -v;
                                      markingConfigs[type] = _updateConfig(cfg, incorrect: v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (type == QuestionType.oneOrMoreOptionsCorrect)
                              Row(
                                children: [
                                  const Text("Partial Marking?"),
                                  Switch(
                                      value: cfg.allowPartialMarking,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          markingConfigs[type] = _updateConfig(cfg, partial: val);
                                        });
                                      }
                                  )
                                ],
                              )
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
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
        markingSchemes: markingConfigs,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Assigned Successfully!")));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  String _getLabelForType(QuestionType t) {
    if (t == QuestionType.singleCorrect) return "Single Correct";
    if (t == QuestionType.oneOrMoreOptionsCorrect) return "Multi Correct";
    if (t == QuestionType.numerical) return "Numerical";
    return "Other";
  }

  MarkingConfiguration _updateConfig(MarkingConfiguration old, {double? correct, double? incorrect, bool? partial}) {
    return MarkingConfiguration(
        correctScore: correct ?? old.correctScore,
        incorrectScore: incorrect ?? old.incorrectScore,
        allowPartialMarking: partial ?? old.allowPartialMarking,
        unattemptedScore: old.unattemptedScore,
        partialScorePerOption: old.partialScorePerOption
    );
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

                // [CRITICAL UX FIX] Only show "Get More Questions" if total matches > 500.
                // If matches <= 500, we have already displayed ALL of them, so "Get More" is pointless.
                if (_totalMatchCount > 500)
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
    selectedList.sort((a, b) {
      int sA = _getSubjectWeight(a.subject);
      int sB = _getSubjectWeight(b.subject);
      if (sA != sB) return sA.compareTo(sB);

      int tA = _getTypeWeight(a.type);
      int tB = _getTypeWeight(b.type);
      return tA.compareTo(tB);
    });

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
                      child: QuestionPreviewCard(
                          question: q
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

  int _getSubjectWeight(String s) {
    s = s.toLowerCase();
    if (s.contains('physic')) return 1;
    if (s.contains('chem')) return 2;
    if (s.contains('math')) return 3;
    if (s.contains('bio')) return 4;
    return 5;
  }

  int _getTypeWeight(QuestionType t) {
    if (t == QuestionType.singleCorrect) return 1;
    if (t == QuestionType.oneOrMoreOptionsCorrect) return 2;
    if (t == QuestionType.numerical) return 3;
    return 4;
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
        DropdownButtonFormField<String>(
          value: _selectedQuestionType,
          hint: const Text("Select Type (Optional)"),
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text("All Types")),
            ..._questionTypesList.map((t) => DropdownMenuItem(value: t, child: Text(t))),
          ],
          onChanged: (val) => setState(() { _selectedQuestionType = val; }),
          decoration: decoration.copyWith(labelText: "Question Type"),
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
        // [NEW] Tags Multi-Select Dropdown
        InkWell(
          onTap: () => _showMultiSelectDialog(
            title: "Select Tags",
            items: _tagsList,
            selectedItems: _selectedTags,
            onConfirm: (set) => setState(() { _selectedTags.clear(); _selectedTags.addAll(set); }),
          ),
          child: InputDecorator(
            decoration: decoration.copyWith(labelText: "Tags (Optional)", suffixIcon: const Icon(Icons.arrow_drop_down)),
            child: Text(_selectedTags.isEmpty ? "All" : "${_selectedTags.length} Selected", maxLines: 1, overflow: TextOverflow.ellipsis),
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