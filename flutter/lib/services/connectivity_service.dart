import 'dart:async';
import 'dart:io';

class ConnectivityService {
  Future<String> checkTcp(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      return 'OPEN';
    } on SocketException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('refused')) {
        return 'REFUSED';
      }
      if (message.contains('timed out') || message.contains('timeout')) {
        return 'FILTERED';
      }
      return 'FAILED (${error.message})';
    } on TimeoutException {
      return 'FILTERED';
    }
  }
}
