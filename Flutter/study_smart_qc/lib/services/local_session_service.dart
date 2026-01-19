// lib/services/local_session_service.dart
// Description: Manages local persistence. Added 'reload()' to prevent stale reads when switching screens.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_smart_qc/models/attempt_model.dart';

class LocalSessionService {
  static const String _sessionKey = 'current_active_session';

  // ===========================================================================
  // 1. SAVE SESSION
  // ===========================================================================
  Future<void> saveSession({
    required String assignmentCode,
    required String mode,
    required String testId,
    required int totalQuestions,
    required int currentTimerValue,
    required int currentQuestionIndex,
    required Map<String, ResponseObject> responses,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Serialize: Ensure complex objects like Lists in selectedOption are preserved
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
  // 2. CHECK & FETCH (UPDATED)
  // ===========================================================================

  Future<bool> hasPendingSession() async {
    final prefs = await SharedPreferences.getInstance();

    // [CRITICAL FIX] Force reload from disk to avoid stale cache after rapid screen switches
    await prefs.reload();

    if (!prefs.containsKey(_sessionKey)) return false;

    final jsonString = prefs.getString(_sessionKey);
    if (jsonString == null) return false;

    try {
      final data = jsonDecode(jsonString);
      return data['testSessionPending'] == "Session pending";
    } catch (e) {
      // If data is corrupt, clear it so user isn't stuck
      await clearSession();
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSessionData() async {
    final prefs = await SharedPreferences.getInstance();

    // [CRITICAL FIX] Ensure we get the latest data structure
    await prefs.reload();

    final jsonString = prefs.getString(_sessionKey);
    if (jsonString == null) return null;
    try {
      return jsonDecode(jsonString);
    } catch (e) {
      return null;
    }
  }

  // ===========================================================================
  // 3. TIMER RECONCILIATION
  // ===========================================================================

  int? calculateResumeTime({
    required String mode,
    required int savedTimerValue,
    required String savedTimestampIso,
  }) {
    if (mode == 'Practice') {
      return savedTimerValue;
    }

    final savedTime = DateTime.parse(savedTimestampIso);
    final now = DateTime.now();
    final timeGoneSeconds = now.difference(savedTime).inSeconds;

    final newRemainingTime = savedTimerValue - timeGoneSeconds;

    if (newRemainingTime <= 0) {
      return null; // Time Expired
    }
    return newRemainingTime;
  }

  // ===========================================================================
  // 4. HELPERS
  // ===========================================================================

  Map<String, ResponseObject> parseResponses(Map<String, dynamic> jsonMap) {
    return jsonMap.map(
          (key, value) => MapEntry(key, ResponseObject.fromMap(value)),
    );
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}