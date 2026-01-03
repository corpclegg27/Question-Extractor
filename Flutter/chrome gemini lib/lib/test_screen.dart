import 'dart:async';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/attempt_model.dart';
import 'package:study_smart_qc/nta_test_models.dart';
import 'package:study_smart_qc/question_model.dart';
import 'package:study_smart_qc/screens/results_screen.dart';
import 'package:study_smart_qc/test_orchestration_service.dart';
import 'package:study_smart_qc/test_result.dart';
import 'package:study_smart_qc/widgets/question_palette.dart';

class TestScreen extends StatefulWidget {
  final String? testId;
  final List<Question> questions;
  final int timeLimitInMinutes;

  const TestScreen({
    super.key,
    required this.questions,
    required this.timeLimitInMinutes,
    this.testId,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  late final PageController _pageController;
  late final Timer _timer;
  late Duration _timeRemaining;
  final Map<int, AnswerState> _answerStates = {};
  final Map<String, TextEditingController> _numericalControllers = {};
  int _currentPage = 0;

  final Map<int, int> _visitCounts = {};
  final Map<int, Stopwatch> _timeTrackers = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _timeRemaining = Duration(minutes: widget.timeLimitInMinutes);

    for (int i = 0; i < widget.questions.length; i++) {
      _answerStates[i] = AnswerState();
      final q = widget.questions[i];
      if (q.type.trim() == 'Numerical type') {
        _numericalControllers[q.id] = TextEditingController();
      }
      _visitCounts[i] = 0;
      _timeTrackers[i] = Stopwatch();
    }

    _onPageChanged(_currentPage, fromInit: true);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining.inSeconds > 0) {
        setState(() => _timeRemaining -= const Duration(seconds: 1));
      } else {
        _timer.cancel();
        _handleSubmit();
      }
    });
  }

  void _onPageChanged(int page, {bool fromInit = false}) {
    if (!fromInit && _timeTrackers.containsKey(_currentPage)) {
      _timeTrackers[_currentPage]!.stop();
    }
    setState(() {
      _currentPage = page;
      _visitCounts[page] = (_visitCounts[page] ?? 0) + 1;
      if (_answerStates[page]?.status == AnswerStatus.notVisited) {
         _answerStates[page]?.status = AnswerStatus.notAnswered;
      }
    });
    if (_timeTrackers.containsKey(page)) {
      _timeTrackers[page]!.start();
    }
  }

  Future<void> _showSubmitConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Submit Test?'),
          content: const Text('Are you sure you want to end the test?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text('Submit'),
              onPressed: () {
                Navigator.of(context).pop();
                _handleSubmit();
              },
            ),
          ],
        );
      },
    );
  }

  void _handleSaveAndNext() {
    final state = _answerStates[_currentPage]!;
    final question = widget.questions[_currentPage];
    final currentAnswer = (question.type.trim() == 'Single Correct') ? state.userAnswer : _numericalControllers[question.id]?.text;

    if (currentAnswer != null && currentAnswer.isNotEmpty) {
      if (state.status != AnswerStatus.answeredAndMarked) {
        state.status = AnswerStatus.answered;
      }
    } else {
       if (state.status != AnswerStatus.markedForReview) {
         state.status = AnswerStatus.notAnswered;
       }
    }

    if (_currentPage < widget.questions.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    } else {
      _showSubmitConfirmationDialog();
    }
  }

  void _handleClearResponse() {
    final question = widget.questions[_currentPage];
    setState(() {
      _answerStates[_currentPage]?.userAnswer = null;
      if (question.type.trim() == 'Numerical type') {
        _numericalControllers[question.id]?.clear();
      }
      _answerStates[_currentPage]?.status = AnswerStatus.notAnswered;
    });
  }

  void _handleMarkForReview() {
     final state = _answerStates[_currentPage]!;
     final question = widget.questions[_currentPage];
     final currentAnswer = (question.type.trim() == 'Single Correct') ? state.userAnswer : _numericalControllers[question.id]?.text;

     setState(() {
       if (currentAnswer != null && currentAnswer.isNotEmpty) {
         state.status = AnswerStatus.answeredAndMarked;
       } else {
         state.status = AnswerStatus.markedForReview;
       }
     });

     if (_currentPage < widget.questions.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    }
  }

  void _handleSubmit() async {
    _timer.cancel();
    _timeTrackers.values.forEach((sw) => sw.stop());

    Map<String, ResponseObject> responses = {};
    for (int i = 0; i < widget.questions.length; i++) {
      final question = widget.questions[i];
      final state = _answerStates[i]!;
      String finalStatus = 'SKIPPED';
      String? finalAnswer = state.userAnswer;

      if (state.status == AnswerStatus.answered || state.status == AnswerStatus.answeredAndMarked) {
        final isCorrect = finalAnswer?.trim().toLowerCase() == question.correctAnswer.trim().toLowerCase();
        finalStatus = isCorrect ? 'CORRECT' : 'INCORRECT';
      } else if (state.status == AnswerStatus.markedForReview) {
        finalStatus = 'REVIEW';
      }

      responses[question.id] = ResponseObject(
        status: finalStatus,
        selectedOption: finalAnswer,
        correctOption: question.correctAnswer,
        timeSpent: _timeTrackers[i]!.elapsed.inSeconds,
        visitCount: _visitCounts[i] ?? 0,
        q_no: i + 1,
      );
    }
    
    final score = (responses.values.where((r) => r.status == 'CORRECT').length * 4) - (responses.values.where((r) => r.status == 'INCORRECT').length * 1);
    
    // **FIX**: Pass the required 'questions' parameter.
    await TestOrchestrationService().saveTestAttempt(
      testId: widget.testId ?? 'unsaved_test',
      questions: widget.questions, // This was the missing parameter
      score: score,
      timeTakenSeconds: (Duration(minutes: widget.timeLimitInMinutes) - _timeRemaining).inSeconds,
      responses: responses,
    );

    final result = TestResult(
      questions: widget.questions,
      answerStates: _answerStates,
      timeTaken: Duration(minutes: widget.timeLimitInMinutes) - _timeRemaining,
      totalMarks: widget.questions.length * 4,
      responses: responses,
    );

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => ResultsScreen(result: result)),
      );
    }
  }
  
  void _showAllQuestions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Question Paper'),
        content: SizedBox(
          width: double.maxFinite,
          child: QuestionPalette(
            questionCount: widget.questions.length,
            answerStates: _answerStates,
            currentQuestionIndex: _currentPage,
            onQuestionTapped: (index) {
              Navigator.of(context).pop();
              _pageController.jumpToPage(index);
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timer.cancel();
    _timeTrackers.values.forEach((sw) => sw.stop());
    _numericalControllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  String get _formattedTime => '${_timeRemaining.inMinutes.toString().padLeft(2, '0')}:${(_timeRemaining.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _showSubmitConfirmationDialog),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(border: Border.all(color: Colors.white), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.timer_outlined, size: 18), const SizedBox(width: 4), Text(_formattedTime)]),
        ),
        centerTitle: true,
        actions: [TextButton(onPressed: _showSubmitConfirmationDialog, child: const Text('Submit', style: TextStyle(color: Colors.white)))],
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildCompactQuestionPalette(),
          const Divider(height: 1),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.questions.length,
              itemBuilder: (context, index) {
                final q = widget.questions[index];
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Q.${index + 1} (+4, -1)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      InteractiveViewer(maxScale: 4.0, child: Image.network(q.imageUrl, fit: BoxFit.contain)),
                      const SizedBox(height: 20),
                      if (q.type.trim() == 'Single Correct') _buildScqOptions(q) else _buildNumericalInput(q),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }
  
  Widget _buildCompactQuestionPalette() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          const Text("Physics", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(widget.questions.length, (index) {
                  final state = _answerStates[index] ?? AnswerState();
                  final isCurrent = index == _currentPage;
                  return GestureDetector(
                    onTap: () => _pageController.jumpToPage(index),
                    child: Container(
                      width: 40, height: 40, margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: state.status.color,
                        borderRadius: BorderRadius.circular(4),
                        border: isCurrent ? Border.all(color: Colors.black, width: 2.5) : null,
                      ),
                      child: Center(child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    ),
                  );
                }),
              ),
            ),
          ),
          TextButton(onPressed: _showAllQuestions, child: const Text('View All >')),
        ],
      ),
    );
  }
  
  Widget _buildScqOptions(Question question) {
    final options = ['A', 'B', 'C', 'D'];
    return Column(
      children: options.map((option) {
        return RadioListTile<String>(
          title: Text(option),
          value: option,
          groupValue: _answerStates[_currentPage]?.userAnswer,
          onChanged: (value) => setState(() => _answerStates[_currentPage]?.userAnswer = value),
        );
      }).toList(),
    );
  }

  Widget _buildNumericalInput(Question question) {
    return TextField(
      controller: _numericalControllers[question.id],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Your Answer', border: OutlineInputBorder()),
      onChanged: (value) => _answerStates[_currentPage]?.userAnswer = value,
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8).copyWith(bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 3)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: _handleClearResponse, child: const Text('Clear Response'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: _handleMarkForReview, child: const Text('Mark for Review'))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: _currentPage == 0 ? null : () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn), child: const Text('Previous'))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: _handleSaveAndNext, child: Text(_currentPage == widget.questions.length - 1 ? 'Submit' : 'Save & Next'))),
            ],
          ),
        ],
      ),
    );
  }
}
