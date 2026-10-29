import 'package:flutter/material.dart';

import 'common.dart';

/// Loads data once, shows a spinner / error with retry, and exposes `reload` to the builder.
class AsyncBuilder<T> extends StatefulWidget {
  const AsyncBuilder({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<AsyncBuilder<T>> createState() => _AsyncBuilderState<T>();
}

class _AsyncBuilderState<T> extends State<AsyncBuilder<T>> {
  late Future<T> _future = widget.load();

  Future<void> _reload() async {
    final next = widget.load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // Displayed by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(message: '${snapshot.error}', onRetry: _reload);
        }
        if (snapshot.connectionState != ConnectionState.done && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return widget.builder(context, snapshot.data as T, _reload);
      },
    );
  }
}
