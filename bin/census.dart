import 'dart:io';
import 'package:grimreach_api/protocol.dart';
import 'package:grimreach_api/messages.dart';
import 'package:grimreach_api/message_codec.dart';
import 'package:grimreach_api/world_state.dart';
import 'package:grimreach_api/zone.dart';
import 'package:grimreach_api/entity_type.dart';
import 'package:grimreach_api/faction.dart';
import 'package:grimreach_api/season.dart';
import 'package:grimreach_api/lunar_phase.dart';
import 'package:grimreach_api/constellation.dart';
import 'package:grimreach_api/harmonic_state.dart';

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
    final environmentDuration =
        <String, int>{}; // State -> Duration (Phase 028)
    String lastEnvironment = 'calm';
    final hazardDuration = <String, int>{}; // Zone -> Duration
    final lastHazards = <String, String>{}; // Zone -> Hazard Name
    Season lastSeason = Season.spring;
    int seasonDuration = 0;
    LunarPhase lastLunarPhase = LunarPhase.newMoon;
    int lunarDuration = 0;
    Constellation lastConstellation = Constellation.wanderer;
    int constellationDuration = 0;
    HarmonicState lastHarmonicState = HarmonicState.nullState;
    int harmonicDuration = 0;

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

            // Environment (Phase 028)
            final currentEnv = state.globalEnvironment;
            if (currentEnv != lastEnvironment) {
              environmentDuration[lastEnvironment] = 0;
              lastEnvironment = currentEnv;
              print('Census: Environment Cycle Change -> $currentEnv');
            }
            environmentDuration[currentEnv] =
                (environmentDuration[currentEnv] ?? 0) + 1;

            if (environmentDuration[currentEnv]! % 20 == 0) {
              if (currentEnv == 'storm') {
                print(
                  'Census: STORM ACTIVE for ${environmentDuration[currentEnv]} ticks - Spawns HALTED',
                );
              } else if (currentEnv == 'fog') {
                print(
                  'Census: FOG ACTIVE for ${environmentDuration[currentEnv]} ticks - Movement SLOWED',
                );
              }
            }

            // Hazard Cycles (Phase 029)
            state.zoneHazards.forEach((zone, hazard) {
              final last = lastHazards[zone] ?? 'none';
              if (hazard != last) {
                print('Census: Hazard Cycle Change [$zone] -> $hazard');
                hazardDuration[zone] = 0;
                lastHazards[zone] = hazard;
              }
              hazardDuration[zone] = (hazardDuration[zone] ?? 0) + 1;

              if (hazard != 'none' && hazardDuration[zone]! % 20 == 0) {
                String effect = '';
                if (hazard == 'wildfire') effect = 'suppressing spawns';
                if (hazard == 'stormSurge') {
                  effect = 'reducing capacity & pushing migration';
                }
                if (hazard == 'toxicFog') effect = 'slowing movement';
                if (hazard == 'quake') effect = 'reducing influence gain';
                print(
                  'Census: Hazard Active [$zone]: $hazard for ${hazardDuration[zone]} ticks ($effect)',
                );
              }
            });

            // Seasonal Cycles (Phase 030)
            if (state.currentSeason != lastSeason) {
              print(
                'Census: Season Cycle Change -> ${state.currentSeason.name}',
              );
              lastSeason = state.currentSeason;
              seasonDuration = 0;
            }
            seasonDuration++;

            if (seasonDuration % 20 == 0) {
              String effect = '';
              switch (state.currentSeason) {
                case Season.spring:
                  effect = 'Increasing Spawn Rate (+50%)';
                  break;
                case Season.summer:
                  effect = 'Boosting Influence Gain (+25%)';
                  break;
                case Season.autumn:
                  effect = 'Reducing Pressure (Decay x2)';
                  break;
                case Season.winter:
                  effect = 'Slowing Movement (-25%)';
                  break;
              }
              print(
                'Census: Season Active: ${state.currentSeason.name} for $seasonDuration ticks ($effect)',
              );
            }

            // Phase 031: Lunar Cycles
            if (state.currentLunarPhase != lastLunarPhase) {
              print(
                'Census: Lunar Phase Change -> ${state.currentLunarPhase.name.toUpperCase()}',
              );
              lastLunarPhase = state.currentLunarPhase;
              lunarDuration = 0;
            }
            lunarDuration++;

            if (lunarDuration % 20 == 0) {
              String effect = '';
              switch (state.currentLunarPhase) {
                case LunarPhase.newMoon:
                  effect = 'Reduced Influence Gain (x0.75)';
                  break;
                case LunarPhase.waxing:
                  effect = 'Increased Migration Pressure (push)';
                  break;
                case LunarPhase.fullMoon:
                  effect = 'Reflected: +Spawn Rate, +Hazards Effect';
                  break;
                case LunarPhase.waning:
                  effect = 'Increased Influence Decay (x1.25)';
                  break;
              }
              print(
                'Census: Lunar Phase Active: ${state.currentLunarPhase.name} for $lunarDuration ticks ($effect)',
              );
            }

            // Phase 032: Constellation Cycles
            if (state.currentConstellation != lastConstellation) {
              print(
                'Census: Constellation Change -> ${state.currentConstellation.name.toUpperCase()}',
              );
              lastConstellation = state.currentConstellation;
              constellationDuration = 0;
            }
            constellationDuration++;

            if (constellationDuration % 20 == 0) {
              String effect = '';
              switch (state.currentConstellation) {
                case Constellation.wanderer:
                  effect = 'Flowing: ++Migration Pr (Safe & Wild)';
                  break;
                case Constellation.crown:
                  effect = 'Ruling: +Order Influence Gain';
                  break;
                case Constellation.serpent:
                  effect = 'Coiling: +Chaos Pressure';
                  break;
                case Constellation.forge:
                  effect = 'Striking: +Hazard Intensity (Influence)';
                  break;
              }
              print(
                'Census: Constellation Active: ${state.currentConstellation.name} for $constellationDuration ticks ($effect)',
              );
            }

            // Phase 033: Harmonic Cycles
            if (state.currentHarmonicState != lastHarmonicState) {
              print(
                'Census: Harmonic Shift -> ${state.currentHarmonicState.name.toUpperCase()}',
              );
              lastHarmonicState = state.currentHarmonicState;
              harmonicDuration = 0;
            }
            harmonicDuration++;

            if (harmonicDuration % 20 == 0) {
              String effect = '';
              switch (state.currentHarmonicState) {
                case HarmonicState.resonance:
                  effect = 'Resonance: +Global Influence Gain';
                  break;
                case HarmonicState.discordance:
                  effect = 'Discordance: +Chaos Pressure';
                  break;
                case HarmonicState.amplification:
                  effect = 'Amplification: ++Hazard Intensity';
                  break;
                case HarmonicState.nullState:
                  effect = 'Null State: -Migration Flow';
                  break;
              }
              print(
                'Census: Harmonic State Active: ${state.currentHarmonicState.name} for $harmonicDuration ticks ($effect)',
              );
            }

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
