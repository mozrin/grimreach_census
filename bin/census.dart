import 'dart:io';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/message_codec.dart';
import 'package:grimreach_api/world_state.dart';
import 'package:grimreach_api/zone.dart';
import 'package:grimreach_api/entity_type.dart';
import 'package:grimreach_api/faction.dart';

void main() async {
  try {
    final socket = await WebSocket.connect('ws://localhost:8080/ws');
    final codec = MessageCodec();

    print('Census: Connected to server');

    // Census State
    Set<String> previousEntityIds = {};
    Map<String, Zone> previousPlayerZones = {};
    Map<String, Zone> previousEntityZones = {};

    socket.listen(
      (data) {
        if (data is String) {
          final msg = codec.decode(data);
          if (msg.type == Protocol.state) {
            final state = WorldState.fromJson(msg.data);

            int safeCount = 0;
            int wildCount = 0;
            int flowSafeToWild = 0;
            int flowWildToSafe = 0;

            final factionCounts = <Faction, int>{};

            for (final p in state.players) {
              if (p.zone == Zone.safe) safeCount++;
              if (p.zone == Zone.wilderness) wildCount++;

              factionCounts[p.faction] = (factionCounts[p.faction] ?? 0) + 1;

              if (previousPlayerZones.containsKey(p.id)) {
                final oldZone = previousPlayerZones[p.id];
                if (oldZone != p.zone) {
                  if (oldZone == Zone.safe && p.zone == Zone.wilderness) {
                    flowSafeToWild++;
                  } else if (oldZone == Zone.wilderness &&
                      p.zone == Zone.safe) {
                    flowWildToSafe++;
                  }
                }
              }
              previousPlayerZones[p.id] = p.zone;
            }

            if (flowSafeToWild > 0 || flowWildToSafe > 0) {
              print(
                'Census: Flow - Safe->Wild: $flowSafeToWild, Wild->Safe: $flowWildToSafe',
              );
            }

            int eSafe = 0;
            int eWild = 0;
            int npc = 0;
            int res = 0;
            int str = 0;

            final currentIds = <String>{};

            int roamSafeToWild = 0;
            int roamWildToSafe = 0;

            for (final e in state.entities) {
              currentIds.add(e.id);
              if (e.zone == Zone.safe) eSafe++;
              if (e.zone == Zone.wilderness) eWild++;

              if (e.type == EntityType.npc) npc++;
              if (e.type == EntityType.resource) res++;
              if (e.type == EntityType.structure) str++;

              factionCounts[e.faction] = (factionCounts[e.faction] ?? 0) + 1;

              if (previousEntityZones.containsKey(e.id)) {
                final oldZone = previousEntityZones[e.id];
                if (oldZone != e.zone) {
                  if (oldZone == Zone.safe && e.zone == Zone.wilderness) {
                    roamSafeToWild++;
                  }
                  if (oldZone == Zone.wilderness && e.zone == Zone.safe) {
                    roamWildToSafe++;
                  }
                }
              }
              previousEntityZones[e.id] = e.zone;
            }
            previousEntityZones.removeWhere((k, v) => !currentIds.contains(k));

            if (roamSafeToWild > 0 || roamWildToSafe > 0) {
              print(
                'Census: Roaming - Safe->Wild: $roamSafeToWild, Wild->Safe: $roamWildToSafe',
              );
            }

            final despawnedCount = previousEntityIds
                .difference(currentIds)
                .length;
            final respawnedCount = currentIds
                .difference(previousEntityIds)
                .length;
            previousEntityIds = currentIds;

            print(
              'Census: World update - P: ${state.players.length} (Safe: $safeCount, Wild: $wildCount), E: ${state.entities.length} (Safe: $eSafe, Wild: $eWild), Types (N: $npc, R: $res, S: $str), Despawned: $despawnedCount, Respawned: $respawnedCount',
            );

            // Faction Census (Phase 019)
            if (factionCounts.isNotEmpty) {
              final summary = factionCounts.entries
                  .map((e) => '${e.key.name}: ${e.value}')
                  .join(', ');
              print('Census: Faction Distribution: $summary');
            }

            // Proximity Census
            int totalProximities = 0;
            for (final count in state.playerProximityCounts.values) {
              totalProximities += count;
            }
            if (totalProximities > 0) {
              print('Census: Total proximities this tick: $totalProximities');
            }

            // Cluster Census (Phase 017)
            if (state.largestClusterSize > 0) {
              print(
                'Census: Largest cluster: ${state.largestClusterSize} entities',
              );
              if (state.zoneClusterCounts.isNotEmpty) {
                final summary = state.zoneClusterCounts.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join(', ');
                print('Census: Clusters by zone: $summary');
              }
            }

            // Group Census (Phase 018)
            if (state.groupCount > 0) {
              print(
                'Census: Group Stats - Count: ${state.groupCount}, Avg Size: ${state.averageGroupSize.toStringAsFixed(1)}',
              );
              // Note: Migration pattern logic implies tracking movement direction, but simple summary requested.
              // "Print aggregated group information".
            }
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
