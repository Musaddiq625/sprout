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
  static const sleepOverlay = Key('sleepOverlay');
  static const dreamBubble = Key('dreamBubble');
  static const thinkingBubble = Key('thinkingBubble');
  static const sleepHint = Key('sleepHint');
  static const petHeart = Key('petHeart');
  static const moodChip = Key('moodChip');
  static const creatureName = Key('creatureName');
  static const mealsButton = Key('mealsButton');
  static const nameField = Key('nameField');
  static const nameSaveButton = Key('nameSaveButton');
  static const wantBubble = Key('wantBubble');
  static const walkBadge = Key('walkBadge');
  static const dialogueBubble = Key('dialogueBubble');
  static const evolveRing = Key('evolveRing');
  static const evolveQuestChip = Key('evolveQuestChip');
  static const resetButton = Key('resetButton');
  static const magnifierBadge = Key('magnifierBadge');

  // Sunbathe — ambient light feed on the creature page
  static const sunBanner = Key('sunBanner');
  static const sunRays = Key('sunRays');
  static const luxValue = Key('luxValue');
  static const sunlightFillBar = Key('sunlightFillBar');

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
  static const wishList = Key('wishList');
  static const wishShowPhoto = Key('wishShowPhoto');
  static const wishVerifyPrompt = Key('wishVerifyPrompt');

  // Meals page
  static const mealsGrid = Key('mealsGrid');

  // Story page
  static const storyButton = Key('storyButton');
  static const growthTimeline = Key('growthTimeline');
  static const wifiChip = Key('wifiChip');
  static const airplaneChip = Key('airplaneChip');
  static const gemmaChip = Key('gemmaChip');
  static const careLogList = Key('careLogList');

  // Model manager
  static const downloadGemmaButton = Key('downloadGemmaButton');
  static const importModelButton = Key('importModelButton');
  static const cancelDownloadButton = Key('cancelDownloadButton');
  static const modelProgressBar = Key('modelProgressBar');
  static const modelStatusLabel = Key('modelStatusLabel');
}
