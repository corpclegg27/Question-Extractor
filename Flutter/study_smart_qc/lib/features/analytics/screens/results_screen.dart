import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/widgets/solution_detail_sheet.dart';

class ResultsScreen extends StatefulWidget {
  final TestResult result;

  const ResultsScreen({super.key, required this.result});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int correctCount = 0;
  int incorrectCount = 0;
  int unattemptedCount = 0;

  int marksObtained = 0;
  double accuracy = 0.0;
  double attemptPercentage = 0.0;

  @override
  void initState() {
    super.initState();
    _calculateResults();
  }

  void _calculateResults() {
    int tempCorrect = 0;
    int tempIncorrect = 0;
    int tempSkipped = 0;

    // Prefer using the detailed 'responses' map if available
    if (widget.result.responses.isNotEmpty) {
      widget.result.responses.forEach((key, response) {
        switch (response.status) {
          case 'CORRECT':
            tempCorrect++;
            break;
          case 'INCORRECT':
            tempIncorrect++;
            break;
          case 'REVIEW':
          // "Marked for Review" without answer counts as SKIPPED
            tempSkipped++;
            break;
          default: // SKIPPED
            tempSkipped++;
            break;
        }
      });
      // Adjust for questions missing from responses map (pure skips)
      int totalTracked = tempCorrect + tempIncorrect + tempSkipped;
      if (totalTracked < widget.result.questions.length) {
        tempSkipped += (widget.result.questions.length - totalTracked);
      }
    } else {
      // Fallback Logic (if responses map is empty)
      widget.result.answerStates.forEach((index, state) {
        if (state.status == AnswerStatus.answered || state.status == AnswerStatus.answeredAndMarked) {
          final question = widget.result.questions[index];
          final userAnswer = state.userAnswer;
          if (userAnswer != null && userAnswer.trim().toLowerCase() == question.correctAnswer.trim().toLowerCase()) {
            tempCorrect++;
          } else {
            tempIncorrect++;
          }
        } else {
          // Not Visited, Not Answered, or Marked For Review (without answer) -> Skipped
          tempSkipped++;
        }
      });
    }

    setState(() {
      correctCount = tempCorrect;
      incorrectCount = tempIncorrect;
      unattemptedCount = tempSkipped;

      final totalAttempted = correctCount + incorrectCount;

      marksObtained = (correctCount * 4) - (incorrectCount * 1);
      accuracy = (totalAttempted > 0) ? (correctCount / totalAttempted) * 100 : 0.0;
      attemptPercentage = (widget.result.questions.isNotEmpty)
          ? (totalAttempted / widget.result.questions.length) * 100
          : 0.0;
    });
  }

  void _showSolutionSheet(int initialIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          child: SolutionDetailSheet(
            result: widget.result,
            initialIndex: initialIndex,
          ),
        );
      },
    );
  }

  String get _formattedTimeTaken {
    final minutes = widget.result.timeTaken.inMinutes.toString().padLeft(2, '0');
    final seconds = (widget.result.timeTaken.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Analysis'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildScoreCard(),
            const SizedBox(height: 20),
            _buildStatsRow(),
            const SizedBox(height: 20),
            _buildVisualAnalysis(),
            const SizedBox(height: 20),
            _buildReviewSolutionsGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    double percentage = (marksObtained / widget.result.totalMarks) * 100;
    String motivation = percentage >= 75 ? 'Excellent Work!' : percentage >= 50 ? 'Good Effort!' : 'Keep Improving!';

    return Card(
      color: Colors.deepPurple.shade700,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text('Marks Obtained', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16)),
            const SizedBox(height: 8),
            Text('$marksObtained / ${widget.result.totalMarks}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(motivation, style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard('Accuracy', '${accuracy.toStringAsFixed(0)}%', Icons.track_changes, Colors.blue),
        _buildStatCard('Attempt %', '${attemptPercentage.toStringAsFixed(0)}%', Icons.rule, Colors.orange),
        _buildStatCard('Time Taken', _formattedTimeTaken, Icons.timer_outlined, Colors.purple),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisualAnalysis() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Performance Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: [
                    PieChartSectionData(value: correctCount.toDouble(), title: '$correctCount', color: Colors.green, radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    PieChartSectionData(value: incorrectCount.toDouble(), title: '$incorrectCount', color: Colors.red, radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    PieChartSectionData(value: unattemptedCount.toDouble(), title: '$unattemptedCount', color: Colors.grey.shade300, radius: 50, titleStyle: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Legend
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildLegendItem(Colors.green, 'Correct'),
                _buildLegendItem(Colors.red, 'Incorrect'),
                _buildLegendItem(Colors.grey.shade300, 'Skipped'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildReviewSolutionsGrid() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Question Analysis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text('Tap on a number to view solution & time spent.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 15),
            GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10
              ),
              itemCount: widget.result.questions.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final question = widget.result.questions[index];

                String statusStr = 'SKIPPED';
                if (widget.result.responses.containsKey(question.id)) {
                  statusStr = widget.result.responses[question.id]!.status;
                }

                // Map 'REVIEW' to 'SKIPPED' colors for the final grid as well
                Color color = Colors.grey.shade300;
                Color textColor = Colors.black;

                if (statusStr == 'CORRECT') {
                  color = Colors.green;
                  textColor = Colors.white;
                } else if (statusStr == 'INCORRECT') {
                  color = Colors.red;
                  textColor = Colors.white;
                } else {
                  // SKIPPED or REVIEW (without answer)
                  color = Colors.grey.shade200;
                  textColor = Colors.black;
                }

                return GestureDetector(
                  onTap: () => _showSolutionSheet(index),
                  child: Container(
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300)
                    ),
                    child: Center(
                      child: Text(
                          '${index + 1}',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.bold)
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}