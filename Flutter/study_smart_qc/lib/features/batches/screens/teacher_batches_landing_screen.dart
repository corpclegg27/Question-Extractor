// lib/features/batches/screens/teacher_batches_landing_screen.dart
// Description: Gateway for Batch Management.
// Options: Create New Batch, Manage Existing Batch.
// UPDATED: Linked 'Manage Existing Batches' to TeacherViewAllBatches.

import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/batches/screens/teacher_create_batch_screen.dart';
import 'package:study_smart_qc/features/batches/screens/teacher_view_all_batches.dart';

class TeacherBatchesLandingScreen extends StatelessWidget {
  const TeacherBatchesLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Batches", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.groups_outlined, size: 80, color: Colors.deepPurple),
            const SizedBox(height: 16),
            const Text(
              "Manage Your Batches",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Organize students into groups for easier assignment distribution and tracking.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 48),

            // Button 1: Create New
            _buildActionButton(
              context,
              icon: Icons.add_circle_outline,
              label: "Create New Batch",
              color: const Color(0xFF6200EA),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TeacherCreateBatchScreen()),
                );
              },
            ),
            const SizedBox(height: 16),

            // Button 2: Manage Existing (UPDATED)
            _buildActionButton(
              context,
              icon: Icons.edit_note,
              label: "Manage Existing Batches",
              color: Colors.grey.shade800,
              isOutlined: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TeacherViewAllBatches()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
        required VoidCallback onTap,
        bool isOutlined = false,
      }) {
    return SizedBox(
      height: 56,
      child: isOutlined
          ? OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      )
          : ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}