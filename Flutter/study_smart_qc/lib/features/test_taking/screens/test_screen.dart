// lib/features/test_taking/screens/test_screen.dart
// Description: Main test interface. Updated _handleSubmit to automatically handle and skip corrupt questions (missing correct answers) to prevent crashes.

import 'dart:async';
import 'package:flutter/material.dart';

// 1. IMPORT MODELS
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/marking_configuration.dart';

// 2. IMPORT SCREENS & SERVICES
import 'package:study_smart_qc/features/analytics/screens/results_screen.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
import 'package:study_smart_qc/services/local_session_service.dart';
import 'package:study_smart_qc/services/universal_scoring_engine.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart';
import 'package:study_smart_qc/widgets/question_input_widget.dart';

class TestScreen extends StatefulWidget {
  final String sourceId;
  final String assignmentCode;
  final String title;
  final bool onlySingleAttempt;
  final List<Question> questions;
  final int timeLimitInMinutes;
  final TestMode testMode;

  final int? resumedTimerSeconds;
  final int? resumedPageIndex;
  final Map<String, ResponseObject>? resumedResponses;

  // Configuration passed from Teacher Service
  final Map<QuestionType, MarkingConfiguration>? markingSchemes;

  const TestScreen({
    super.key,
    required this.questions,
    required this.timeLimitInMinutes,
    this.sourceId = '',
    this.assignmentCode = 'PRAC',
    this.title = 'Practice Test',
    this.onlySingleAttempt = false,
    this.testMode = TestMode.test,
    this.resumedTimerSeconds,
    this.resumedPageIndex,
    this.resumedResponses,
    this.markingSchemes,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> with WidgetsBindingObserver {
  late final PageController _pageController;
  late final Timer _timer;
  late Duration _overallTimeCounter;
  bool _isPaused = false;

  final ScrollController _paletteController = ScrollController();

  // --- SORTING & CONFIG STATE ---
  List<Question> _sortedQuestions = [];
  final List<String> _subjects = [];
  final Map<String, int> _subjectStartIndex = {};
  late Map<QuestionType, MarkingConfiguration> _activeMarkingSchemes;
  String _currentSubject = "";

  // --- LEGACY STATE ---
  final Map<int, AnswerState> _answerStates = {};
  final Map<int, int> _visitCounts = {};
  final Map<int, Stopwatch> _timeTrackers = {};
  final Map<int, int> _accumulatedTime = {};

  int _currentPage = 0;
  bool _isAnswerChecked = false;

  final LocalSessionService _localSessionService = LocalSessionService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1. INITIALIZE CONFIG (Defaults if null)
    if (widget.markingSchemes != null && widget.markingSchemes!.isNotEmpty) {
      _activeMarkingSchemes = widget.markingSchemes!;
    } else {
      _activeMarkingSchemes = {
        QuestionType.singleCorrect: MarkingConfiguration.jeeMain(),
        QuestionType.numerical: const MarkingConfiguration(correctScore: 4, incorrectScore: 0),
        QuestionType.oneOrMoreOptionsCorrect: MarkingConfiguration.jeeAdvanced(),
      };
    }

    // 2. SORT QUESTIONS (Subject -> Type)
    _sortQuestions();

    // 3. INITIALIZE CONTROLLER & INDEX
    _currentPage = widget.resumedPageIndex ?? 0;
    if (_currentPage >= _sortedQuestions.length) _currentPage = 0;

    _pageController = PageController(initialPage: _currentPage);

    // Set initial subject for Tabs
    if (_sortedQuestions.isNotEmpty) {
      _currentSubject = _capitalize(_sortedQuestions[_currentPage].subject);
    }

    // 4. INIT TIMER
    if (widget.resumedTimerSeconds != null) {
      _overallTimeCounter = Duration(seconds: widget.resumedTimerSeconds!);
    } else {
      _overallTimeCounter = (widget.testMode == TestMode.test)
          ? Duration(minutes: widget.timeLimitInMinutes)
          : Duration.zero;
    }

    // 5. INITIALIZE ANSWER STATES
    for (int i = 0; i < _sortedQuestions.length; i++) {
      final question = _sortedQuestions[i];
      _visitCounts[i] = 0;
      _timeTrackers[i] = Stopwatch();
      _accumulatedTime[i] = 0;

      AnswerState newState = AnswerState(status: AnswerStatus.notVisited);

      // RESTORE LOGIC (Using Question ID to map correctly after sorting)
      if (widget.resumedResponses != null &&
          widget.resumedResponses!.containsKey(question.id)) {

        final savedResponse = widget.resumedResponses![question.id]!;

        // Handle restoration of List from comma-separated String
        dynamic restoredAnswer = savedResponse.selectedOption;
        if (restoredAnswer is String && restoredAnswer.contains(',') && question.type == QuestionType.oneOrMoreOptionsCorrect) {
          restoredAnswer = restoredAnswer.split(',').map((e) => e.trim()).toList();
        }

        newState.userAnswer = restoredAnswer;
        _accumulatedTime[i] = savedResponse.timeSpent;

        switch (savedResponse.status) {
          case 'REVIEW':
            newState.status = AnswerStatus.markedForReview;
            break;
          case 'REVIEW_ANSWERED':
            newState.status = AnswerStatus.answeredAndMarked;
            break;
          case 'ANSWERED':
          case 'CORRECT':
          case 'INCORRECT':
          case 'PARTIALLY_CORRECT':
            newState.status = AnswerStatus.answered;
            break;
          case 'SKIPPED':
            newState.status = AnswerStatus.notAnswered;
            break;
          default:
            if (savedResponse.selectedOption != null) {
              newState.status = AnswerStatus.answered;
            }
        }
        _visitCounts[i] = savedResponse.visitCount;
      }
      _answerStates[i] = newState;
    }

    _onPageChanged(_currentPage, fromInit: true);
    _startTimer();
  }

  void _sortQuestions() {
    _sortedQuestions = List.from(widget.questions);

    // Sorting Logic: Subject -> Type
    _sortedQuestions.sort((a, b) {
      int subjectCompare = _getSubjectWeight(a.subject).compareTo(_getSubjectWeight(b.subject));
      if (subjectCompare != 0) return subjectCompare;
      return _getTypeWeight(a.type).compareTo(_getTypeWeight(b.type));
    });

    // Populate Subject Tabs
    _subjects.clear();
    _subjectStartIndex.clear();

    for (int i = 0; i < _sortedQuestions.length; i++) {
      String subj = _sortedQuestions[i].subject;
      if (subj.isEmpty) subj = "General";
      subj = _capitalize(subj);

      if (!_subjectStartIndex.containsKey(subj)) {
        _subjectStartIndex[subj] = i;
        _subjects.add(subj);
      }
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
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
    switch (t) {
      case QuestionType.singleCorrect: return 1;
      case QuestionType.oneOrMoreOptionsCorrect: return 2;
      case QuestionType.numerical: return 3;
      default: return 4;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    _pageController.dispose();
    _paletteController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _triggerLocalSave();
    }
  }

  Future<void> _triggerLocalSave() async {
    Map<String, ResponseObject> currentResponses = _buildResponseMap();
    await _localSessionService.saveSession(
      assignmentCode: widget.assignmentCode,
      mode: widget.testMode == TestMode.test ? 'Test' : 'Practice',
      testId: widget.sourceId,
      totalQuestions: _sortedQuestions.length,
      currentTimerValue: _overallTimeCounter.inSeconds,
      currentQuestionIndex: _currentPage,
      responses: currentResponses,
    );
  }

  // --- Flatten List to String for DB compatibility ---
  Map<String, ResponseObject> _buildResponseMap() {
    Map<String, ResponseObject> responses = {};
    for (int i = 0; i < _sortedQuestions.length; i++) {
      final question = _sortedQuestions[i];
      final state = _answerStates[i]!;
      final int totalTimeSpent = (_accumulatedTime[i] ?? 0) + (_timeTrackers[i]?.elapsed.inSeconds ?? 0);

      String statusString = 'SKIPPED';
      if (state.status == AnswerStatus.answered) {
        statusString = 'ANSWERED';
      } else if (state.status == AnswerStatus.markedForReview) statusString = 'REVIEW';
      else if (state.status == AnswerStatus.answeredAndMarked) statusString = 'REVIEW_ANSWERED';

      dynamic finalAnswer = state.userAnswer;
      if (finalAnswer is List) {
        finalAnswer = finalAnswer.join(',');
      }

      responses[question.id] = ResponseObject(
        status: statusString,
        selectedOption: finalAnswer,
        correctOption: question.actualCorrectAnswers.join(","),
        timeSpent: totalTimeSpent,
        visitCount: _visitCounts[i] ?? 0,
        q_no: i + 1,
        exam: question.exam,
        subject: question.subject,
        chapter: question.chapter,
        topic: question.topic,
        topicL2: question.topicL2,
        chapterId: question.chapterId,
        topicId: question.topicId,
        topicL2Id: question.topicL2Id,
        pyq: question.isPyq ? 'Yes' : 'No',
        difficultyTag: question.difficulty,
        // questionType and marksObtained will be filled during Submit
        imageUrl: question.imageUrl,
        solutionUrl: question.solutionUrl,
      );
    }
    return responses;
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) return;
      if (mounted) {
        setState(() {
          if (widget.testMode == TestMode.test) {
            if (_overallTimeCounter.inSeconds > 0) {
              _overallTimeCounter -= const Duration(seconds: 1);
            } else {
              _timer.cancel();
              _handleSubmit();
            }
          } else {
            _overallTimeCounter += const Duration(seconds: 1);
          }
        });
      }
    });
  }

