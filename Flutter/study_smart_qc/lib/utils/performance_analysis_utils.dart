// lib/utils/performance_analysis_utils.dart

// 1. Define the Quadrants
enum PerformanceQuadrant {
  mastery,      // Correct & Fast
  needsSpeed,   // Correct & Slow
  learningGap,  // Incorrect (Fast or Slow)
  wastedEffort, // Incorrect & Slow (Special sub-case, optional)
  skipped,      // Not attempted
  unknown       // Fallback
}

class PerformanceAnalysisUtils {

  // 2. Default Benchmarks (in seconds)
  // You will likely fetch these from Firestore later, but these are safe defaults.
  static const int defaultIdealTimePhysics = 120; // 2 mins
  static const int defaultIdealTimeChemistry = 90; // 1.5 mins
  static const int defaultIdealTimeMaths = 150;    // 2.5 mins

  /// Returns the ideal time for a question based on its subject.
  /// You can expand this to take 'difficulty' or 'questionType' later.
  static int getIdealTime(String subject) {
    switch (subject.toLowerCase()) {
      case 'physics':
        return defaultIdealTimePhysics;
      case 'chemistry':
        return defaultIdealTimeChemistry;
      case 'maths':
      case 'mathematics':
        return defaultIdealTimeMaths;
      default:
        return 120; // Default average
    }
  }

  /// The Core Logic: Determines the quadrant for a single response
  static PerformanceQuadrant analyzeResponse({
    required String status,
    required int timeSpent,
    required String subject,
    int? customIdealTime, // Allow passing a specific time if you fetched it from Config
  }) {
    if (status == 'SKIPPED') {
      return PerformanceQuadrant.skipped;
    }

    if (status == 'INCORRECT') {
      // You could split this into "Silly Mistake" (Fast) vs "Conceptual Error" (Slow)
      // For now, we group them as Learning Gap.
      return PerformanceQuadrant.learningGap;
    }

    if (status == 'CORRECT') {
      final int idealTime = customIdealTime ?? getIdealTime(subject);

      if (timeSpent <= idealTime) {
        return PerformanceQuadrant.mastery;
      } else {
        return PerformanceQuadrant.needsSpeed;
      }
    }

    return PerformanceQuadrant.unknown;
  }

  /// Helper to get a color for the UI later
  static int getColorHexForQuadrant(PerformanceQuadrant quadrant) {
    switch (quadrant) {
      case PerformanceQuadrant.mastery:
        return 0xFF4CAF50; // Green
      case PerformanceQuadrant.needsSpeed:
        return 0xFFFFC107; // Amber/Yellow
      case PerformanceQuadrant.learningGap:
        return 0xFFF44336; // Red
      case PerformanceQuadrant.skipped:
        return 0xFF9E9E9E; // Grey
      default:
        return 0xFF000000;
    }
  }
}