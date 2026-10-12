import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// What the creature can choose to do when asked for its own will.
enum CreatureAction {
  nothing,
  demandSunlight,
  requestGrass,
  requestWalk,
  inventQuest,
  sing,
  nap,
  ask,
}

/// The creature's self-chosen move — an action plus the line it
/// speaks. Produced by Gemma's native function calling (or the
/// fake heuristic in demo mode).
class Decision {
  const Decision({
    required this.action,
    required this.line,
    this.args = const {},
  });

  final CreatureAction action;
  final String line;
  final Map<String, dynamic> args;
}

CreatureAction actionFromName(String name) => switch (name) {
      'demand_sunlight' => CreatureAction.demandSunlight,
      'request_grass' => CreatureAction.requestGrass,
      'request_walk' => CreatureAction.requestWalk,
      'invent_quest' => CreatureAction.inventQuest,
      'sing' => CreatureAction.sing,
      'nap' => CreatureAction.nap,
      'ask' => CreatureAction.ask,
      _ => CreatureAction.nothing,
    };

const _lineProp = {
  'line': {
    'type': 'string',
    'description':
        'What the creature says out loud — in character, 1-2 sentences.',
  },
};

const _lineSchema = {
  'type': 'object',
  'properties': _lineProp,
  'required': ['line'],
};

/// Tool schemas offered to the model when it decides what it wants.
/// Every tool carries `line` — what the creature says — so a single
/// function call produces action + dialogue together.
final creatureTools = <Tool>[
  const Tool(
    name: 'nothing',
    description:
        'Do nothing special — just say something. Use when content.',
    parameters: _lineSchema,
  ),
  const Tool(
    name: 'demand_sunlight',
    description:
        'Ask to be taken into sunlight. Use when energy is low or '
        'you miss the sun.',
    parameters: _lineSchema,
  ),
  const Tool(
    name: 'request_grass',
    description:
        'Ask for grass to eat. Use when hunger is low or you are '
        'peckish.',
    parameters: _lineSchema,
  ),
  const Tool(
    name: 'request_walk',
    description:
        'Ask to be carried outside for a walk together.',
    parameters: _lineSchema,
  ),
  const Tool(
    name: 'invent_quest',
    description:
        'Invent a small real-world quest for the human — something '
        'to find, photograph, or do outside. Use occasionally.',
    parameters: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string'},
        'description': {'type': 'string'},
        'kind': {
          'type': 'string',
          'enum': ['sunlight', 'grass', 'photo', 'walk'],
          'description':
              'photo = verify a picture with the vision model; '
              'sunlight/grass = completed by that feed; '
              'walk = completed by walking together.',
        },
        'verify_prompt': {
          'type': 'string',
          'description':
              'For kind=photo only: a yes/no question about the '
              'photo that verifies completion.',
        },
        ..._lineProp,
      },
      'required': ['title', 'description', 'kind', 'line'],
    },
  ),
  const Tool(
    name: 'sing',
    description: 'Sing a little happy tune.',
    parameters: _lineSchema,
  ),
  const Tool(
    name: 'nap',
    description: 'Decide to fall asleep right now, voluntarily.',
    parameters: _lineSchema,
  ),
  const Tool(
    name: 'ask',
    description:
        'Ask the human a question about the outside world.',
    parameters: {
      'type': 'object',
      'properties': {
        'question': {'type': 'string'},
      },
      'required': ['question'],
    },
  ),
];