  void _onPageChanged(int page, {bool fromInit = false}) {
    if (!fromInit && _timeTrackers.containsKey(_currentPage)) {
      _timeTrackers[_currentPage]!.stop();
    }
    setState(() {
      _currentPage = page;
      _isAnswerChecked = false;
      _visitCounts[page] = (_visitCounts[page] ?? 0) + 1;

      // Update Subject Tab
      if (page < _sortedQuestions.length) {
        String s = _sortedQuestions[page].subject;
        if(s.isEmpty) s = "General";
        _currentSubject = _capitalize(s);
      }

      if (_answerStates[page]?.status == AnswerStatus.notVisited) {
        _answerStates[page]?.status = AnswerStatus.notAnswered;
      }
    });

    if (_paletteController.hasClients) {
      double targetOffset = (page * 60.0) - (MediaQuery.of(context).size.width / 2) + 30;
      if (targetOffset < 0) targetOffset = 0;
      _paletteController.animateTo(targetOffset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }

    if (_timeTrackers.containsKey(page)) {
      _timeTrackers[page]!.start();
    }
    if (!fromInit) _triggerLocalSave();
  }

  void _togglePauseState() {
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _timeTrackers[_currentPage]?.stop();
      _triggerLocalSave();
    } else {
      _timeTrackers[_currentPage]?.start();
    }
  }

