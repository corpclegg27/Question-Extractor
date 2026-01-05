import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/analytics/widgets/attempt_list_widget.dart';

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Number of tabs
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            "Performance Analysis",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: [
              Tab(
                icon: Icon(Icons.school_outlined),
                text: "Assignments",
              ),
              Tab(
                icon: Icon(Icons.timer_outlined),
                text: "Tests",
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            // Tab 1: Practice Assignments
            AttemptListWidget(filterMode: 'Practice'),

            // Tab 2: Strict Tests
            AttemptListWidget(filterMode: 'Test'),
          ],
        ),
      ),
    );
  }
}