// lib/features/teacher/screens/teacher_history_screen.dart
// Description: Lists all curations created by the teacher.
// UPDATED: Now imports and uses the new 'CloneAssignmentSheet' for batch cloning.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// SCREEN IMPORTS
import 'package:study_smart_qc/features/teacher/screens/curation_management_screen.dart';

// WIDGET IMPORTS
import 'package:study_smart_qc/features/teacher/widgets/teacher_curation_preview_card.dart';
// [CRITICAL] This is the new bottom sheet we created
import 'package:study_smart_qc/features/teacher/widgets/clone_assignment_sheet.dart';

// SERVICES
import 'package:study_smart_qc/services/teacher_service.dart';

class TeacherHistoryScreen extends StatefulWidget {
  const TeacherHistoryScreen({super.key});

  @override
  State<TeacherHistoryScreen> createState() => _TeacherHistoryScreenState();
}

class _TeacherHistoryScreenState extends State<TeacherHistoryScreen> {

  // [NEW LOGIC] Opens the CloneAssignmentSheet widget
  void _openCloneSheet(DocumentSnapshot doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Required for dynamic height
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CloneAssignmentSheet(sourceDoc: doc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teacherUid = FirebaseAuth.instance.currentUser?.uid;

    if (teacherUid == null) {
      return const Scaffold(body: Center(child: Text("Authentication Error")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Curations"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: TeacherService().getTeacherCurations(teacherUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("No curations found.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final DocumentSnapshot doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final String title = data['title'] ?? 'Untitled';
              final String docId = doc.id;

              return TeacherCurationPreviewCard(
                doc: doc,
                // Navigate to Details
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CurationManagementScreen(
                        curationId: docId,
                        title: title,
                      ),
                    ),
                  );
                },
                // [ACTION] This triggers the NEW bottom sheet
                onClone: () => _openCloneSheet(doc),
              );
            },
          );
        },
      ),
    );
  }
}