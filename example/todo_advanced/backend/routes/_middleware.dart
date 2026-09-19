import 'package:dart_frog/dart_frog.dart';
import 'package:todo_advanced_backend/repositories/todo_repository.dart';
import 'package:todo_advanced_backend/services/simulation_service.dart';

final _todoRepository = TodoRepository();
final _simulationService = SimulationService(_todoRepository);

Handler middleware(Handler handler) {
  return handler
      .use(_corsMiddleware())
      .use(_requestLogger())
      .use(provider<TodoRepository>((_) => _todoRepository))
      .use(provider<SimulationService>((_) => _simulationService));
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
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, X-Idempotency-Key, X-Force-Update, X-Force-Delete',
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
