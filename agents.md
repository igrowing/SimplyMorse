# AGENTS.md - Project Context & Operational Rules for AI Agents

This file provides non-negotiable architectural context, programming standards, and verification workflows for autonomous agents working on this Flutter application codebase. Read and internalize this file entirely before executing any tasks.

---

## 1. Project Overview & Architecture Blueprint

### Directory Layer Convention

Every feature must follow a strict separation of concerns utilizing Clean Architecture layers. Do not mix business logic with UI rendering:
* `lib/features/<feature_name>/domain/`  : Core models, enterprise rules, and raw interfaces. Pure Dart. No Flutter dependencies.
* `lib/features/<feature_name>/data/`    : Repository implementations, data sources (network API, local SQLite storage), and serializers.
* `lib/features/<feature_name>/presentation/` : UI screens, domain-specific widgets, and State Management controllers.


### Core Design Patterns
* **Service Locator:** Use `get_it` for dependency injection. Register dependencies inside a centralized service locator file (`lib/core/di/injection.dart`). Never instantiate long-lived service objects inline.
* **Cross-Platform Abstraction:** For platform-specific features (native vs web), utilize explicit conditional imports (`import './stub.dart' if (dart.library.js_interop) './web.dart'`) rather than stacking runtime `Platform.isAndroid` checks throughout the UI.

---

## 2. Non-Negotiable Coding Standards & Modern Syntax

### Anti-Hallucination & Modern API Rules
Agents must use modern Flutter API patterns. Do not copy legacy (2022 or older) examples found in general training sets:
* **Responsive Layouts:** NEVER query raw physical screen dimensions or hardware type ("phone" vs "tablet"). Use `LayoutBuilder` and branch directly on `constraints.maxWidth`. Remember the core engine layout rule: **"Constraints go down, sizes go up, parent sets position."**
* **MediaQuery Efficiency:** Do not use `MediaQuery.of(context).size`. This triggers unnecessary widget rebuilds across the entire tree. Use the optimized, targeted aspect methods: `MediaQuery.sizeOf(context)`, `MediaQuery.paddingOf(context)`, or `MediaQuery.viewInsetsOf(context)`.
* **Immutability:** Mark all custom presentation models and states as `@immutable`. Prefer using `freezed` or `equatable` to enforce structural equality rather than object reference identity.



### Code Style & Formatting Constraints
* **Linting:** Code must pass standard strict lint rules (`package:very_good_analysis`). 
* **Formatting:** Lines must not exceed **80 characters** to preserve structural integrity inside token contexts. Run `dart format .` automatically on any modified files.
* **Code Generation:** Code-generated companion files (`*.g.dart`, `*.freezed.dart`) must never be manually modified. If modifications require schema updates, run the build runner shell command.
* **Versions**: automatically increase minor version of the app on every commit. The minor version identifies is a number between last does and a plus sign in pubspec.yml under `version` entry. Change major or middle version number only when explicitly requested by the developer. Do not change the number after sign plus (+) in the version.

---

## 3. Strict Error Handling & Failure Protocols
* **No Silent Swallowing:** Never wrap blocks in blank `catch (e) {}` statements. Errors must be captured, transformed into typed domain `Failure` objects, and explicitly pushed to the presentation layer or logged.
* **Explicit Failure Over Default Data:** When parsing JSON data, configuration files, or network responses, **never fall back to implicit placeholder or default values** (e.g., an empty string `""` or a current timestamp `DateTime.now()`) if validation fails. Return an explicit `null` or throw a parsing exception. It is always better for the application to fail loudly and traceably than to operate silently with corrupted or hallucinated baseline data.

---

## 4. Operational Steps & Verification Loop

When assigned a development ticket or bug fix, you must execute the task according to this chronological checklist. Do not skip steps. Apply `kotlin.incremental=false` in `android\gradle.properties` if not applied yet.

### Step 1: Establish Environment Baseline
Before changing a single line of production code, verify the codebase is in a functional state to isolate future errors:
1. Run `flutter pub get` to resolve any local dependencies.
2. Run `flutter analyze` to guarantee the starting code is clear of syntax or static compilation errors.
3. Run `flutter test` to ensure existing unit and widget test files currently pass.

### Step 2: Implement Changes and Handle Code-Gen
1. Execute your structural modifications localized to the corresponding clean architecture feature layer.
2. If changing models or data serialization mappings, execute the background compiler to generate missing implementation code:

`dart run build_runner build --delete-conflicting-outputs`

3. On changes in production code follow the rules:
  * Add unit test on added functins and classes.
  * On removal of obsolete, non-used, merged functions remove according unit tests.
  * On changes in functions adapt related unit tests accordingly. 

4. **Don't repeat yourself** restriction - when any functionality is needed to implement, review existing classes and function for similar functionality. Often you will find that what's needed is already implemented. Then just call and reuse it. If slight modification to the existing functionality is needed and that function has only 1-2 invocations, enhance that function and adapt the existing invokations. If signigicant modification needed or too many calls exist to the implemented function then add a function which has larger functional span and then the older, narrower span function, can use the new one to avoid code duplication. Add new functions only if there is no similar fucntionality is already implemented.

### Step 3: Self-Correction & Automated Cleaning
Before presenting your changes for human review, clean your workspace of transient tracking code:

Review your code diff and verify that NO local print() or debugPrint() statements remain. Use an interface-wrapped logger service if logging is necessary.

Remove any unused import statements or leftover temporary code comments.

### Step 4: Verification Testing Pipeline

Confirm your adjustments have not created regression breakages elsewhere:
Run flutter analyze to ensure the new code satisfies formatting and package-specific lint rules.

Run the test suite targeting the specific module you modified:

`flutter test test/features/<target_feature_test>.dart`

If errors are flagged, read the compiler stack trace, apply a corrective fix, and re-run the verification suite until the console output reports a clean, successful completion.

