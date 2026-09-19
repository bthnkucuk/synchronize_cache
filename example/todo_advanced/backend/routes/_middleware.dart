import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

final _todoRepository = TodoRepository();
final _simulationService = SimulationService(_todoRepository);

Handler middleware(Handler handler) {
  return handler
      .use(_bareConflictMiddleware())
      .use(_delayMiddleware())
      .use(_corsMiddleware())
      .use(_requestLogger())
      .use(provider<TodoRepository>((_) => _todoRepository))
      .use(provider<SimulationService>((_) => _simulationService));
}

/// Applies the artificial latency armed via `POST /simulate/delay`.
///
/// Sits inside the CORS middleware so preflight requests are never delayed,
/// and skips the `/simulate` routes themselves.
Middleware _delayMiddleware() {
  return (handler) {
    return (context) async {
      if (!context.request.uri.path.startsWith('/simulate')) {
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
Middleware _bareConflictMiddleware() {
  const writes = {HttpMethod.put, HttpMethod.post, HttpMethod.delete};
  return (handler) {
    return (context) async {
      final request = context.request;
      if (writes.contains(request.method) &&
          request.uri.path.startsWith('/todos')) {
        final status = _simulationService.takeWriteFailure();
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
      'X-Idempotency-Key, X-Force-Update, X-Force-Delete',
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
