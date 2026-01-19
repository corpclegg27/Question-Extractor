// lib/models/marking_configuration.dart
// Description: Defines scoring rules (e.g., +4/-1 or +4/-2 with partial marking).

class MarkingConfiguration {
  final double correctScore;      // e.g., +4.0
  final double incorrectScore;    // e.g., -1.0 or -2.0 (stored as negative)
  final double unattemptedScore;  // e.g., 0.0

  // Specific to "One or more options correct"
  final bool allowPartialMarking;
  final double partialScorePerOption; // e.g., +1.0

  const MarkingConfiguration({
    this.correctScore = 4.0,
    this.incorrectScore = -1.0,
    this.unattemptedScore = 0.0,
    this.allowPartialMarking = false,
    this.partialScorePerOption = 1.0,
  });

  // Factory for Standard JEE Main (+4, -1)
  factory MarkingConfiguration.jeeMain() {
    return const MarkingConfiguration(
      correctScore: 4.0,
      incorrectScore: -1.0,
      allowPartialMarking: false,
    );
  }

  // Factory for JEE Advanced (+4, -2, Partial +1)
  factory MarkingConfiguration.jeeAdvanced() {
    return const MarkingConfiguration(
      correctScore: 4.0,
      incorrectScore: -2.0,
      allowPartialMarking: true,
      partialScorePerOption: 1.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'correctScore': correctScore,
      'incorrectScore': incorrectScore,
      'unattemptedScore': unattemptedScore,
      'allowPartialMarking': allowPartialMarking,
      'partialScorePerOption': partialScorePerOption,
    };
  }

  factory MarkingConfiguration.fromMap(Map<String, dynamic> map) {
    return MarkingConfiguration(
      correctScore: (map['correctScore'] ?? 4.0).toDouble(),
      incorrectScore: (map['incorrectScore'] ?? -1.0).toDouble(),
      unattemptedScore: (map['unattemptedScore'] ?? 0.0).toDouble(),
      allowPartialMarking: map['allowPartialMarking'] ?? false,
      partialScorePerOption: (map['partialScorePerOption'] ?? 1.0).toDouble(),
    );
  }
}