  // --- UPDATED: Check Answer Logic ---
  bool _checkEquality(dynamic userAns, dynamic correctAns) {
    if (userAns == null || correctAns == null) return false;

    // Normalize User Answer
    List<String> uList = [];
    if (userAns is String) {
      uList = [userAns];
    } else if (userAns is List) uList = List<String>.from(userAns);
    else if (userAns is num) uList = [userAns.toString()];
    else return false;

    // Normalize Correct Answer
    List<String> cList = [];
    if (correctAns is String) {
      cList = [correctAns];
    } else if (correctAns is List) cList = List<String>.from(correctAns);
    else if (correctAns is num) cList = [correctAns.toString()];

    // Compare
    final uSet = uList.map((e) => e.toString().trim().toUpperCase()).where((e) => e.isNotEmpty).toSet();
    final cSet = cList.map((e) => e.toString().trim().toUpperCase()).where((e) => e.isNotEmpty).toSet();

    if (uSet.isEmpty || cSet.isEmpty) return false;
    return uSet.length == cSet.length && uSet.containsAll(cSet);
  }

  void _checkAnswer() {
    final state = _answerStates[_currentPage]!;
    bool isEmpty = false;
    // Check if input is truly empty
    if (state.userAnswer == null) isEmpty = true;
    if (state.userAnswer is String && (state.userAnswer as String).isEmpty) isEmpty = true;
    if (state.userAnswer is List && (state.userAnswer as List).isEmpty) isEmpty = true;

    if (isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select an answer first!")));
      }
      return;
    }
    setState(() {
      _isAnswerChecked = true;
    });
    _triggerLocalSave();
  }

  // ===========================================================================
  // _handleSubmit (ROBUST VERSION)
  // Description: Includes safety checks for empty correct answers to prevent crashes.
  // ===========================================================================
  void _handleSubmit() async {
    print("DEBUG: >>> _handleSubmit Triggered");

    _timer.cancel();
    for (var sw in _timeTrackers.values) {
      sw.stop();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. Build Responses (sanitized)
      Map<String, ResponseObject> sanitizedResponses = _buildResponseMap();
      print("DEBUG: Responses built. Count: ${sanitizedResponses.length}");

      int correctCount = 0;
      int incorrectCount = 0;
      int skippedCount = 0;
      num totalScore = 0;

      // [NEW] Rich Analytics Breakdown Structure
      Map<String, dynamic> marksBreakdown = {
        "Overall": <String, dynamic>{"maxMarks": 0.0, "marksObtained": 0.0}
      };

      print("DEBUG: Step 2 - Starting Scoring Loop. Total Questions: ${_sortedQuestions.length}");

      // 2. Run Scoring Engine on Sorted Questions
      for (var i = 0; i < _sortedQuestions.length; i++) {
        final q = _sortedQuestions[i];

        final response = sanitizedResponses[q.id];
        if (response == null) continue;

        // Get Config
        final config = _activeMarkingSchemes[q.type] ?? MarkingConfiguration.jeeMain();

        // ---------------------------------------------------------
        // CRITICAL FIX: Check if question has correct answers
        // ---------------------------------------------------------
        if (q.actualCorrectAnswers.isEmpty) {
          print("CRITICAL WARNING: QID ${q.id} has NO CORRECT ANSWERS defined in DB.");
          print("ACTION: Skipping scoring for this question to prevent crash.");

          // Treat as 0 Marks / Skipped / Bonus
          sanitizedResponses[q.id] = response.copyWith(
            status: QuestionStatus.skipped,
            questionType: _mapTypeToString(q.type),
            marksObtained: 0,
          );
          continue; // SKIP to next question
        }
        // ---------------------------------------------------------

        // Calculate
        final result = UniversalScoringEngine.calculateScore(
          questionType: q.type,
          userResponse: response.selectedOption,
          correctAnswers: q.actualCorrectAnswers,
          config: config,
        );

        totalScore += result.score;
        String finalStatus = result.status;

        // Manual override for empty inputs
        if (response.selectedOption == null) finalStatus = QuestionStatus.skipped;
        if (response.selectedOption is String && (response.selectedOption as String).isEmpty) finalStatus = QuestionStatus.skipped;
        if (response.selectedOption is List && (response.selectedOption as List).isEmpty) finalStatus = QuestionStatus.skipped;

        // --- AGGREGATION LOGIC ---
        String subject = q.subject.isEmpty ? "General" : q.subject;
        String typeStr = _mapTypeToString(q.type);
        double qMaxMarks = config.correctScore;

        // A. Ensure Subject Keys Exist with correct Dynamic Type
        if (!marksBreakdown.containsKey(subject)) {
          marksBreakdown[subject] = <String, dynamic>{"maxMarks": 0.0, "marksObtained": 0.0};
        }

        // B. Ensure Type Keys Exist inside Subject
        if (!marksBreakdown[subject].containsKey(typeStr)) {
          marksBreakdown[subject][typeStr] = <String, dynamic>{"maxMarks": 0.0, "marksObtained": 0.0};
        }

        // C. Update Totals (Using Inner Maps)
        marksBreakdown[subject]["maxMarks"] += qMaxMarks;
        marksBreakdown[subject]["marksObtained"] += result.score;

        marksBreakdown[subject][typeStr]["maxMarks"] += qMaxMarks;
        marksBreakdown[subject][typeStr]["marksObtained"] += result.score;

        marksBreakdown["Overall"]["maxMarks"] += qMaxMarks;
        marksBreakdown["Overall"]["marksObtained"] += result.score;

        // [NEW] Inject Type and Marks into Response
        sanitizedResponses[q.id] = response.copyWith(
          status: finalStatus,
          questionType: typeStr,
          marksObtained: result.score,
        );

        if (finalStatus == QuestionStatus.correct || finalStatus == QuestionStatus.partiallyCorrect) {
          correctCount++;
        } else if (finalStatus == QuestionStatus.incorrect) {
          incorrectCount++;
        } else {
          skippedCount++;
        }
      }

      print("DEBUG: Step 3 - Loop Finished. Total Score: $totalScore");

      // Prepare Schemes for Storage
      Map<String, dynamic> schemesMapForStorage = {};
      _activeMarkingSchemes.forEach((key, value) {
        schemesMapForStorage[_mapTypeToString(key)] = value.toMap();
      });

      final int maxMarks = _sortedQuestions.length * 4;
      final int finalTime = widget.testMode == TestMode.test
          ? (Duration(minutes: widget.timeLimitInMinutes) - _overallTimeCounter).inSeconds
          : _overallTimeCounter.inSeconds;

      print("DEBUG: Step 4 - Calling Service submitAttempt...");

      // 3. Submit
      final enrichedAttempt = await TestOrchestrationService().submitAttempt(
        sourceId: widget.sourceId,
        assignmentCode: widget.assignmentCode,
        title: widget.title,
        onlySingleAttempt: widget.onlySingleAttempt,
        mode: widget.testMode == TestMode.test ? 'Test' : 'Practice',
        questions: _sortedQuestions,
        score: totalScore,
        timeTakenSeconds: finalTime,
        responses: sanitizedResponses,
        timeLimitMinutes: widget.testMode == TestMode.test ? widget.timeLimitInMinutes : null,

        // Pass Analytics Data
        markingSchemes: schemesMapForStorage,
        marksBreakdown: marksBreakdown,
      );

      print("DEBUG: Step 5 - Service Call Complete.");

      if (mounted) {
        Navigator.pop(context); // Close Loader

        if (enrichedAttempt != null) {
          await _localSessionService.clearSession();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ResultsScreen(
                // [FIXED] Updated to use the new Refactored Wrapper Constructor
                result: TestResult(
                  attempt: enrichedAttempt,
                  questions: _sortedQuestions,
                  answerStates: _answerStates,
                ),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error uploading. Results saved locally.")));
        }
      }
    } catch (e, stackTrace) {
      print("CRITICAL FAILURE IN _handleSubmit");
      print("ERROR: $e");
      print("STACK TRACE: $stackTrace");

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Submission Error: $e"),
            duration: const Duration(seconds: 10)
        ));
      }
    }
  }

  String _mapTypeToString(QuestionType type) {
    switch (type) {
      case QuestionType.singleCorrect: return 'Single Correct';
      case QuestionType.numerical: return 'Numerical type';
      case QuestionType.oneOrMoreOptionsCorrect: return 'One or more options correct';
      case QuestionType.matrixSingle: return 'Single Matrix Match';
      case QuestionType.matrixMulti: return 'Multi Matrix Match';
      default: return 'Unknown';
    }
  }

  // --- RESTORED: Detailed Pause Dialog ---
  void _showPauseDialog() {
    _togglePauseState();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: const [
              Icon(Icons.pause_circle_filled, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Paused'),
            ],
          ),
          content: const Text(
            'Test timer is paused. Click Resume to continue.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _togglePauseState();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Resume',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- RESTORED: Detailed Submit Confirmation ---
  Future<void> _showSubmitConfirmationDialog() async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Test'),
        content: const Text('Are you sure you want to finish the test?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleSubmit();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // --- RESTORED: Detailed Quit Dialog ---
  Future<bool> _onWillPop() async {
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quit Test?'),
        content: const Text('If you quit now, your progress will be saved locally. You can resume later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, Resume')),
          TextButton(
            onPressed: () {
              _triggerLocalSave().then((_) => Navigator.pop(ctx, true));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Quit (Save & Exit)'),
          ),
        ],
      ),
    );
    return shouldPop ?? false;
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () async {
              final shouldExit = await _onWillPop();
              if (shouldExit && context.mounted) Navigator.of(context).pop();
            },
          ),
          title: _buildOverallTimerWidget(),
          actions: [
            if (widget.testMode == TestMode.practice)
              IconButton(
                onPressed: _showPauseDialog,
                icon: const Icon(Icons.pause_circle_filled, color: Colors.white),
                tooltip: "Pause",
              ),
            TextButton(
              onPressed: _showSubmitConfirmationDialog,
              child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // NEW: Subject Tabs
            _buildSubjectTabs(),

            // Reused Palette
            _buildNTAQuestionPalette(),
            const Divider(height: 1),

            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: _isPaused
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(),
                onPageChanged: (index) => _onPageChanged(index),
                itemCount: _sortedQuestions.length,
                itemBuilder: (context, index) {
                  final q = _sortedQuestions[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Q.${index + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            // NEW: Marking Badge
                            _buildMarkingBadge(q),
                            _buildQuestionTimerWidget(index),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // NEW: Type Label
                        Text(_getQuestionTypeLabel(q.type), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                        const SizedBox(height: 10),

                        if (q.imageUrl.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ExpandableImage(imageUrl: q.imageUrl),
                          ),
                        const SizedBox(height: 20),

                        QuestionInputWidget(
                          question: q,
                          currentAnswer: _answerStates[index]?.userAnswer,
                          onAnswerChanged: (newAnswer) {
                            if (!_isPaused) {
                              setState(() {
                                _answerStates[index]?.userAnswer = newAnswer;
                                if (widget.testMode == TestMode.practice) {
                                  _isAnswerChecked = false;
                                }
                              });
                            }
                          },
                        ),

                        if (widget.testMode == TestMode.practice && _isAnswerChecked)
                          _buildFeedbackUI(q),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  // --- UPDATED: Feedback with Partial Correctness ---
  Widget _buildFeedbackUI(Question q) {
    final userAns = _answerStates[_currentPage]?.userAnswer;

    // Normalize User Answer
    List<String> uList = [];
    if (userAns is List) {
      uList = List<String>.from(userAns);
    } else if (userAns is String) uList = userAns.split(',');

    // Normalize Correct Answer
    List<String> cList = q.actualCorrectAnswers;

    String status = "Incorrect";
    Color color = Colors.red;
    IconData icon = Icons.cancel;

    final uSet = uList.map((e) => e.trim()).toSet();
    final cSet = cList.map((e) => e.trim()).toSet();

    if (uSet.length == cSet.length && uSet.containsAll(cSet)) {
      status = "Correct!";
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (q.type == QuestionType.oneOrMoreOptionsCorrect) {
      // Check for Partial
      bool hasWrongSelection = uList.any((e) => !cList.contains(e));
      if (!hasWrongSelection && uList.isNotEmpty) {
        status = "Partially Correct";
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Text(status, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: _showSolution, child: const Text("View Full Solution")),
        ],
      ),
    );
  }

  void _showSolution() {
    final q = _sortedQuestions[_currentPage];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Solution", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 10),
            Text("Correct Answer: ${q.actualCorrectAnswers.join(", ")}",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 10),
            if (q.solutionUrl != null)
              Expanded(child: Center(child: ExpandableImage(imageUrl: q.solutionUrl!)))
            else
              const Text("No image solution available."),
          ],
        ),
      ),
    );
  }

  // --- NEW: Subject Tabs Widget ---
  Widget _buildSubjectTabs() {
    return Container(
      color: Colors.deepPurple.shade50,
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _subjects.length,
        itemBuilder: (context, index) {
          final subject = _subjects[index];
          final isSelected = _currentSubject == subject;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(subject, style: TextStyle(color: isSelected ? Colors.white : Colors.black87)),
              selected: isSelected,
              selectedColor: Colors.deepPurple,
              backgroundColor: Colors.white,
              onSelected: (bool selected) {
                if (selected) {
                  final targetIndex = _subjectStartIndex[subject] ?? 0;
                  _pageController.jumpToPage(targetIndex);
                }
              },
            ),
          );
        },
      ),
    );
  }

  // --- NEW: Marking Badge Widget ---
  Widget _buildMarkingBadge(Question q) {
    final config = _activeMarkingSchemes[q.type] ?? MarkingConfiguration.jeeMain();

    String correct = config.correctScore.toString().replaceAll('.0', '');
    String incorrect = config.incorrectScore.toString().replaceAll('.0', '');
    String scheme = "+$correct, $incorrect";

    Color color = Colors.green;
    if (config.incorrectScore <= -2) color = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(scheme, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }

  String _getQuestionTypeLabel(QuestionType type) {
    switch (type) {
      case QuestionType.singleCorrect: return "Single Correct";
      case QuestionType.oneOrMoreOptionsCorrect: return "One or more options correct";
      case QuestionType.numerical: return "Numerical";
      default: return "";
    }
  }

  // --- RESTORED: Standard Widgets (Bottom Bar, Timer, etc.) ---

  Widget _buildOverallTimerWidget() {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(_overallTimeCounter.inMinutes.remainder(60));
    final seconds = twoDigits(_overallTimeCounter.inSeconds.remainder(60));
    final hours = twoDigits(_overallTimeCounter.inHours);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade700,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        "$hours:$minutes:$seconds",
        style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildQuestionTimerWidget(int index) {
    final currentElapsed = _timeTrackers[index]?.elapsed.inSeconds ?? 0;
    final totalSeconds = (_accumulatedTime[index] ?? 0) + currentElapsed;
    final duration = Duration(seconds: totalSeconds);

    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_filled, size: 16, color: Colors.black54),
          const SizedBox(width: 5),
          Text(
            "$minutes:$seconds",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildNTAQuestionPalette() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: ListView.builder(
        controller: _paletteController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _sortedQuestions.length,
        itemBuilder: (context, index) {
          final state = _answerStates[index]!;
          final isCurrent = index == _currentPage;
          BoxShape shape = BoxShape.rectangle;
          Color fillColor = Colors.white;
          Color textColor = Colors.black;
          Border? border = Border.all(color: Colors.grey.shade300);
          Widget? badge;

          switch (state.status) {
            case AnswerStatus.notVisited:
              fillColor = Colors.white;
              textColor = Colors.black;
              border = Border.all(color: Colors.grey.shade400);
              shape = BoxShape.rectangle;
              break;
            case AnswerStatus.notAnswered:
              fillColor = Colors.red.shade600;
              textColor = Colors.white;
              border = null;
              shape = BoxShape.rectangle;
              break;
            case AnswerStatus.answered:
              fillColor = Colors.green.shade600;
              textColor = Colors.white;
              border = null;
              shape = BoxShape.rectangle;
              break;
            case AnswerStatus.markedForReview:
              fillColor = Colors.purple.shade700;
              textColor = Colors.white;
              border = null;
              shape = BoxShape.circle;
              break;
            case AnswerStatus.answeredAndMarked:
              fillColor = Colors.purple.shade700;
              textColor = Colors.white;
              border = null;
              shape = BoxShape.circle;
              badge = Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 12, color: Colors.green),
                ),
              );
              break;
          }

          return GestureDetector(
            onTap: () => _pageController.jumpToPage(index),
            child: Container(
              width: 50,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: fillColor,
                      shape: shape,
                      border: isCurrent
                          ? Border.all(color: Colors.blueAccent, width: 3)
                          : border,
                      borderRadius: shape == BoxShape.rectangle
                          ? BorderRadius.circular(4)
                          : null,
                      boxShadow: isCurrent
                          ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 4, spreadRadius: 1)]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        "${index + 1}",
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  if (badge != null) badge,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.grey.shade200, blurRadius: 4, offset: const Offset(0, -2))
          ]
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.testMode == TestMode.practice)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _checkAnswer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Check Answer"),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleSaveAndMarkForReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.purple,
                    side: const BorderSide(color: Colors.purple),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text("Save & Mark Review",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleMarkForReviewAndNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.purple,
                    side: const BorderSide(color: Colors.purple),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text("Mark Review & Next",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _handleClearResponse,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text("Clear", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleSaveAndNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Save & Next", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleSaveAndNext() {
    final state = _answerStates[_currentPage]!;
    bool hasAnswer = false;
    if (state.userAnswer is List) {
      hasAnswer = (state.userAnswer as List).isNotEmpty;
    } else if (state.userAnswer is String) hasAnswer = (state.userAnswer as String).isNotEmpty;

    if (hasAnswer) {
      setState(() => state.status = AnswerStatus.answered);
    } else {
      setState(() => state.status = AnswerStatus.notAnswered);
    }

    _triggerLocalSave().then((_) { if (mounted) _moveToNextPage(); });
  }

  void _handleSaveAndMarkForReview() {
    final state = _answerStates[_currentPage]!;
    bool hasAnswer = false;
    if (state.userAnswer is List) {
      hasAnswer = (state.userAnswer as List).isNotEmpty;
    } else if (state.userAnswer is String) hasAnswer = (state.userAnswer as String).isNotEmpty;

    if (hasAnswer) {
      setState(() => state.status = AnswerStatus.answeredAndMarked);
      _triggerLocalSave().then((_) { if (mounted) _moveToNextPage(); });
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select an answer to Save & Mark for Review")));
    }
  }

  void _handleMarkForReviewAndNext() {
    setState(() => _answerStates[_currentPage]!.status = AnswerStatus.markedForReview);
    _triggerLocalSave().then((_) { if (mounted) _moveToNextPage(); });
  }

  void _handleClearResponse() {
    setState(() {
      _answerStates[_currentPage]!.userAnswer = null;
      _answerStates[_currentPage]!.status = AnswerStatus.notAnswered;
      _isAnswerChecked = false;
    });
    _triggerLocalSave();
  }

  void _moveToNextPage() {
    if (_currentPage < _sortedQuestions.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are on the last question. Click Submit to finish.")));
    }
  }
}