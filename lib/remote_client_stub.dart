abstract class RemoteConnection {
  Future<void> get done;

  void writeln(String value);

  Future<void> close();
}

Future<RemoteConnection> connectToRemote(
  String host,
  int port, {
  required Duration timeout,
}) {
  throw UnsupportedError(
    'Raw TCP sockets are not available in this Flutter target. '
    'Run the app on Android, iOS, Windows, macOS, or Linux.',
  );
}
