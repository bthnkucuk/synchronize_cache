import 'package:http/http.dart' as http;

/// An [http.Client] that records every request it sends.
///
/// [maxRequests] is a safety valve for scenarios that may trigger a runaway
/// request loop: once exceeded, further requests fail locally instead of
/// hammering the backend forever.
class RecordingClient extends http.BaseClient {
  RecordingClient({this.maxRequests});

  final int? maxRequests;
  final http.Client _inner = http.Client();

  /// Every request sent so far, in order.
  final List<http.BaseRequest> requests = [];

  /// Whether [maxRequests] was exceeded at least once.
  bool guardTripped = false;

  /// Number of recorded requests with [method] whose path ends in [pathSuffix].
  int count(String method, String pathSuffix) => requests
      .where((r) => r.method == method && r.url.path.endsWith(pathSuffix))
      .length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    final limit = maxRequests;
    if (limit != null && requests.length > limit) {
      guardTripped = true;
      throw StateError('scenario guard: more than $limit requests');
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
