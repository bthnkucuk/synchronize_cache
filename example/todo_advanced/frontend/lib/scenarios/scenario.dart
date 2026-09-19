import 'package:flutter/foundation.dart';

import '../database/database.dart';

/// Result of running one [Scenario].
@immutable
class ScenarioOutcome {
  const ScenarioOutcome.pass(this.details) : passed = true;

  const ScenarioOutcome.fail(this.details) : passed = false;

  final bool passed;

  /// Human-readable evidence: what was observed and why it passes or fails.
  final String details;
}

/// Everything a scenario needs: a scratch database that is wiped before every
/// run and the URL of the demo backend.
@immutable
class ScenarioContext {
  const ScenarioContext({required this.db, required this.backendUrl});

  final AppDatabase db;
  final String backendUrl;
}

typedef ScenarioBody = Future<ScenarioOutcome> Function(
  ScenarioContext context,
);

/// A reproducible check of one sync behaviour, runnable from the UI.
///
/// Every scenario states the behaviour users rely on and then exercises the
/// real sync stack to see whether it holds.
@immutable
class Scenario {
  const Scenario({
    required this.id,
    required this.title,
    required this.expectation,
    required this.run,
  });

  /// Stable identifier, e.g. `K1-2`, matching `REVIEW_FINDINGS.md`.
  final String id;

  final String title;

  /// The behaviour that must hold for the scenario to pass.
  final String expectation;

  final ScenarioBody run;
}
