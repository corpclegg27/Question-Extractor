// lib/features/batches/screens/teacher_view_specific_batch.dart
// Description: Tabbed view for a specific batch.
// Tabs: 'Tests and assignments', 'Manage batch'.

import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/batch_model.dart';

class TeacherViewSpecificBatch extends StatefulWidget {
  final BatchModel batch;

  const TeacherViewSpecificBatch({super.key, required this.batch});

  @override
  State<TeacherViewSpecificBatch> createState() => _TeacherViewSpecificBatchState();
}

class _TeacherViewSpecificBatchState extends State<TeacherViewSpecificBatch> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.batch.batchName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Color(0xFF6200EA),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFF6200EA),
            tabs: [
              Tab(text: "Tests & Assignments"),
              Tab(text: "Manage Batch"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            // Tab 1: Tests & Assignments (Placeholder)
            Center(
              child: Text("Assignments List will go here", style: TextStyle(color: Colors.grey)),
            ),

            // Tab 2: Manage Batch (Placeholder)
            Center(
              child: Text("Add/Remove Students & Teachers here", style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}