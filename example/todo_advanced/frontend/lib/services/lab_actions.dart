import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the Sync lab does *to the server*, as if it were another device.
///
/// Deliberately uses its own plain [http.Client] rather than the one the
/// sync engine uses: the lab's "no connection" switch must cut this device
/// off without also cutting off the pretend other device — otherwise you
/// could never arm an experiment while offline.
class LabActions {
  LabActions({required this.backendUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String backendUrl;
  final http.Client _client;

  /// Makes the next [requests] writes fail with [status].
  ///
  /// With [entityId] only that one record fails, and only it uses up a slot:
  /// that is the difference between "everything is stuck" and "one poisoned
  /// item is stuck".
  Future<void> failWrites({
    required int status,
    int requests = 6,
    String? entityId,
  }) => _post('/simulate/fail_writes', {
    'status': status,
    'requests': requests,
    'id': ?entityId,
  });

  /// Disarms [failWrites].
  Future<void> stopFailingWrites() =>
      _post('/simulate/fail_writes', {'status': 503, 'requests': 0});

  /// Makes the next request answer only after [milliseconds].
  Future<void> delayNextRequest({int milliseconds = 6000}) =>
      _post('/simulate/delay', {'milliseconds': milliseconds, 'requests': 1});

  /// Another device changes a todo's priority.
  Future<void> editTodoElsewhere(String id, {int priority = 1}) =>
      _post('/simulate/prioritize', {'id': id, 'priority': priority});

  /// Another device edits a note. Only the fields given change.
  Future<void> editNoteElsewhere(String id, {String? title, String? body}) =>
      _post('/simulate/edit_note', {'id': id, 'title': ?title, 'body': ?body});

  /// Another device deletes a record for good.
  Future<void> deleteElsewhere(String kind, String id) async {
    final response = await _client.delete(
      Uri.parse('$backendUrl/$kind/$id'),
      headers: {'X-Force-Delete': 'true'},
    );
    if (response.statusCode >= 300 && response.statusCode != 404) {
      throw StateError(
        'DELETE /$kind/$id failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    final response = await _client.post(
      Uri.parse('$backendUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode >= 300) {
      throw StateError('$path failed: ${response.statusCode} ${response.body}');
    }
  }

  void dispose() => _client.close();
}
