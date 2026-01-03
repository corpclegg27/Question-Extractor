import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/services/onboarding_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final OnboardingService _onboardingService = OnboardingService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Loading States
  bool _isFetchingOptions = true;
  bool _isSubmitting = false;

  // Data Options (Fetched from Firestore)
  List<String> _examsList = [];
  List<String> _classesList = [];
  List<String> _subjectsList = [];
  List<int> _targetYears = [];

  // Form State - Student
  String? _selectedExam;
  String? _selectedClass;
  int? _selectedYear;

  // Form State - Teacher
  final List<String> _teacherSelectedExams = [];
  final List<String> _teacherSelectedSubjects = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchOptions();
  }

  Future<void> _fetchOptions() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('static_data')
          .doc('option_sets')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _examsList = List<String>.from(data['exams_list'] ?? []);
          _classesList = List<String>.from(data['classes_list'] ?? []);
          _subjectsList = List<String>.from(data['subjects_list'] ?? []);
          _targetYears = List<int>.from(data['target_years'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading options: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingOptions = false);
      }
    }
  }

  Future<void> _handleSubmit() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      final isStudent = _tabController.index == 0;
      final role = isStudent ? 'student' : 'teacher';
      Map<String, dynamic> profileData = {};

      if (isStudent) {
        // Validate Student Form
        if (_selectedExam == null ||
            _selectedClass == null ||
            _selectedYear == null) {
          throw Exception("Please fill all fields.");
        }
        profileData = {
          'targetExam': _selectedExam,
          'currentClass': _selectedClass,
          'targetYear': _selectedYear,
        };
      } else {
        // Validate Teacher Form
        if (_teacherSelectedExams.isEmpty ||
            _teacherSelectedSubjects.isEmpty) {
          throw Exception("Please select at least one exam and one subject.");
        }
        profileData = {
          'teachingExams': _teacherSelectedExams,
          'teachingSubjects': _teacherSelectedSubjects,
        };
      }

      // Call Service
      await _onboardingService.completeOnboarding(
        uid: user.uid,
        role: role,
        profileData: profileData,
      );

      // No manual navigation needed here; AuthWrapper will react to the data change.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetchingOptions) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Welcome to StudySmart"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "I'm a Student", icon: Icon(Icons.school)),
            Tab(text: "I'm a Teacher", icon: Icon(Icons.person_outline)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStudentForm(),
          _buildTeacherForm(),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2),
          )
              : const Text("Complete Profile", style: TextStyle(fontSize: 18)),
        ),
      ),
    );
  }

  Widget _buildStudentForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Help us personalize your learning path.",
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 30),
          _buildDropdown(
            label: "Target Exam",
            value: _selectedExam,
            items: _examsList,
            onChanged: (val) => setState(() => _selectedExam = val),
          ),
          const SizedBox(height: 20),
          _buildDropdown(
            label: "Current Class",
            value: _selectedClass,
            items: _classesList,
            onChanged: (val) => setState(() => _selectedClass = val),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            // FIX: Using initialValue instead of value
            initialValue: _selectedYear,
            decoration: const InputDecoration(
              labelText: "Target Exam Year",
              border: OutlineInputBorder(),
            ),
            items: _targetYears
                .map((year) => DropdownMenuItem(
              value: year,
              child: Text(year.toString()),
            ))
                .toList(),
            onChanged: (val) => setState(() => _selectedYear = val),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Tell us about your teaching expertise.",
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 30),
          const Text("Exams you teach:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8.0,
            children: _examsList.map((exam) {
              final isSelected = _teacherSelectedExams.contains(exam);
              return FilterChip(
                label: Text(exam),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    selected
                        ? _teacherSelectedExams.add(exam)
                        : _teacherSelectedExams.remove(exam);
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 30),
          const Text("Subjects:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8.0,
            children: _subjectsList.map((subject) {
              final isSelected = _teacherSelectedSubjects.contains(subject);
              return FilterChip(
                label: Text(subject),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    selected
                        ? _teacherSelectedSubjects.add(subject)
                        : _teacherSelectedSubjects.remove(subject);
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      // FIX: Using initialValue instead of value
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items
          .map((item) => DropdownMenuItem(
        value: item,
        child: Text(item),
      ))
          .toList(),
      onChanged: onChanged,
    );
  }
}