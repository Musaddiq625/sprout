import 'package:flutter/foundation.dart';

/// Element keys for widget tests. Never tap by coordinates.
class KeyConstants {
  KeyConstants._();

  // Hatch
  static const hatchEgg = Key('hatchEgg');
  static const hatchPrompt = Key('hatchPrompt');
  static const hatchCrackProgress = Key('hatchCrackProgress');

  // Creature page
  static const creatureEmoji = Key('creatureEmoji');
  static const creatureDialogue = Key('creatureDialogue');
  static const energyBar = Key('energyBar');
  static const hungerBar = Key('hungerBar');
  static const feedSunlightButton = Key('feedSunlightButton');
  static const feedGrassButton = Key('feedGrassButton');
  static const questsButton = Key('questsButton');
  static const streakChip = Key('streakChip');
  static const modelStatusChip = Key('modelStatusChip');

  // Sunlight page
  static const luxValue = Key('luxValue');
  static const sunlightFillBar = Key('sunlightFillBar');
  static const holdSteadyButton = Key('holdSteadyButton');
  static const sunlightBackButton = Key('sunlightBackButton');

  // Grass page
  static const grassPhotoPreview = Key('grassPhotoPreview');
  static const feedGrassConfirm = Key('feedGrassConfirm');
  static const grassRetryButton = Key('grassRetryButton');
  static const grassGateResult = Key('grassGateResult');
  static const cameraButton = Key('cameraButton');
  static const galleryButton = Key('galleryButton');
  static const testPackButton = Key('testPackButton');
  static const grassBackButton = Key('grassBackButton');

  // Quest page
  static const questList = Key('questList');
  static const chapter1Header = Key('chapter1Header');

  // Model manager
  static const downloadGemmaButton = Key('downloadGemmaButton');
  static const importModelButton = Key('importModelButton');
  static const cancelDownloadButton = Key('cancelDownloadButton');
  static const modelProgressBar = Key('modelProgressBar');
  static const modelStatusLabel = Key('modelStatusLabel');
}
