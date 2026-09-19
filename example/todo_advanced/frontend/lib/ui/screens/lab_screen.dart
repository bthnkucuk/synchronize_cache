import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../models/todo.dart';
import '../../repositories/note_repository.dart';
import '../../repositories/todo_repository.dart';
import '../../services/lab_actions.dart';
import '../../services/sync_service.dart';
import '../widgets/experiment_card.dart';
import 'scenarios_screen.dart';

/// Edge cases you can trigger by hand, one card each.
///
/// The automated "Sync scenarios" screen proves the library behaves; this
/// screen lets you *watch* it behave, which is a different kind of
/// understanding. Every card names what must not happen, because in sync
/// that is usually the interesting part: nothing is lost, nothing is sent
/// twice, nothing gets parked because the network was down.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  String? _armed;
  String? _poisonedId;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final theme = Theme.of(context);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Arm an experiment, then use the app normally and watch the '
            'chips on each card and the sync panel.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ScenariosScreen()),
            ),
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Automated sync scenarios'),
          ),
          const SizedBox(height: 4),
          Text(
            'Those run by themselves against a scratch database and report '
            'pass or fail. The experiments below are the opposite: you '
            'drive them, on your real data.',
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 28),

          ExperimentCard(
            number: 1,
            title: 'No connection',
            doThis:
                'Switch the connection off, then add or edit a todo and '
                'press Send now.',
            youShouldSee:
                'The item is chipped "Only on this device" or "Changes not '
                'sent yet", the pending count grows, and the reason says '
                '"No connection to the server". Switch the connection back '
                'on and press Send now: everything goes.',
            mustNotHappen:
                'Nothing may be lost, and attempts must stay at 0 — a dead '
                'network is not the item\'s fault, so it must never become '
                'stuck.',
            armed: !sync.networkSwitch.online,
            control: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: !sync.networkSwitch.online,
              onChanged: (value) =>
                  setState(() => sync.networkSwitch.online = !value),
              title: Text(
                sync.networkSwitch.online
                    ? 'Connection is on'
                    : 'Connection is off',
              ),
            ),
          ),

          ExperimentCard(
            number: 2,
            title: 'Sign-in expired (401)',
            doThis:
                'Arm it, then edit something and press Send now a few times.',
            youShouldSee:
                'The chip says "Waiting to retry" and the reason reads '
                '"Your sign-in has expired".',
            mustNotHappen:
                'The item must never become stuck: an expired token is the '
                'session\'s problem, not the item\'s.',
            armed: _armed == 'auth',
            control: _ArmButton(
              label: 'Arm 6 failing writes (401)',
              armed: _armed == 'auth',
              onArm: () => _arm('auth', () => _actions.failWrites(status: 401)),
              onDisarm: _disarm,
            ),
          ),

          ExperimentCard(
            number: 3,
            title: 'Server down (503)',
            doThis: 'Arm it, then edit something and press Send now.',
            youShouldSee:
                'The chip says "Waiting to retry" and the reason reads '
                '"The server is having trouble (HTTP 503)".',
            mustNotHappen:
                'Attempts must stay at 0 and the queue must survive — an '
                'outage must not eat anybody\'s work.',
            armed: _armed == 'server',
            control: _ArmButton(
              label: 'Arm 6 failing writes (503)',
              armed: _armed == 'server',
              onArm: () =>
                  _arm('server', () => _actions.failWrites(status: 503)),
              onDisarm: _disarm,
            ),
          ),

          ExperimentCard(
            number: 4,
            title: 'The server rejects one item (422)',
            doThis:
                'Poison the first todo, then edit it and press Send now five '
                'times. Edit a different todo in between.',
            youShouldSee:
                'After five attempts only the poisoned todo is "Stuck", with '
                'the server\'s message. Retry and Discard change both work '
                'from its chip.',
            mustNotHappen:
                'Everything else must keep syncing — one bad item may not '
                'block the queue.',
            armed: _poisonedId != null,
            control: _poisonedId == null
                ? _Buttons(
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _poisonFirstTodo(),
                        child: const Text('Poison the first todo'),
                      ),
                    ],
                  )
                : _Buttons(
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          await _actions.stopFailingWrites();
                          if (mounted) setState(() => _poisonedId = null);
                        },
                        child: const Text('Stop rejecting it'),
                      ),
                    ],
                  ),
          ),

          ExperimentCard(
            number: 5,
            title: 'Edited on another device',
            doThis:
                'Press one of the buttons, then edit the same item here and '
                'press Send now.',
            youShouldSee:
                'A todo opens the conflict dialog and waits for you. A note '
                'merges by itself — the sync log names which field came from '
                'which device.',
            mustNotHappen:
                'Neither version may be dropped silently, and a note must '
                'not stop to ask.',
            control: _Buttons(
              children: [
                FilledButton.tonal(
                  onPressed: () => _editFirstTodoElsewhere(),
                  child: const Text('Another device edits a todo'),
                ),
                FilledButton.tonal(
                  onPressed: () => _editFirstNoteElsewhere(),
                  child: const Text('Another device edits a note'),
                ),
              ],
            ),
          ),

          ExperimentCard(
            number: 6,
            title: 'Deleted on another device',
            doThis: 'Press the button, then press Get changes.',
            youShouldSee:
                'The item disappears from this device — the pull brought a '
                'tombstone, not an empty answer.',
            mustNotHappen:
                'It must not quietly stay in the list, and it must not come '
                'back at the next sync.',
            control: _Buttons(
              children: [
                FilledButton.tonal(
                  onPressed: () => _deleteFirstTodoElsewhere(),
                  child: const Text('Another device deletes a todo'),
                ),
              ],
            ),
          ),

          ExperimentCard(
            number: 7,
            title: 'Two quick edits before a sync',
            doThis:
                'Press the button: it edits the first todo twice in a row '
                'without syncing in between, then sends.',
            youShouldSee:
                'Both edits are accepted and the final text is the second '
                'one.',
            mustNotHappen:
                'You must never conflict with yourself — the app stamps a '
                'new updatedAt on every edit, but the base it sends is the '
                'version the server gave back.',
            control: _Buttons(
              children: [
                FilledButton.tonal(
                  onPressed: () => _twoQuickEdits(),
                  child: const Text('Edit twice, then send'),
                ),
              ],
            ),
          ),

          ExperimentCard(
            number: 8,
            title: 'Slow server',
            doThis: 'Arm it, then press Sync now and keep using the app.',
            youShouldSee:
                'The app stays usable and the request gives up after the '
                'transport timeout instead of waiting for the server.',
            mustNotHappen:
                'The UI must not freeze, and sync must not hang forever.',
            armed: _armed == 'delay',
            control: _ArmButton(
              label: 'Make the next request take 6 s',
              armed: _armed == 'delay',
              onArm: () => _arm('delay', _actions.delayNextRequest),
              onDisarm: _disarm,
            ),
          ),

          ExperimentCard(
            number: 9,
            title: 'Delete here what another device just edited',
            doThis:
                'Press the button: another device edits the first todo, then '
                'this device deletes it. Press Send now.',
            youShouldSee:
                'The conflict dialog asks whether to delete anyway or keep '
                'the other device\'s version. Notes answer this one by '
                'themselves: the edit wins and the note comes back.',
            mustNotHappen:
                'The delete must not go through silently, and it must not '
                'sit in the queue forever without ever asking.',
            control: _Buttons(
              children: [
                FilledButton.tonal(
                  onPressed: () => _deleteWhatWasEdited(),
                  child: const Text('Edit elsewhere, delete here'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  LabActions get _actions => context.read<LabActions>();

  Future<void> _arm(String id, Future<void> Function() action) async {
    await _run(action, 'Armed');
    if (mounted) setState(() => _armed = id);
  }

  Future<void> _disarm() async {
    await _run(_actions.stopFailingWrites, 'Disarmed');
    if (mounted) setState(() => _armed = null);
  }

  Future<void> _poisonFirstTodo() async {
    final todo = await _firstTodo();
    if (todo == null || !mounted) return;
    await _run(
      () => _actions.failWrites(status: 422, requests: 100, entityId: todo.id),
      'The server will now reject "${todo.title}"',
    );
    if (mounted) setState(() => _poisonedId = todo.id);
  }

  Future<void> _editFirstTodoElsewhere() async {
    final todo = await _firstTodo();
    if (todo == null || !mounted) return;
    await _run(
      () => _actions.editTodoElsewhere(todo.id),
      'Another device changed the priority of "${todo.title}"',
    );
  }

  Future<void> _editFirstNoteElsewhere() async {
    final note = await _firstNote();
    if (note == null || !mounted) return;
    await _run(
      () => _actions.editNoteElsewhere(
        note.id,
        body: 'Added by another device at ${TimeOfDay.now().format(context)}',
      ),
      'Another device changed the body of "${note.title}"',
    );
  }

  Future<void> _deleteFirstTodoElsewhere() async {
    final todo = await _firstTodo();
    if (todo == null || !mounted) return;
    await _run(
      () => _actions.deleteElsewhere('todos', todo.id),
      'Another device deleted "${todo.title}" — press Get changes',
    );
  }

  Future<void> _twoQuickEdits() async {
    final repo = context.read<TodoRepository>();
    final sync = context.read<SyncService>();
    var todo = await _firstTodo();
    if (todo == null || !mounted) return;

    // Two edits with no sync in between. The second one is based on the
    // first one's local row, but the *base* sent to the server is still the
    // version the server last returned — which is why this is not a
    // conflict with yourself.
    final original = todo.title;
    todo = await repo.update(todo, title: '$original (1)');
    await repo.update(todo, title: '$original (2)');
    await _run(sync.sendNow, 'Both edits sent');
  }

  Future<void> _deleteWhatWasEdited() async {
    final repo = context.read<TodoRepository>();
    final todo = await _firstTodo();
    if (todo == null || !mounted) return;

    await _run(() async {
      await _actions.editTodoElsewhere(todo.id, priority: 1);
      await repo.delete(todo);
    }, 'Edited elsewhere and deleted here — press Send now');
  }

  Future<Todo?> _firstTodo() async {
    final todos = await context.read<TodoRepository>().getAll();
    if (todos.isEmpty) {
      _say('Add a todo first, and sync it.');
      return null;
    }
    return todos.first;
  }

  Future<Note?> _firstNote() async {
    final notes = await context.read<NoteRepository>().getAll();
    if (notes.isEmpty) {
      _say('Add a note first, and sync it.');
      return null;
    }
    return notes.first;
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    // Grab the messenger before awaiting: afterwards this State may be gone.
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    try {
      await action();
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not do that: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ArmButton extends StatelessWidget {
  const _ArmButton({
    required this.label,
    required this.armed,
    required this.onArm,
    required this.onDisarm,
  });

  final String label;
  final bool armed;
  final Future<void> Function() onArm;
  final Future<void> Function() onDisarm;

  @override
  Widget build(BuildContext context) => _Buttons(
    children: [
      if (armed)
        OutlinedButton(onPressed: onDisarm, child: const Text('Disarm'))
      else
        FilledButton.tonal(onPressed: onArm, child: Text(label)),
    ],
  );
}

class _Buttons extends StatelessWidget {
  const _Buttons({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);
}
