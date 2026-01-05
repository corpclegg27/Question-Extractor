# Project Roadmap & Technical Debt Tracker

## 🚀 MVP Goals (Current Phase)
- [x] **Single Correct UI:** Horizontal tiles (A, B, C, D) with selection logic.
- [x] **Numerical UI:** Text field input accepting decimals.
- [ ] **Scoring Logic:** Implement standard +4/-1 scoring for Single/Numerical types.
- [ ] **Timer:** Basic countdown timer with auto-submit.
- [ ] **Result Screen:** Display basic correct/incorrect counts and score.

## 🔮 Phase 2: Advanced Question Types (JEE Advanced)
- [ ] **Multi-Select UI:** - Fix `AnswerState` to support `List<String>` instead of just `String`.
    - Implement robust UI for "One or more options correct".
- [ ] **Matrix Match UI:**
    - Implement Grid UI (Rows A-D, Cols P-T).
    - Update `AnswerState` to support `Map<String, List<String>>`.
- [ ] **Correct Answer Parsing:**
    - Decouple `correctAnswer` in Model. 
    - specific parser to convert strings like "A, B" or "A B" into `['A', 'B']`.

## 🧠 Phase 3: The Advanced Scoring Engine
- [ ] **Decoupled Scoring Logic:**
    - Move away from hardcoded `if (correct) +4 else -1`.
    - Create a `MarkingScheme` model.
- [ ] **Partial Marking Implementation:**
    - Implement "Step-wise" marking (e.g., +1 for each correct option).
    - Implement "Negative blocking" (selecting any wrong option = negative marks).
- [ ] **Schema Update:** - Create `/static_data/marking_schemes` collection in Firestore.
    - Add `marking_scheme_id` to Question documents.

## 🐛 Known Issues / Technical Debt
- **Text Matching:** Firestore question types rely on exact string matching. Need to implement `.trim()` and `.toLowerCase()` sanitization globally.
- **Answer Recording:** Currently, `AnswerState` might still be treating all inputs as Strings. Need to refactor to `dynamic` or a custom `Answer` class.