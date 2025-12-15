# grimreach_census

The passive analytics and observation node for Grimreach.

See also: [Grimreach Design & Architecture](../grimreach_docs/README.md)

## Core Responsibilities
- Observes WorldState broadcasts
- Aggregates and prints systemic summaries
- Tracks long-cycle correlations
- Contains no simulation or gameplay logic

## Architectural Role
Serves as a specialized client that focuses on data aggregation and logging rather than user interaction. It verifies that valid world state is being broadcast and provides insights into the global simulation without participating in it.

## Deterministic Contract Surface
- Input: `WorldState` (via WebSocket)
- Output: `Protocol.handshake` (as census role)
- Output: `Logs/Console Output`

## Explicit Non-Responsibilities
- No gameplay logic
- No world simulation
- No active interference

## Folder/Layout Summary
- `bin/`: Executable entry points.
  - `census.dart`: Main listener loop.
- `lib/`: Shared logic (minimal).

## Development Notes
Run with `dart bin/census.dart`. Intended to run alongside `grimreach_server` for monitoring.
