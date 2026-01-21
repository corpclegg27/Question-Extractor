// lib/features/teacher/screens/modify_question_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/features/common/widgets/teacher_question_preview_card.dart';

class ModifyQuestionScreen extends StatefulWidget {
  final String questionId;
  final Map<String, dynamic> questionData;
  final Map<String, dynamic> syllabusTree;

  const ModifyQuestionScreen({
    super.key,
    required this.questionId,
    required this.questionData,
    required this.syllabusTree,
  });

  @override
  State<ModifyQuestionScreen> createState() => _ModifyQuestionScreenState();
}

class _ModifyQuestionScreenState extends State<ModifyQuestionScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late TextEditingController _pyqYearController;
  late TextEditingController _difficultyScoreController;
  late TextEditingController _correctAnswerController;

  String? _selectedChapter;
  String? _selectedTopic;
  String? _selectedTopicL2;
  String? _selectedQCStatus;
  String? _selectedDifficulty;
  String? _selectedPYQ;

  List<String> _chapters = [];
  List<String> _topics = [];
  List<String> _topicL2s = [];

  final List<String> _qcOptions = ['Pending QC', 'Accepted', 'Rejected'];
  final List<String> _diffOptions = ['Easy', 'Medium', 'Hard'];
  final List<String> _pyqOptions = ['Yes', 'No'];

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    final data = widget.questionData;

    _pyqYearController = TextEditingController(text: (data['PYQ_Year'] ?? 0).toString());
    _difficultyScoreController = TextEditingController(text: (data['Difficulty_score'] ?? 0).toString());
    _correctAnswerController = TextEditingController(text: (data['Correct Answer'] ?? "").toString());

    _selectedQCStatus = data['QC_Status'];
    _selectedDifficulty = data['Difficulty'];
    _selectedPYQ = data['PYQ'];

    _selectedChapter = data['Chapter'];
    _selectedTopic = data['Topic'];
    _selectedTopicL2 = data['Topic_L2'];

    _chapters = widget.syllabusTree.keys.toList();

    if (_selectedChapter != null && _chapters.contains(_selectedChapter)) {
      _updateTopicsList(_selectedChapter!);
      if (_selectedTopic != null && _topics.contains(_selectedTopic)) {
        _updateTopicL2List(_selectedChapter!, _selectedTopic!);
      }
    }
  }

  // --- FIX IS HERE ---
  // We add 'questionNo' and 'type' because your Question model requires them.
  Question _buildPreviewQuestion() {
    return Question(
      id: widget.questionId,
      // Provide a fallback of 0 if missing, since it's required
      questionNo: widget.questionData['questionNo'] ?? 0,
      // Provide a fallback type (e.g. 'MCQ') if missing
      type: widget.questionData['type'] ?? 'MCQ',

      customId: widget.questionData['question_id'] ?? widget.questionId,

      // Live State variables
      chapter: _selectedChapter ?? "",
      topic: _selectedTopic ?? "",
      topicL2: _selectedTopicL2 ?? "",
      difficulty: _selectedDifficulty ?? "Unknown",
      correctAnswer: _correctAnswerController.text,

      // Static Data
      ocrText: widget.questionData['OCR_Text'] ?? "",
      imageUrl: widget.questionData['image_url'] ?? "",
      solutionUrl: widget.questionData['solution_url'],

      // Metadata
      qcStatus: _selectedQCStatus,
      isPyq: _selectedPYQ == 'Yes',
      pyqYear: int.tryParse(_pyqYearController.text) ?? 0,
      difficultyScore: num.tryParse(_difficultyScoreController.text) ?? 0,

      // Required defaults
      exam: widget.questionData['Exam'] ?? "",
      subject: widget.questionData['Subject'] ?? "",
      chapterId: "",
      topicId: "",
      topicL2Id: "",
    );
  }

  String? _getValidValue(String? value, List<String> items) {
    if (value == null) return null;
    if (items.contains(value)) return value;
    return null;
  }

  void _updateTopicsList(String chapter) {
    final chapterData = widget.syllabusTree[chapter];
    setState(() {
      if (chapterData is Map) {
        _topics = chapterData.keys.map((e) => e.toString()).toList();
      } else {
        _topics = [];
      }
      if (!_topics.contains(_selectedTopic)) {
        _selectedTopic = null;
        _selectedTopicL2 = null;
        _topicL2s = [];
      }
    });
  }

  void _updateTopicL2List(String chapter, String topic) {
    final chapterData = widget.syllabusTree[chapter];
    setState(() {
      if (chapterData is Map && chapterData[topic] is List) {
        _topicL2s = List<String>.from(chapterData[topic]);
      } else {
        _topicL2s = [];
      }
      if (!_topicL2s.contains(_selectedTopicL2)) {
        _selectedTopicL2 = null;
      }
    });
  }

  Future<void> _updateQuestion() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('questions').doc(widget.questionId).update({
        'Chapter': _selectedChapter,
        'Topic': _selectedTopic,
        'Topic_L2': _selectedTopicL2 ?? "",
        'QC_Status': _selectedQCStatus,
        'Correct Answer': _correctAnswerController.text.trim(),
        'Difficulty': _selectedDifficulty,
        'Difficulty_score': num.tryParse(_difficultyScoreController.text) ?? 0,
        'PYQ': _selectedPYQ,
        'PYQ_Year': int.tryParse(_pyqYearController.text) ?? 0,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteQuestion() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Question?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance.collection('questions').doc(widget.questionId).delete();
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modify Question'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _isLoading ? null : _deleteQuestion,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- REUSED PREVIEW CARD ---
              QuestionPreviewCard(
                question: _buildPreviewQuestion(),
              ),

              const SizedBox(height: 30),
              const Divider(thickness: 2),
              const SizedBox(height: 10),

              // --- SYLLABUS MAPPING ---
              _buildSectionHeader("Syllabus Mapping"),
              DropdownButtonFormField<String>(
                initialValue: _getValidValue(_selectedChapter, _chapters),
                decoration: const InputDecoration(labelText: 'Chapter', border: OutlineInputBorder()),
                isExpanded: true,
                items: _chapters.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedChapter = val;
                    _updateTopicsList(val!);
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _getValidValue(_selectedTopic, _topics),
                decoration: const InputDecoration(labelText: 'Topic', border: OutlineInputBorder()),
                isExpanded: true,
                items: _topics.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: _selectedChapter == null
                    ? null
                    : (val) {
                  setState(() {
                    _selectedTopic = val;
                    _updateTopicL2List(_selectedChapter!, val!);
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _getValidValue(_selectedTopicL2, _topicL2s),
                decoration: const InputDecoration(labelText: 'Sub-Topic (L2)', border: OutlineInputBorder()),
                isExpanded: true,
                items: _topicL2s.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: _selectedTopic == null ? null : (val) => setState(() => _selectedTopicL2 = val),
              ),

              const SizedBox(height: 30),

              // --- METADATA ---
              _buildSectionHeader("Metadata"),
              DropdownButtonFormField<String>(
                initialValue: _getValidValue(_selectedQCStatus, _qcOptions),
                decoration: const InputDecoration(labelText: 'QC Status', border: OutlineInputBorder()),
                items: _qcOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) => setState(() => _selectedQCStatus = val),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _getValidValue(_selectedDifficulty, _diffOptions),
                      decoration: const InputDecoration(labelText: 'Difficulty', border: OutlineInputBorder()),
                      items: _diffOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) => setState(() => _selectedDifficulty = val),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _correctAnswerController,
                      decoration: const InputDecoration(
                        labelText: 'Correct Ans',
                        border: OutlineInputBorder(),
                        hintText: 'e.g. A',
                      ),
                      onChanged: (val) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _difficultyScoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Difficulty Score', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _getValidValue(_selectedPYQ, _pyqOptions),
                      decoration: const InputDecoration(labelText: 'PYQ?', border: OutlineInputBorder()),
                      items: _pyqOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) => setState(() => _selectedPYQ = val),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _pyqYearController,
                      enabled: _selectedPYQ == 'Yes',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'PYQ Year', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // --- UPDATE BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text("UPDATE QUESTION"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _updateQuestion,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pyqYearController.dispose();
    _difficultyScoreController.dispose();
    _correctAnswerController.dispose();
    super.dispose();
  }
}