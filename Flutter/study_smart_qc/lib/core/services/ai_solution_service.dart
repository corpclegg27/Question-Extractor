// lib/core/services/ai_solution_service.dart
// Description: Service to handle communications with Firebase Cloud Functions for AI tasks.
// - Initializes FirebaseFunctions instance.
// - Calls 'generate_ai_solution' to fetch on-demand solutions.
// - Handles errors (timeouts, permission issues) and returns clean strings.
// - Designed to be called from UI widgets like QuestionReviewCard.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class AiSolutionService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Calls the Cloud Function to generate a solution for the given [questionId].
  /// Returns the generated solution text or throws an exception.
  Future<String> generateSolution(String questionId) async {
    try {
      if (kDebugMode) {
        print("🤖 AI Service: Requesting solution for $questionId...");
      }

      final HttpsCallable callable = _functions.httpsCallable(
        'generate_ai_solution',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

      final result = await callable.call(<String, dynamic>{
        'questionId': questionId,
      });

      final data = result.data as Map<dynamic, dynamic>;

      // The function returns a dict: {'solution': '...', 'source': '...'}
      final solutionText = data['solution'] as String?;

      if (solutionText == null || solutionText.isEmpty) {
        throw Exception("AI returned an empty solution.");
      }

      if (kDebugMode) {
        print("✅ AI Service: Success! Source: ${data['source']}");
      }

      return solutionText;

    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        print("❌ AI Service Error (Firebase): ${e.code} - ${e.message}");
      }
      throw _handleFirebaseError(e);
    } catch (e) {
      if (kDebugMode) {
        print("❌ AI Service Error (General): $e");
      }
      throw Exception("Failed to generate solution. Please try again.");
    }
  }

  /// Helper to convert Firebase error codes into user-friendly messages.
  Exception _handleFirebaseError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return Exception("Question data not found on server.");
      case 'failed-precondition':
        return Exception("Cannot generate solution: Missing image or data.");
      case 'deadline-exceeded':
        return Exception("AI is taking too long. Please try again.");
      case 'unavailable':
        return Exception("AI Service is temporarily unavailable.");
      default:
        return Exception("AI Error: ${e.message ?? 'Unknown error'}");
    }
  }
}