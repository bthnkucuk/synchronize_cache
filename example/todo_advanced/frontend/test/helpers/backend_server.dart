import 'dart:async';
import 'dart:io';

/// Starts a real Dart Frog backend server for E2E testing.
///
/// Uses `dart_frog dev` as a subprocess with dynamic port allocation.
class BackendServer {
  Process? _process;
  int? _port;
  final String backendPath;
  final List<String> _output = [];

  BackendServer({required this.backendPath});

  /// The port the server is running on.
  int get port {
    if (_port == null) {
      throw StateError('Server not started yet');
    }
    return _port!;
  }

  /// The base URL for API requests.
  Uri get baseUrl => Uri.parse('http://localhost:$port');

  /// Starts the server on an available port.
  Future<void> start() async {
    _port = await _findAvailablePort();
    final vmServicePort = await _findAvailablePort();

    _process = await Process.start('dart_frog', [
      'dev',
      '--port',
      '$_port',
      '--dart-vm-service-port',
      '$vmServicePort',
    ], workingDirectory: backendPath);

    // Capture output for debugging
    _process!.stdout.transform(const SystemEncoding().decoder).listen((data) {
      _output.add(data);
    });

    _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
      _output.add('[STDERR] $data');
    });

    // Wait for server to be ready
    await _waitForReady();
  }

  /// Waits for the server to respond to health check.
  Future<void> _waitForReady() async {
    // First, wait for dart_frog hot reload to be enabled
    // The server isn't actually ready until this message appears
    for (var i = 0; i < 150; i++) {
      if (_output.any((line) => line.contains('Hot reload is enabled'))) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // Now poll the health endpoint
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);

    for (var i = 0; i < 30; i++) {
      try {
        final request = await client.getUrl(
          Uri.parse('http://localhost:$_port/health'),
        );
        final response = await request.close();
        await response.drain<void>();

        if (response.statusCode == 200) {
          client.close();
          return;
        }
      } catch (_) {
        // Server not ready yet
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    client.close();
    throw Exception(
      'Server failed to start within 36 seconds.\nOutput:\n${_output.join()}',
    );
  }

  /// Stops the server.
  Future<void> stop() async {
    if (_process != null) {
      _process!.kill(ProcessSignal.sigterm);
      await _process!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _process!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      _process = null;
    }
  }

  /// Finds an available port.
  Future<int> _findAvailablePort() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    return port;
  }

  /// Returns captured server output for debugging.
  String get output => _output.join();
}
