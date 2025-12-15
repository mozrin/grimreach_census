import 'package:grimreach_api/world_state.dart';

void main() {
  final state = WorldState(entities: [], players: []);
  print(
    'Census: API linked. Ready to analyze ${state.players.length} players.',
  );
}
