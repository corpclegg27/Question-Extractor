// lib/features/teacher/screens/teacher_edit_question_screen.dart
// Description: Screen to Edit Question Metadata and QC Status.
// UPDATED: Added Question Subtype Dropdown, Fresh Data Fetch, Image Expansion, and Solution Image.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart'; // Ensure this exists

class TeacherEditQuestionScreen extends StatefulWidget {
  final Question question;
  final Map<String, dynamic>? rawSyllabus;

  const TeacherEditQuestionScreen({
    super.key,
    required this.question,
    this.rawSyllabus,
  });

  @override
  State<TeacherEditQuestionScreen> createState() => _TeacherEditQuestionScreenState();
}

class _TeacherEditQuestionScreenState extends State<TeacherEditQuestionScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Answer Controllers
  late TextEditingController _textAnswerCtrl;
  String? _selectedSingleAnswer;
  List<String> _selectedMultiAnswers = [];

  // Hierarchy State
  String? _selectedSubject;
  String? _selectedChapter;
  String? _selectedTopic;
  String? _selectedTopicL2;

  // Question Type & Subtype
  String? _currentQuestionType;
  String? _questionSubtype; // [NEW]

  // QC State
  String? _qcStatus;
  bool _isQCPass = false;

  // Solution Image Url (Fetched freshly)
  String? _freshSolutionUrl;

  final List<String> _qcStatusOptions = ["Pass", "Fail", "Pending", "Review Needed"];
  final List<String> _validOptions = ["A", "B", "C", "D"];

  final List<String> _questionTypes = [
    'Single Correct',
    'One or more options correct',
    'Numerical type',
    'Single Matrix Match',
    'Multi Matrix Match'
  ];

  final List<String> _questionSubtypes = [ // [NEW]
    'Assertions and reason',
    'Matrix match'
  ];

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    // Initial load from widget data
    final q = widget.question;
    _updateStateFromMap({
      'Subject': q.subject,
      'Chapter': q.chapter,
      'Topic': q.topic,
      'Topic_L2': q.topicL2,
      'Question type': _getQuestionTypeString(q.type),
      'Correct Answer': q.actualCorrectAnswers.toString(),
      'QC_Status': "Pending",
      'isQCPass': false,
      'solution_url': q.solutionUrl,
      'questionSubtype': null, // Model might not have this, wait for fetch
    }, isInitial: true);

    _textAnswerCtrl = TextEditingController();

    // Fetch fresh data immediately
    _fetchFreshData();
  }

  // Centralized method to update state from a Data Map
  void _updateStateFromMap(Map<String, dynamic> data, {bool isInitial = false}) {
    _selectedSubject = _validateString(data['Subject']);
    _selectedChapter = _validateString(data['Chapter']);
    _selectedTopic = _validateString(data['Topic']);
    _selectedTopicL2 = _validateString(data['Topic_L2']);

    // Normalize Question Type
    String typeRaw = data['Question type'] ?? 'Single Correct';
    if (_questionTypes.contains(typeRaw)) {
      _currentQuestionType = typeRaw;
    } else {
      _currentQuestionType = 'Single Correct'; // Fallback
    }

    // [NEW] Question Subtype
    String? subtypeRaw = data['questionSubtype'];
    if (subtypeRaw != null && _questionSubtypes.contains(subtypeRaw)) {
      _questionSubtype = subtypeRaw;
    } else {
      _questionSubtype = null;
    }

    // Parse Answers
    String rawAnswer = (data['Correct Answer'] ?? "").toString().replaceAll('[', '').replaceAll(']', '');

    if (_currentQuestionType == 'Single Correct') {
      if (_validOptions.contains(rawAnswer.trim())) {
        _selectedSingleAnswer = rawAnswer.trim();
      } else if (_validOptions.contains(rawAnswer.trim().toUpperCase())) {
        _selectedSingleAnswer = rawAnswer.trim().toUpperCase();
      }
    } else if (_currentQuestionType == 'One or more options correct') {
      if (data['correctAnswersOneOrMore'] is List) {
        List<dynamic> list = data['correctAnswersOneOrMore'];
        _selectedMultiAnswers = list.map((e) => e.toString()).where((e) => _validOptions.contains(e)).toList();
      } else if (rawAnswer.isNotEmpty) {
        _selectedMultiAnswers = rawAnswer.split(',').map((e) => e.trim()).where((e) => _validOptions.contains(e)).toList();
      }
    } else {
      if (!isInitial) _textAnswerCtrl.text = rawAnswer;
    }

    // QC Status Logic
    String fetchedStatus = data['QC_Status'] ?? "Pending";
    if (fetchedStatus == "Pending QC") fetchedStatus = "Pending";
    if (!_qcStatusOptions.contains(fetchedStatus)) fetchedStatus = "Pending";
    _qcStatus = fetchedStatus;

    _isQCPass = data['isQCPass'] ?? false;
    _freshSolutionUrl = data['solution_url'];
  }

  String? _validateString(String? val) {
    if (val == null || val.isEmpty || val.toLowerCase() == 'unknown') return null;
    return val;
  }

  Future<void> _fetchFreshData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('questions').doc(widget.question.id).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _updateStateFromMap(data);
            if (!['Single Correct', 'One or more options correct'].contains(_currentQuestionType)) {
              _textAnswerCtrl.text = (data['Correct Answer'] ?? "").toString();
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching QC data: $e");
    }
  }

  // --- Syllabus Helpers ---
  List<String> _getChapters() {
    if (_selectedSubject == null || widget.rawSyllabus == null) return [];
    String subjectKey = _selectedSubject!.toLowerCase();
    if (subjectKey.startsWith('phys')) subjectKey = 'physics';
    else if (subjectKey.startsWith('chem')) subjectKey = 'chemistry';
    else if (subjectKey.startsWith('math')) subjectKey = 'maths';
    else if (subjectKey.startsWith('bio')) subjectKey = 'biology';

    final subjectsData = widget.rawSyllabus!['subjects'];
    if (subjectsData == null || subjectsData is! Map || !subjectsData.containsKey(subjectKey)) return [];

    final chaptersMap = subjectsData[subjectKey]['chapters'];
    if (chaptersMap is! Map) return [];

    List<String> chapters = [];
    chaptersMap.forEach((k, v) {
      if (v is Map && v.containsKey('name')) chapters.add(v['name'].toString());
      else chapters.add(k.toString());
    });
    chapters.sort();
    return chapters;
  }

  List<String> _getTopics() {
    if (_selectedSubject == null || _selectedChapter == null || widget.rawSyllabus == null) return [];
    String subjectKey = _selectedSubject!.toLowerCase();
    if (subjectKey.startsWith('phys')) subjectKey = 'physics';
    else if (subjectKey.startsWith('chem')) subjectKey = 'chemistry';
    else if (subjectKey.startsWith('math')) subjectKey = 'maths';
    else if (subjectKey.startsWith('bio')) subjectKey = 'biology';

    final subjectsData = widget.rawSyllabus!['subjects'];
    if (subjectsData == null || subjectsData is! Map || !subjectsData.containsKey(subjectKey)) return [];

    final chaptersMap = subjectsData[subjectKey]['chapters'];
    if (chaptersMap is! Map) return [];

    Map<String, dynamic>? targetChapter;
    for (var entry in chaptersMap.entries) {
      final val = entry.value;
      if (val is Map && val['name'] == _selectedChapter) {
        targetChapter = Map<String, dynamic>.from(val);
        break;
      }
    }

    if (targetChapter == null || !targetChapter.containsKey('topics')) return [];
    final topicsMap = targetChapter['topics'];
    if (topicsMap is! Map) return [];

    List<String> topics = [];
    topicsMap.forEach((k, v) => topics.add(v.toString()));
    topics.sort();
    return topics;
  }

  void _onQCStatusChanged(String? val) {
    setState(() {
      _qcStatus = val;
      if (val == 'Pass') _isQCPass = true;
      else if (val == 'Fail') _isQCPass = false;
    });
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      String finalCorrectAnswerString = "";
      List<String>? finalOneOrMoreList;

      if (_currentQuestionType == 'Single Correct') {
        finalCorrectAnswerString = _selectedSingleAnswer ?? "";
      }
      else if (_currentQuestionType == 'One or more options correct') {
        _selectedMultiAnswers.sort();
        finalCorrectAnswerString = _selectedMultiAnswers.join(", ");
        finalOneOrMoreList = _selectedMultiAnswers;
      }
      else {
        finalCorrectAnswerString = _textAnswerCtrl.text.trim();
      }

      Map<String, dynamic> updateData = {
        'Subject': _selectedSubject,
        'Chapter': _selectedChapter,
        'Topic': _selectedTopic,
        'Topic_L2': _selectedTopicL2,
        'Question type': _currentQuestionType,
        'questionSubtype': _questionSubtype, // [NEW] Save Subtype
        'Correct Answer': finalCorrectAnswerString,
        'QC_Status': _qcStatus,
        'isQCPass': _isQCPass,
        'manually updated': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (finalOneOrMoreList != null) {
        updateData['correctAnswersOneOrMore'] = finalOneOrMoreList;
      }

      await FirebaseFirestore.instance.collection('questions').doc(widget.question.id).update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Question Updated Successfully!")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteQuestion() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Question?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('questions').doc(widget.question.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Question Deleted.")));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting: $e")));
      setState(() => _isSaving = false);
    }
  }

  Widget _buildCorrectAnswerInput() {
    if (_currentQuestionType == 'Single Correct') {
      return DropdownButtonFormField<String>(
        value: _selectedSingleAnswer,
        decoration: const InputDecoration(labelText: "Correct Option", border: OutlineInputBorder()),
        items: _validOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
        onChanged: (val) => setState(() => _selectedSingleAnswer = val),
        validator: (val) => val == null ? "Please select an option" : null,
      );
    }
    else if (_currentQuestionType == 'One or more options correct') {
      return InputDecorator(
        decoration: const InputDecoration(labelText: "Correct Options", border: OutlineInputBorder()),
        child: Wrap(
          spacing: 12,
          children: _validOptions.map((opt) {
            final isSelected = _selectedMultiAnswers.contains(opt);
            return FilterChip(
              label: Text(opt),
              selected: isSelected,
              selectedColor: Colors.green.shade100,
              checkmarkColor: Colors.green,
              labelStyle: TextStyle(
                  color: isSelected ? Colors.green.shade900 : Colors.black87,
                  fontWeight: FontWeight.bold
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedMultiAnswers.add(opt);
                  } else {
                    _selectedMultiAnswers.remove(opt);
                  }
                });
              },
            );
          }).toList(),
        ),
      );
    }
    else {
      return TextFormField(
        controller: _textAnswerCtrl,
        decoration: const InputDecoration(
            labelText: "Correct Answer (Text/Number)",
            border: OutlineInputBorder(),
            hintText: "e.g., 4.5 or A-p, B-q"
        ),
      );
    }
  }

  String _getQuestionTypeString(dynamic typeEnum) {
    String s = typeEnum.toString().split('.').last;
    if (s == 'singleCorrect') return 'Single Correct';
    if (s == 'oneOrMoreOptionsCorrect') return 'One or more options correct';
    if (s == 'numerical') return 'Numerical type';
    if (s == 'matrixSingle') return 'Single Matrix Match';
    if (s == 'matrixMulti') return 'Multi Matrix Match';
    return 'Single Correct';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Question QC"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _isSaving ? null : _deleteQuestion,
          )
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Question ID Display
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 16),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  const Text("Question ID: ", style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(
                    widget.question.customId.isNotEmpty ? widget.question.customId : widget.question.id,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),

            // Expandable Question Image
            if (widget.question.imageUrl.isNotEmpty)
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ExpandableImage(imageUrl: widget.question.imageUrl),
                ),
              ),
            const SizedBox(height: 20),

            const Text("Classification", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _selectedSubject,
              decoration: const InputDecoration(labelText: "Subject", border: OutlineInputBorder()),
              items: ["Physics", "Chemistry", "Mathematics", "Biology"]
                  .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedSubject = val;
                  _selectedChapter = null;
                  _selectedTopic = null;
                });
              },
            ),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _selectedChapter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: "Chapter", border: OutlineInputBorder()),
              items: _getChapters().map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedChapter = val;
                  _selectedTopic = null;
                });
              },
            ),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _selectedTopic,
              isExpanded: true,
              decoration: const InputDecoration(labelText: "Topic", border: OutlineInputBorder()),
              items: _getTopics().map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) => setState(() => _selectedTopic = val),
            ),
            const SizedBox(height: 10),

            TextFormField(
              initialValue: _selectedTopicL2,
              decoration: const InputDecoration(labelText: "Topic L2 (Sub-Topic)", border: OutlineInputBorder()),
              onChanged: (val) => _selectedTopicL2 = val,
            ),

            const SizedBox(height: 20),
            const Divider(),
            const Text("Question Data", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _questionTypes.contains(_currentQuestionType) ? _currentQuestionType : null,
              decoration: const InputDecoration(labelText: "Question Type", border: OutlineInputBorder()),
              items: _questionTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) {
                setState(() {
                  _currentQuestionType = val;
                  _selectedSingleAnswer = null;
                  _selectedMultiAnswers = [];
                  _textAnswerCtrl.clear();
                });
              },
            ),
            const SizedBox(height: 10),

            // [NEW] Question Subtype Dropdown
            DropdownButtonFormField<String>(
              value: _questionSubtype,
              decoration: const InputDecoration(labelText: "Question Subtype (Optional)", border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text("None")),
                ..._questionSubtypes.map((t) => DropdownMenuItem(value: t, child: Text(t))),
              ],
              onChanged: (val) => setState(() => _questionSubtype = val),
            ),
            const SizedBox(height: 15),

            _buildCorrectAnswerInput(),

            const SizedBox(height: 20),
            const Divider(),
            const Text("Quality Control", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _qcStatus,
              decoration: const InputDecoration(labelText: "QC Status", border: OutlineInputBorder()),
              items: _qcStatusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: _onQCStatusChanged,
            ),
            const SizedBox(height: 10),

            SwitchListTile(
              title: const Text("Is QC Pass?"),
              subtitle: Text(_isQCPass ? "Visible in search" : "Hidden from main search"),
              value: _isQCPass,
              activeColor: Colors.green,
              onChanged: (val) => setState(() => _isQCPass = val),
            ),

            const SizedBox(height: 20),
            // Solution Image
            if (_freshSolutionUrl != null && _freshSolutionUrl!.isNotEmpty) ...[
              const Divider(),
              const Text("Solution Image", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ExpandableImage(imageUrl: _freshSolutionUrl!),
                ),
              ),
            ],

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                onPressed: _saveChanges,
                child: const Text("Save Changes", style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textAnswerCtrl.dispose();
    super.dispose();
  }
}