import 'dart:io';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/message_codec.dart';

void main() async {
  try {
    final socket = await WebSocket.connect('ws://localhost:8080/ws');
    final codec = MessageCodec();

    print('Census: Connected to server');

    socket.listen(
      (data) {
        if (data is String) {
          final msg = codec.decode(data);
          print('Census: Echo received: ${msg.type}');
          exit(0); // Exit after successful echo for this test phase
        }
      },
      onError: (e) {
        print('Census: Error: $e');
        exit(1);
      },
      onDone: () {
        print('Census: Disconnected');
      },
    );

    // Send handshake
    final handshake = Message(
      type: Protocol.handshake,
      data: {'id': 'census_1'},
    );
    socket.add(codec.encode(handshake));
    print('Census: Sent handshake');
  } catch (e) {
    print('Census: Connection failed: $e');
    exit(1);
  }
}
