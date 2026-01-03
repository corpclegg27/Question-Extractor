import 'package:flutter/material.dart';
import 'package:study_smart_qc/question_model.dart';
import 'package:study_smart_qc/test_preview_screen.dart';
import 'package:study_smart_qc/test_service.dart';

class TestConfigurationBottomSheet extends StatefulWidget {
  final Set<String> chapterIds;
  final Map<String, String> chapterIdToNameMap;
  final Set<String> topicIds;
  final Map<String, String> topicIdToNameMap;
  final Map<String, Map<String, String>> chapterIdToTopicsMap;

  const TestConfigurationBottomSheet({
    super.key,
    required this.chapterIds,
    required this.topicIds,
    required this.chapterIdToNameMap,
    required this.topicIdToNameMap,
    required this.chapterIdToTopicsMap, // FIX: Added required parameter
  });

  @override
  State<TestConfigurationBottomSheet> createState() =>
      _TestConfigurationBottomSheetState();
}

class _TestConfigurationBottomSheetState
    extends State<TestConfigurationBottomSheet> {
  int _selectedQuestionCount = 15;
  late int _timeInMinutes;
  final List<int> _questionCountOptions = [10, 15, 20, 30];
  bool _isCustom = false;
  final TextEditingController _customCountController = TextEditingController();
  late final TextEditingController _testNameController;
  bool _isGeneratingTest = false;

  @override
  void initState() {
    super.initState();
    _timeInMinutes = _selectedQuestionCount * 2;
    _customCountController.text = '45';
    final defaultChapterName = widget.chapterIds.isNotEmpty ? widget.chapterIdToNameMap[widget.chapterIds.first] : 'Custom';
    _testNameController = TextEditingController(text: 'P - $defaultChapterName Test');
  }

  @override
  void dispose() {
    _customCountController.dispose();
    _testNameController.dispose();
    super.dispose();
  }

  void _updateQuestionCount(int? count) {
    setState(() {
      _isCustom = count == null;
      if (!_isCustom) {
        _selectedQuestionCount = count!;
      } else {
        _selectedQuestionCount = int.tryParse(_customCountController.text) ?? 45;
      }
      _timeInMinutes = _selectedQuestionCount * 2;
    });
  }

  void _onCustomCountChanged(String value) {
    setState(() {
      _selectedQuestionCount = int.tryParse(value) ?? _selectedQuestionCount;
      _timeInMinutes = _selectedQuestionCount * 2;
    });
  }

  void _adjustTime(int delta) {
    setState(() {
      _timeInMinutes = (_timeInMinutes + delta).clamp(5, 180);
    });
  }

  Future<void> _generateAndPreviewTest() async {
    setState(() => _isGeneratingTest = true);

    final service = TestService();
    final questions = await service.generateTest(
      chapterIds: widget.chapterIds,
      topicIds: widget.topicIds,
      questionCount: _selectedQuestionCount,
    );

    if (!mounted) return;
    setState(() => _isGeneratingTest = false);

    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No questions found for the selected topics.'), backgroundColor: Colors.red),
      );
      Navigator.pop(context);
      return;
    }

    final Map<String, List<String>> selectedSyllabus = {};
    for (String chapId in widget.chapterIds) {
      final chapterName = widget.chapterIdToNameMap[chapId]!;
      final List<String> selectedTopicsInChapter = [];
      
      final questionTopicIdsForThisChapter = questions
          .where((q) => q.chapterId == chapId)
          .map((q) => q.topicId)
          .toSet();

      for (var topicId in questionTopicIdsForThisChapter) {
        final topicName = widget.topicIdToNameMap[topicId];
        if (topicName != null && !selectedTopicsInChapter.contains(topicName)) {
          selectedTopicsInChapter.add(topicName);
        }
      }

      if (selectedTopicsInChapter.isNotEmpty) {
        selectedSyllabus[chapterName] = selectedTopicsInChapter;
      }
    }

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TestPreviewScreen(
          questions: questions,
          timeLimitInMinutes: _timeInMinutes,
          selectedSyllabus: selectedSyllabus,
          testName: _testNameController.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configure Your Test', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _testNameController,
              decoration: const InputDecoration(labelText: 'Test Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            const Text('Number of Questions:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                ..._questionCountOptions.map((count) {
                  return ChoiceChip(
                    label: Text('$count'),
                    selected: !_isCustom && _selectedQuestionCount == count,
                    onSelected: (_) => _updateQuestionCount(count),
                  );
                }).toList(),
                ChoiceChip(
                  label: const Text('Custom'),
                  selected: _isCustom,
                  onSelected: (_) => _updateQuestionCount(null),
                )
              ],
            ),
            if (_isCustom)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: TextField(
                  controller: _customCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Enter number of questions', border: OutlineInputBorder()),
                  onChanged: _onCustomCountChanged,
                ),
              ),
            const SizedBox(height: 20),
            const Text('Time Limit:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _adjustTime(-5)),
                Text('$_timeInMinutes mins', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _adjustTime(5)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: _isGeneratingTest
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _generateAndPreviewTest,
                      child: const Text('Generate Test', style: TextStyle(fontSize: 18)),
                    ),
            )
          ],
        ),
      ),
    );
  }
}
