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
      return 'OPEN · 端口已开（TCP 握手成功）';
    } on SocketException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('refused')) {
        return 'REFUSED · 端口已开（防火墙已放行，服务未监听）';
      }
      if (message.contains('timed out') || message.contains('timeout')) {
        return 'FILTERED · 端口未开（超时或被防火墙/网络丢弃）';
      }
      return 'FAILED · 未知状态（${error.message}）';
    } on TimeoutException {
      return 'FILTERED · 端口未开（超时或被防火墙/网络丢弃）';
    }
  }
}
