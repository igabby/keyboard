import 'dart:io';

class SocketRemoteConnection implements RemoteConnection {
  final Socket _socket;

  const SocketRemoteConnection(this._socket);

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  void writeln(String value) => _socket.writeln(value);
}

abstract class RemoteConnection {
  Future<void> get done;

  void writeln(String value);

  Future<void> close();
}

Future<RemoteConnection> connectToRemote(
  String host,
  int port, {
  required Duration timeout,
}) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  return SocketRemoteConnection(socket);
}
