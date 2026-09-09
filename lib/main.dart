import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'data/ai_service.dart';
import 'data/integrations.dart';
import 'data/local_repository.dart';
import 'data/native_service.dart';
import 'data/network_service.dart';
import 'ui/app_model.dart';
import 'ui/app_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final native = NativeService();
  final path = await native.call<String>('dataDirectory');
  final repository = LocalRepository(Directory(path!));
  final network = NetworkService();
  final model = AppModel(
    repository: repository,
    native: native,
    ai: AiService(network, native),
    integrations: Integrations(network, native, repository),
  );
  runApp(LocalMindApp(model: model));
  unawaited(model.initialize());
}
