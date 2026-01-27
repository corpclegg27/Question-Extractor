// lib/features/batches/screens/teacher_view_all_batches.dart
// Description: Lists all batches the teacher belongs to.
// Links to TeacherViewSpecificBatch.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/batches/screens/teacher_view_specific_batch.dart';
import 'package:study_smart_qc/features/batches/widgets/batch_display_card.dart';
import 'package:study_smart_qc/models/batch_model.dart';
import 'package:study_smart_qc/services/batch_service.dart';

class TeacherViewAllBatches extends StatefulWidget {
  const TeacherViewAllBatches({super.key});

  @override
  State<TeacherViewAllBatches> createState() => _TeacherViewAllBatchesState();
}

class _TeacherViewAllBatchesState extends State<TeacherViewAllBatches> {
  final BatchService _batchService = BatchService();
  bool _isLoading = true;
  List<BatchModel> _batches = [];

  @override
  void initState() {
    super.initState();
    _fetchBatches();
  }

  Future<void> _fetchBatches() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final batches = await _batchService.getBatchesForTeacher(uid);
      if (mounted) {
        setState(() {
          _batches = batches;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text("My Batches", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _batches.length,
        itemBuilder: (context, index) {
          final batch = _batches[index];
          return BatchDisplayCard(
            batch: batch,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TeacherViewSpecificBatch(batch: batch),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "No batches found",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          const Text(
            "Create a new batch to get started.",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}