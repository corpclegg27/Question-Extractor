// lib/features/student/widgets/student_assignments_list.dart
// Description: Displays assignment list. Uses robust normalized comparison for Resume status.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// WIDGETS
import 'package:study_smart_qc/features/student/widgets/student_curation_preview_card.dart';

class StudentAssignmentsList extends StatefulWidget {
  final List<QueryDocumentSnapshot> documents;
  final String? resumableAssignmentCode;
  final Future<void> Function() onResumeTap;
  final VoidCallback onViewAnalysisTap;
  final bool isHistoryMode;

  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;

  final VoidCallback? onRefreshNeeded;

  const StudentAssignmentsList({
    super.key,
    required this.documents,
    required this.resumableAssignmentCode,
    required this.onResumeTap,
    required this.onViewAnalysisTap,
    this.isHistoryMode = false,
    this.onLoadMore,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onRefreshNeeded,
  });

  @override
  State<StudentAssignmentsList> createState() => _StudentAssignmentsListState();
}

class _StudentAssignmentsListState extends State<StudentAssignmentsList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom && !widget.isLoadingMore && widget.hasMore && widget.onLoadMore != null) {
      widget.onLoadMore!();
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll - 200);
  }

  // Helper for Robust Comparison
  String _normalize(dynamic value) {
    if (value == null) return '';
    return value.toString().trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.documents.isEmpty && !widget.isLoadingMore) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              widget.isHistoryMode
                  ? "No completed assignments yet."
                  : "No pending assignments!",
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: widget.documents.length + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == widget.documents.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final doc = widget.documents[index];
        final data = doc.data() as Map<String, dynamic>;

        // Robust ID Extraction
        final String docAssignmentCode = _normalize(data['assignmentCode']);
        final String pendingCode = _normalize(widget.resumableAssignmentCode);

        final bool isStrict = data['onlySingleAttempt'] ?? false;

        // SIMPLE CHECK: Do the normalized strings match?
        final bool isResumable = (pendingCode.isNotEmpty && docAssignmentCode == pendingCode);

        return StudentCurationPreviewCard(
          snapshot: doc,
          isResumable: isResumable,
          isSubmitted: widget.isHistoryMode,
          isStrict: isStrict,
          onResumeTap: widget.onResumeTap,
          onViewAnalysisTap: widget.onViewAnalysisTap,
          onRefreshNeeded: widget.onRefreshNeeded,
        );
      },
    );
  }
}