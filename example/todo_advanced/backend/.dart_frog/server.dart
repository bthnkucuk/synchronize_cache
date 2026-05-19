// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';


import '../routes/reset.dart' as reset;
import '../routes/health.dart' as health;
import '../routes/todos/index.dart' as todos_index;
import '../routes/todos/[id].dart' as todos_$id;
import '../routes/simulate/reminder.dart' as simulate_reminder;
import '../routes/simulate/prioritize.dart' as simulate_prioritize;
import '../routes/simulate/complete.dart' as simulate_complete;

import '../routes/_middleware.dart' as middleware;

void main() async {
  final address = InternetAddress.tryParse('') ?? InternetAddress.anyIPv6;
  final port = int.tryParse(Platform.environment['PORT'] ?? '57214') ?? 57214;
  hotReload(() => createServer(address, port));
}

Future<HttpServer> createServer(InternetAddress address, int port) {
  final handler = Cascade().add(buildRootHandler()).handler;
  return serve(handler, address, port);
}

Handler buildRootHandler() {
  final pipeline = const Pipeline().addMiddleware(middleware.middleware);
  final router = Router()
    ..mount('/', (context) => buildHandler()(context))
    ..mount('/todos', (context) => buildTodosHandler()(context))
    ..mount('/simulate', (context) => buildSimulateHandler()(context));
  return pipeline.addHandler(router);
}

Handler buildHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/health', (context) => health.onRequest(context,))..all('/reset', (context) => reset.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildTodosHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/<id>', (context,id,) => todos_$id.onRequest(context,id,))..all('/', (context) => todos_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildSimulateHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/complete', (context) => simulate_complete.onRequest(context,))..all('/prioritize', (context) => simulate_prioritize.onRequest(context,))..all('/reminder', (context) => simulate_reminder.onRequest(context,));
  return pipeline.addHandler(router);
}

