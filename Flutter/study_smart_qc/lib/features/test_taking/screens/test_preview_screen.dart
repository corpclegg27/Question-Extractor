import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/test_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/features/test_taking/screens/test_screen.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
// NEW IMPORT
import 'package:study_smart_qc/models/test_enums.dart';

class TestPreviewScreen extends StatelessWidget {
  final List<Question> questions;
  final int timeLimitInMinutes;
  final Map<String, List<String>> selectedSyllabus;
  final String testName;
  final TestModel? existingTest;

  const TestPreviewScreen({
    super.key,
    required this.questions,
    required this.timeLimitInMinutes,
    required this.selectedSyllabus,
    required this.testName,
    this.existingTest,
  });

  Future<void> _handleAttemptLater(BuildContext context) async {
    final service = TestOrchestrationService();
    if (existingTest == null) {
      await service.createAndSaveTestBlueprint(
        questions: questions,
        durationSeconds: timeLimitInMinutes * 60,
        chapterNames: selectedSyllabus.keys.toList(),
        testName: testName,
      );
    }

    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _handleAttemptNow(BuildContext context) async {
    final service = TestOrchestrationService();
    TestModel? testToAttempt = existingTest;

    if (testToAttempt == null) {
      testToAttempt = await service.createAndSaveTestBlueprint(
        questions: questions,
        durationSeconds: timeLimitInMinutes * 60,
        chapterNames: selectedSyllabus.keys.toList(),
        testName: testName,
      );
    }

    if (testToAttempt == null) return;

    await service.recordTestAttempt(testToAttempt.id);

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => TestScreen(
            questions: questions,
            timeLimitInMinutes: timeLimitInMinutes,
            // FIXED: Updated arguments here
            sourceId: testToAttempt!.id,
            testMode: TestMode.test,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Preview'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              testName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 8.0,
              children: [
                Chip(
                  label: Text('JEE Main'),
                  avatar: Icon(Icons.check_circle, color: Colors.green),
                ),
                Chip(label: Text('Physics')),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.help_outline,
                            color: Colors.deepPurple,
                          ),
                          const SizedBox(height: 8),
                          Text('${questions.length} Qs'),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: Colors.deepPurple,
                          ),
                          const SizedBox(height: 8),
                          Text('$timeLimitInMinutes Mins'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'Syllabus - ${selectedSyllabus.length} chapters',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: selectedSyllabus.length,
                itemBuilder: (context, index) {
                  final chapterName = selectedSyllabus.keys.elementAt(index);
                  final topicNames = selectedSyllabus[chapterName]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• $chapterName',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (topicNames.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 20, top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: topicNames
                                  .map(
                                    (topic) => Text(
                                  '    - $topic',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _handleAttemptNow(context),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Attempt test now'),
                    Icon(Icons.arrow_forward),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _handleAttemptLater(context),
                child: const Text('Attempt later'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}