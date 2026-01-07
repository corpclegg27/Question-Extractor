import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_smart_qc/models/attempt_model.dart';

class LocalSessionService {
  static const String _sessionKey = 'current_active_session';

  // ===========================================================================
  // 1. SAVE SESSION (The Black Box Recorder)
  // ===========================================================================
  /// Call this on every user interaction (Next, Answer, Mark Review) and Lifecycle Pause.
  Future<void> saveSession({
    required String assignmentCode,
    required String mode, // Expects 'Test' or 'Practice' (Title Case)
    required String testId,
    required int totalQuestions,
    required int currentTimerValue, // Seconds remaining (Test) or elapsed (Practice)
    required int currentQuestionIndex,
    required Map<String, ResponseObject> responses,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Serialize Responses using the new .toJson() method
    final serializedResponses = responses.map(
          (key, value) => MapEntry(key, value.toJson()),
    );

    final sessionData = {
      "testSessionPending": "Session pending",
      "meta": {
        "assignmentCode": assignmentCode,
        "mode": mode,
        "testId": testId,
        "totalQuestions": totalQuestions
      },
      "timestamps": {
        "quitTimeTimestamp": DateTime.now().toIso8601String(),
        "quitTimeTimerValue": currentTimerValue
      },
      "state": {
        "currentQuestionIndex": currentQuestionIndex,
        "responses": serializedResponses
      }
    };

    await prefs.setString(_sessionKey, jsonEncode(sessionData));
  }

  // ===========================================================================
  // 2. CHECK & FETCH (The Gatekeeper)
  // ===========================================================================

  /// Checks if a valid pending session exists.
  Future<bool> hasPendingSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_sessionKey)) return false;

    final jsonString = prefs.getString(_sessionKey);
    if (jsonString == null) return false;

    try {
      final data = jsonDecode(jsonString);
      return data['testSessionPending'] == "Session pending";
    } catch (e) {
      return false; // Corrupt data
    }
  }

  /// Retrieves the raw session data.
  Future<Map<String, dynamic>?> getSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_sessionKey);
    if (jsonString == null) return null;
    return jsonDecode(jsonString);
  }

  // ===========================================================================
  // 3. TIMER RECONCILIATION (The Anti-Cheat Math)
  // ===========================================================================

  /// Calculates the correct time to resume from.
  /// Returns NULL if the test time has expired while away.
  int? calculateResumeTime({
    required String mode,
    required int savedTimerValue,
    required String savedTimestampIso,
  }) {
    // 1. Practice Mode: Effort based. Ignore the gap.
    if (mode == 'Practice') {
      return savedTimerValue;
    }

    // 2. Test Mode: Strict time.
    final savedTime = DateTime.parse(savedTimestampIso);
    final now = DateTime.now();
    final timeGoneSeconds = now.difference(savedTime).inSeconds;

    // We subtract the time they were away from the time they had left.
    final newRemainingTime = savedTimerValue - timeGoneSeconds;

    if (newRemainingTime <= 0) {
      return null; // Time Expired!
    }
    return newRemainingTime;
  }

  // ===========================================================================
  // 4. HELPERS
  // ===========================================================================

  /// Helper to convert the JSON map back into your ResponseObject Map
  Map<String, ResponseObject> parseResponses(Map<String, dynamic> jsonMap) {
    // The jsonMap from storage is Map<String, dynamic> where value is the JSON of ResponseObject
    return jsonMap.map(
          (key, value) => MapEntry(key, ResponseObject.fromJson(value)),
    );
  }

  /// Clears the session from disk (Call after successful submission).
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}