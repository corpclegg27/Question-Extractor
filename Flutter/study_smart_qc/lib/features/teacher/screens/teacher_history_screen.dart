// lib/features/teacher/screens/teacher_history_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/services/teacher_service.dart';
// IMPORT THE NEW SCREEN
import 'package:study_smart_qc/features/teacher/screens/curation_management_screen.dart';

class TeacherHistoryScreen extends StatelessWidget {
  const TeacherHistoryScreen({super.key});

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
              final docId = docs[index].id; // Capture the Doc ID for navigation
              final data = docs[index].data() as Map<String, dynamic>;

              final String title = data['title'] ?? 'Untitled';
              final String code = data['assignmentCode'] ?? '----';
              final String status = data['status'] ?? 'assigned';
              final bool isStrict = data['onlySingleAttempt'] ?? false;
              final int questionCount = (data['questionIds'] as List?)?.length ?? 0;

              // Format Date
              final Timestamp? ts = data['createdAt'];
              final String dateStr = ts != null
                  ? DateFormat('MMM d, yyyy').format(ts.toDate())
                  : 'Unknown Date';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("$questionCount Questions • $dateStr"),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildStatusChip(status),
                          const SizedBox(width: 8),
                          if (isStrict)
                            _buildMiniLabel("STRICT", Colors.red.shade100, Colors.red.shade800),
                        ],
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("CODE", style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text(
                        code,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: Colors.deepPurple
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    // Navigate to the Management Screen
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
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color = Colors.grey.shade100;
    Color textColor = Colors.black87;

    if (status == 'submitted') {
      color = Colors.green.shade100;
      textColor = Colors.green.shade800;
    } else if (status == 'assigned') {
      color = Colors.blue.shade100;
      textColor = Colors.blue.shade800;
    }

    return _buildMiniLabel(status.toUpperCase(), color, textColor);
  }

  Widget _buildMiniLabel(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}