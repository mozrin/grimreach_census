import 'dart:io';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/message_codec.dart';
import 'package:grimreach_api/world_state.dart';

void main() async {
  try {
    final socket = await WebSocket.connect('ws://localhost:8080/ws');
    final codec = MessageCodec();

    print('Census: Connected to server');

    socket.listen(
      (data) {
        if (data is String) {
          final msg = codec.decode(data);
          if (msg.type == Protocol.state) {
            final state = WorldState.fromJson(msg.data);
            print(
              'Census: World update - P: ${state.players.length}, E: ${state.entities.length}',
            );
            // In real implementation we'd run forever, for testing we might want to exit after receiving some.
            // But instructions say "runs cleanly with a heartbeat world broadcast".
            // I'll leave it running, but for verification I'll kill it manually.
          }
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
