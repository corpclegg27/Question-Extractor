// lib/widgets/student_lookup_sheet.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/analytics/screens/analysis_screen.dart';

class StudentLookupSheet extends StatefulWidget {
  const StudentLookupSheet({super.key});

  @override
  State<StudentLookupSheet> createState() => _StudentLookupSheetState();
}

class _StudentLookupSheetState extends State<StudentLookupSheet> {
  final TextEditingController _idController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _findAndOpenStudent() async {
    final idStr = _idController.text.trim();
    if (idStr.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final int studentId = int.parse(idStr);

      // Query Firestore: Find user where 'studentId' == the number entered
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('studentId', isEqualTo: studentId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() => _error = "Student ID $studentId not found.");
      } else {
        final uid = query.docs.first.id;
        final data = query.docs.first.data();
        final name = data['displayName'] ?? "Student";

        if (mounted) {
          Navigator.pop(context); // Close the bottom sheet

          // Open Analysis Screen with the found UID
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AnalysisScreen(targetStudentUid: uid),
            ),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Viewing reports for $name")),
          );
        }
      }
    } catch (e) {
      setState(() => _error = "Invalid ID format or Network Error");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Handle keyboard covering the field
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Inspect Student Performance",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Enter the unique Student ID to view their full analytics.",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _idController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: "Enter Student ID (e.g. 10)",
              border: const OutlineInputBorder(),
              errorText: _error,
              prefixIcon: const Icon(Icons.person_search),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _findAndOpenStudent,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("View Reports"),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}