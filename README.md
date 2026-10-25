# Sprout

A creature that needs you to go outside. On-device AI, sunlight detection, grass verification.

Built for [Hacktoberfest 2026 — Week 1: Touch Grass](https://dev.to/challenges/hacktoberfest-week1-2026-10-05).

<img width="2251" height="953" alt="sprout mockup" src="https://github.com/user-attachments/assets/efce12a1-a55f-4f51-9cbd-4c7b1607bd8a" />

## What it is

Sprout is a small creature that lives on your phone. It hatches from an egg, then survives on two things:

- **Sunlight** — detected by the Android ambient light sensor (`TYPE_LIGHT`), no camera needed
- **Grass** — confirmed by a green-pixel HSV classifier, with Gemma vision as a borderline arbiter

Every line the creature speaks — its greeting, its gratitude, its confusion when you show it something that isn't grass — is generated on-device by Gemma 4 E2B running locally through LiteRT-LM. No network call, no API key, no data leaves the device.

## Why open-source AI

- **Private by design**: photos of your environment, your outdoor habits, your streak — nothing leaves the device
- **Offline**: the creature works in a forest with no signal
- **Inspect**: the model is an open `.litertlm` file you can read, swap, or fine-tune
- **Zero cost**: no API bill, ever

## Stack

| Layer | Tech |
|---|---|
| App | Flutter 3.44.5 / Dart 3.12.2 |
| AI | Gemma 4 E2B `.litertlm` via `flutter_edge_ai` |
| Lux sensor | Native `EventChannel` → Android `TYPE_LIGHT` |
| Grass gate | Custom HSV pixel classifier (no model call needed) |
| Storage | `sqflite` — creature state, care log, quest progress |
| Camera | `camera` + `image_picker` |

## Quick start

```bash
# Requires FVM with Flutter 3.44.5
fvm flutter pub get
fvm flutter run           # Android device, API 30+, arm64

# Run tests
fvm flutter test

# Build APK
fvm flutter build apk --debug
```

## Project structure

```
lib/
  main.dart                    # init + hatch routing
  src/
    creature/                  # state, store, controller, lux service
    vision/                    # grass gate, image prep, camera service
    ai/                        # Gemma client, prompts, model manager
    ui/                        # screens + widgets
assets/
  quests/quests.json           # 12 quests across 3 chapters
  testpack/                    # synthetic test images (no attribution needed)
tool/
  generate_testpack.dart       # regenerate test images
```

## License

MIT

<p align="center">Built with ❤️ by Musaddiq625</p>
