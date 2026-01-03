import 'package:flutter/material.dart';
import 'package:study_smart_qc/custom_test_model.dart';
import 'package:study_smart_qc/nta_test_models.dart';
import 'package:study_smart_qc/question_model.dart';
import 'package:study_smart_qc/screens/results_screen.dart';
import 'package:study_smart_qc/screens/syllabus_screen.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/test_model.dart';
import 'package:study_smart_qc/test_orchestration_service.dart';
import 'package:study_smart_qc/test_result.dart';
import 'package:study_smart_qc/test_screen.dart';

class CustomTestHistoryScreen extends StatefulWidget {
  const CustomTestHistoryScreen({super.key});

  @override
  State<CustomTestHistoryScreen> createState() => _CustomTestHistoryScreenState();
}

class _CustomTestHistoryScreenState extends State<CustomTestHistoryScreen> {
  final TestOrchestrationService _testService = TestOrchestrationService();
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Your Own Test'),
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: StreamBuilder<List<TestModel>>(
              stream: _testService.getSavedTestsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No tests created yet.'));
                }

                final allTests = snapshot.data!;
                final filteredTests = allTests.where((test) {
                  if (_filter == 'All') return true;
                  return test.status == _filter;
                }).toList();

                if (filteredTests.isEmpty) {
                  return Center(child: Text('No tests match the \'$_filter\' filter.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100), 
                  itemCount: filteredTests.length,
                  itemBuilder: (context, index) {
                    final test = filteredTests[index];
                    return _buildTestListItem(test);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SyllabusScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('Create new custom test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: ['All', 'Attempted', 'Not Attempted'].map((filter) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ChoiceChip(
              label: Text(filter),
              selected: _filter == filter,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _filter = filter);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTestListItem(TestModel test) {
    final formattedDate = DateFormat('d MMM yyyy').format(test.createdAt.toDate());
    bool isAttempted = test.status == 'Attempted';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(test.testName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('JEE Main • $formattedDate', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    if (isAttempted) {
                      final attempt = await _testService.getAttemptForTest(test.id);
                      final questions = await _testService.getQuestionsByIds(test.questionIds);
                      if (mounted && attempt != null) {
                        
                        final answerStates = <int, AnswerState>{};
                        for (int i = 0; i < questions.length; i++) {
                           final questionId = questions[i].id;
                           final response = attempt.responses[questionId];
                           answerStates[i] = AnswerState(
                             userAnswer: response?.selectedOption,
                             status: response?.status == 'CORRECT' || response?.status == 'INCORRECT' ? AnswerStatus.answered : AnswerStatus.notAnswered, 
                           );
                        }

                        final result = TestResult(
                            questions: questions,
                            answerStates: answerStates, 
                            timeTaken: Duration(seconds: attempt.timeTakenSeconds),
                            totalMarks: questions.length * 4,
                            responses: attempt.responses);

                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => ResultsScreen(result: result)));
                      }
                    } else {
                      final List<Question> questions = await _testService.getQuestionsByIds(test.questionIds);
                      if (mounted) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => TestScreen(questions: questions, timeLimitInMinutes: test.config.durationSeconds ~/ 60, testId: test.id)));
                      }
                    }
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Text(isAttempted ? 'View Analysis' : 'Attempt now'), const Icon(Icons.arrow_forward_ios, size: 14)]),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
