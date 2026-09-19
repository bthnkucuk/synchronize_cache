import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/repositories/note_repository.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/services/change_hub.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

/// The kinds that take part in sync. Everything the simulations do is scoped
/// to these paths, so `/health`, `/reset` and `/ws` are never delayed or
/// failed by an armed experiment.
const _syncKinds = {'todos', 'notes'};

final _changeHub = ChangeHub();

// Every write that changes a record wakes the connected apps. Wiring it here,
// once, means the `/simulate/*` endpoints broadcast too — they go through the
// same repositories as a client push.
final _todoRepository = TodoRepository(onChanged: _changeHub.recordChanged);
final _noteRepository = NoteRepository(onChanged: _changeHub.recordChanged);
final _simulationService = SimulationService(_todoRepository, _noteRepository);

Handler middleware(Handler handler) {
  return handler
      .use(_writeSimulationMiddleware())
      .use(_delayMiddleware())
      .use(_corsMiddleware())
      .use(_requestLogger())
      .use(provider<TodoRepository>((_) => _todoRepository))
      .use(provider<NoteRepository>((_) => _noteRepository))
      .use(provider<ChangeHub>((_) => _changeHub))
      .use(provider<SimulationService>((_) => _simulationService));
}

/// Applies the artificial latency armed via `POST /simulate/delay`.
///
/// Sits inside the CORS middleware so preflight requests are never delayed,
/// and skips the `/simulate` routes themselves. `/health` is deliberately
/// included: "the server answers, but far too slowly" is exactly what the
/// health probe before a sync run has to survive.
///
/// `/ws` is skipped — an armed delay is meant for one API call, and eating
/// it with a socket handshake that happens to reconnect at the same moment
/// would make the experiment unrepeatable.
Middleware _delayMiddleware() {
  return (handler) {
    return (context) async {
      final path = context.request.uri.path;
      if (!path.startsWith('/simulate') && path != '/ws') {
        final delay = _simulationService.takeDelay();
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
      return handler(context);
    };
  };
}

/// Answers writes with the failure armed via `POST /simulate/fail_writes`,
/// or with the bare `409` armed via `POST /simulate/bare_conflict`.
Middleware _writeSimulationMiddleware() {
  const writes = {HttpMethod.put, HttpMethod.post, HttpMethod.delete};
  return (handler) {
    return (context) async {
      final request = context.request;
      if (writes.contains(request.method) &&
          _syncKinds.contains(_kindOf(request))) {
        // `fail_writes` can name a single record; the id is the second path
        // segment (`PUT /todos/{id}`), which is what the sync client uses
        // for every upsert and delete.
        final status = _simulationService.takeWriteFailure(
          _entityIdOf(request),
        );
        if (status != null) {
          return Response.json(
            statusCode: status,
            body: {'error': 'simulated $status'},
          );
        }
        if (_simulationService.takeBareConflict()) {
          return Response.json(statusCode: 409, body: {'error': 'conflict'});
        }
      }
      return handler(context);
    };
  };
}

/// `todos` for `/todos` and `/todos/{id}`, `null` for everything else.
String? _kindOf(Request request) {
  final segments = request.uri.pathSegments;
  return segments.isEmpty ? null : segments.first;
}

/// The `{id}` of `/{kind}/{id}`, or `null` for a collection request.
String? _entityIdOf(Request request) {
  final segments = request.uri.pathSegments;
  return segments.length > 1 ? segments[1] : null;
}

Middleware _corsMiddleware() {
  return (handler) {
    return (context) async {
      // Handle preflight requests
      if (context.request.method == HttpMethod.options) {
        return Response(statusCode: 204, headers: _corsHeaders);
      }

      final response = await handler(context);
      return response.copyWith(headers: {...response.headers, ..._corsHeaders});
    };
  };
}

// TODO: Restrict 'Access-Control-Allow-Origin' to specific domains in production
const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  // RestTransport always sends Authorization (and If-Match once versions are
  // used); without them here every browser request fails its CORS preflight.
  'Access-Control-Allow-Headers':
      'Origin, Content-Type, Accept, Authorization, If-Match, '
      'X-Idempotency-Key, X-Force-Update, X-Force-Delete, X-Base-Updated-At',
  'Access-Control-Expose-Headers': 'X-Next-Page-Token',
};

Middleware _requestLogger() {
  return (handler) {
    return (context) async {
      // Note: In production, use structured logging instead of print
      // print() is disabled to avoid exposing request paths in production logs
      // Enable for local development only:
      // print('[${context.request.method.value}] ${context.request.uri.path}');
      return handler(context);
    };
  };
}
