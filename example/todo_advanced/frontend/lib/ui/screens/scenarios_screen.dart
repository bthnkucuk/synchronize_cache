import 'package:flutter/material.dart';

import '../../database/database.dart';
import '../../main.dart' show kBackendUrl;
import '../../scenarios/scenario.dart';
import '../../scenarios/sync_scenarios.dart';

/// Runs the sync behaviour checks in [syncScenarios] against the demo backend
/// and shows the evidence for each one.
///
/// Scenarios use their own scratch database, so the todos in the main app are
/// never touched.
class ScenariosScreen extends StatefulWidget {
  const ScenariosScreen({super.key});

  @override
  State<ScenariosScreen> createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends State<ScenariosScreen> {
  late final AppDatabase _db = AppDatabase.open(
    name: 'todo_advanced_scenarios',
  );
  final Map<String, ScenarioOutcome> _outcomes = {};
  String? _running;

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Future<void> _run(Scenario scenario) async {
    setState(() {
      _running = scenario.id;
      _outcomes.remove(scenario.id);
    });

    ScenarioOutcome outcome;
    try {
      await wipeScenarioDatabase(_db);
      outcome = await scenario.run(
        ScenarioContext(db: _db, backendUrl: kBackendUrl),
      );
    } catch (error) {
      outcome = ScenarioOutcome.fail('Scenario crashed: $error');
    }

    if (!mounted) return;
    setState(() {
      _running = null;
      _outcomes[scenario.id] = outcome;
    });
  }

  Future<void> _runAll() async {
    for (final scenario in syncScenarios) {
      if (!mounted) return;
      await _run(scenario);
    }
  }

  @override
  Widget build(BuildContext context) {
    final passed = _outcomes.values.where((o) => o.passed).length;
    final failed = _outcomes.length - passed;
    final busy = _running != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync scenarios')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Each scenario states a behaviour the sync stack must guarantee '
            'and checks it against the real engine and backend '
            '($kBackendUrl).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: busy ? null : _runAll,
                icon: const Icon(Icons.playlist_play),
                label: const Text('Run all scenarios'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Summary: $passed passed, $failed failed, '
                  '${syncScenarios.length - _outcomes.length} not run',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final scenario in syncScenarios)
            _ScenarioCard(
              scenario: scenario,
              outcome: _outcomes[scenario.id],
              running: _running == scenario.id,
              onRun: busy ? null : () => _run(scenario),
            ),
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.outcome,
    required this.running,
    required this.onRun,
  });

  final Scenario scenario;
  final ScenarioOutcome? outcome;
  final bool running;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = this.outcome;

    final String status;
    final Color color;
    if (running) {
      status = 'RUNNING';
      color = theme.colorScheme.primary;
    } else if (outcome == null) {
      status = 'NOT RUN';
      color = theme.colorScheme.outline;
    } else if (outcome.passed) {
      status = 'PASS';
      color = Colors.green.shade700;
    } else {
      status = 'FAIL';
      color = theme.colorScheme.error;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${scenario.id} · ${scenario.title}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                OutlinedButton(
                  onPressed: onRun,
                  child: Text('Run ${scenario.id}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Expected: ${scenario.expectation}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${scenario.id} result: $status'
              '${outcome == null ? '' : ' — ${outcome.details}'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
