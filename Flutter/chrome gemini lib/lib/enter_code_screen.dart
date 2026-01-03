import 'package:flutter/material.dart';
import 'package:study_smart_qc/question_model.dart';
import 'package:study_smart_qc/test_model.dart';
import 'package:study_smart_qc/test_orchestration_service.dart';
import 'package:study_smart_qc/test_preview_screen.dart';

class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({super.key});

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  final _codeController = TextEditingController();
  final _testService = TestOrchestrationService();
  bool _isLoading = false;
  String? _errorText;

  Future<void> _findTest() async {
    if (_codeController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final test = await _testService.getTestByShareCode(_codeController.text.trim());

    if (test == null) {
      setState(() {
        _isLoading = false;
        _errorText = 'Invalid or expired test code.';
      });
      return;
    }

    final questions = await _testService.getQuestionsByIds(test.questionIds);

    if (!mounted) return;

    setState(() => _isLoading = false);
    
    // Navigate to Test Preview Screen
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => TestPreviewScreen(
        questions: questions,
        timeLimitInMinutes: test.config.durationSeconds ~/ 60,
        selectedSyllabus: { for (var v in test.chapters) v : [] }, // Reconstruct a simplified map
        testName: test.testName,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Test Code')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _codeController,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '_ _ _ _',
                errorText: _errorText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _findTest,
                child: const Text('Find Test'),
              ),
          ],
        ),
      ),
    );
  }
}
