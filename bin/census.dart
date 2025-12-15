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
    // Persistent State for Trends (Phase 023)
    final moraleTrendDuration =
        <Faction, int>{}; // Faction -> Ticks in current trend
    final lastMorale = <Faction, double>{}; // Faction -> Previous Score
    final trendDirection =
        <Faction, int>{}; // 1 = rising, -1 = falling, 0 = stable
    final saturationDuration =
        <String, int>{}; // Zone -> Ticks in non-normal state
    final migrationDuration =
        <String, int>{}; // Zone -> Ticks in high pressure state

    // Connect
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
            }

            // Morale Trends (Phase 023)
            state.factionMorale.forEach((faction, score) {
              final prevScore = lastMorale[faction] ?? 50.0;
              final diff = score - prevScore;

              int currentDir = 0;
              if (diff > 0) {
                currentDir = 1;
              } else if (diff < 0) {
                currentDir = -1;
              }

              final lastDir = trendDirection[faction] ?? 0;

              if (currentDir != 0 && currentDir == lastDir) {
                moraleTrendDuration[faction] =
                    (moraleTrendDuration[faction] ?? 0) + 1;
              } else {
                moraleTrendDuration[faction] = 1; // New trend or stable
              }

              trendDirection[faction] = currentDir;
              lastMorale[faction] = score;

              // Log if significant trend
              if (moraleTrendDuration[faction]! > 2 && currentDir != 0) {
                String dirStr = currentDir > 0 ? 'Rising' : 'Falling';
                print(
                  'Census: Morale Trend: ${faction.name} $dirStr for ${moraleTrendDuration[faction]} ticks (Current: ${score.toStringAsFixed(1)})',
                );
              }
            });

            // Influence Modifiers (Phase 024)
            if (state.factionInfluenceModifiers.isNotEmpty) {
              final mods = state.factionInfluenceModifiers.entries
                  .map((e) {
                    String type = e.value > 1.0
                        ? 'Boosted'
                        : (e.value < 1.0 ? 'Suppressed' : 'Normal');
                    return '${e.key.name}: $type (${e.value.toStringAsFixed(2)}x)';
                  })
                  .join(', ');
              print('Census: Influence Modifiers: $mods');
            }

            // Faction Pressure (Phase 025)
            if (state.factionPressure.isNotEmpty) {
              state.factionPressure.forEach((faction, score) {
                if (score > 60.0) {
                  print(
                    'Census: Pressure Surge: ${faction.name} (${score.toStringAsFixed(1)}) - Accelerating Spawns',
                  );
                } else if (score < 40.0) {
                  print(
                    'Census: Pressure Drop: ${faction.name} (${score.toStringAsFixed(1)}) - Slowing Spawns',
                  );
                }
              });
            }

            // Zone Saturation (Phase 026)
            final saturationSummary = <String>[];
            state.zoneSaturation.forEach((zone, stateStr) {
              if (stateStr != 'normal') {
                saturationDuration[zone] = (saturationDuration[zone] ?? 0) + 1;
                saturationSummary.add(
                  '$zone($stateStr, ${saturationDuration[zone]}t)',
                );
              } else {
                saturationDuration[zone] = 0;
              }
            });

            if (saturationSummary.isNotEmpty) {
              print(
                'Census: Saturation Alert: ${saturationSummary.join(', ')}',
              );
            }

            // Migration Pressure (Phase 027)
            state.migrationPressure.forEach((zone, pressure) {
              if (pressure > 50.0) {
                migrationDuration[zone] = (migrationDuration[zone] ?? 0) + 1;
                if (migrationDuration[zone]! % 10 == 0) {
                  // Log every 10 ticks
                  print(
                    'Census: Migration Push Active in $zone ($pressure) for ${migrationDuration[zone]} ticks',
                  );
                }
              } else {
                migrationDuration[zone] = 0;
              }
            });

            // Shift Volatility Census (Phase 022)
            if (state.recentShifts.isNotEmpty) {
              print(
                'Census: ${state.recentShifts.length} territory shifts occurred this tick!',
              );
              // Optional: detail
              // print('Census: Shifts in: ${state.recentShifts.join(", ")}');
            }

            // Territory Census (Phase 020)
            if (state.zoneControl.isNotEmpty) {
              final summary = state.zoneControl.entries
                  .map((e) => '${e.key}: ${e.value.name}')
                  .join(', ');
              print('Census: Territory Control: $summary');
            }

            // Influence Census (Phase 021)
            if (state.zoneInfluence.isNotEmpty) {
              final summary = state.zoneInfluence.entries
                  .map((e) {
                    final scores = e.value;
                    // Find top faction
                    Faction top = Faction.neutral;
                    double maxScore = -1.0;
                    scores.forEach((f, s) {
                      if (s > maxScore) {
                        maxScore = s;
                        top = f;
                      }
                    });
                    return '${e.key}: ${top.name} (${maxScore.toStringAsFixed(1)})';
                  })
                  .join(', ');
              print('Census: Area Influence: $summary');
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
