# Planet Snake 3D

Classic arcade Snake reimagined on a realistic 3D planetary globe, built with **Godot 4.7.2** for **Windows**, **Android**, and **iOS**.

## Downloads

Pre-built binaries are published on the [**GitHub Releases**](https://github.com/RoboticLabSkuast/planetsnake3dgame/releases/latest) page:

- **Android (`.apk`)**: Download `PlanetSnake3D.apk` from [Releases](https://github.com/RoboticLabSkuast/planetsnake3dgame/releases/latest) and install directly on your Android device.
- **Windows (`.exe` / `.zip`)**: Download `PlanetSnake3D-Windows-x64.zip` from [Releases](https://github.com/RoboticLabSkuast/planetsnake3dgame/releases/latest), extract it, and run `PlanetSnake3D.exe`.
- **iOS (Xcode Project)**: Download `PlanetSnake3D-iOS-Xcode.zip` from [Releases](https://github.com/RoboticLabSkuast/planetsnake3dgame/releases/latest), open in Xcode on macOS, and sign with your Apple Developer team.

## Features

- **True Spherical 4-Connected Grid (`SphereGrid`)**: Equiangular cubed-sphere topology (`8x8`, `10x10`, or `14x14` per face = `384`, `600`, or `1,176` cells) with seamless face/corner transitions, smooth spherical interpolation (`slerp`), rolling terrain bumps, and parallel-transport camera movement (zero polar gimbal flip).
- **Realistic Procedural 3D Visuals**:
  - Sculpted continuous scaly viper body with Chaikin turn smoothing, sinusoidal slither motion, and tapered tail.
  - Articulated 3D snake head with lower jaw animation, glossy amber slit-pupil eyes, and flicking forked tongue.
  - Multi-food crimson & golden bonus apples, continuous 3D carved stone walls and rocky terrain bumps, cast directional shadows, atmospheric Fresnel rim shader, distant cratered Moon, and starry deep-space skybox.
  - Three selectable planetary biomes: **Mossy Terra**, **Volcanic Basalt** (animated magma cracks), and **Desert Sandstone**.
- **Classic Gameplay & Modes**:
  - **Classic**: Stone walls, terrain bumps, multi-apple globe spawning, gradual speed progression over time + apples, 2-input turn buffering, combo scoring, and timed golden bonus fruits.
  - **Arcade**: Denser stone walls and rocky bumps across the planet.
  - **Open**: Pure obstacle-free spherical Snake.
  - **Camera Modes**: `Globe 4-Way` (screen-relative WASD/Arrows/Swipe) or close-up `3D Chase` (behind-the-head left/right steering).
- **Cross-Platform Input & Responsive Safe-Area UI**:
  - **Windows**: `WASD` / `Arrow Keys` to turn, `Space` / `Shift` to boost, `Mouse Wheel` to zoom, `P` / `Esc` to pause, `R` to quick-restart.
  - **Android & iOS**: Instant low-latency swipe gestures, two-finger pinch zoom, on-screen virtual D-Pad + Boost button, notch/safe-area padding, and haptic vibration feedback.

## Project Structure

- `scenes/main.tscn` — Main entry scene
- `scripts/sphere_grid.gd` — Equiangular cube-sphere topology, terrain bumps, and mesh builder
- `scripts/snake_logic.gd` — Pure classic Snake simulation, walls/bumps generation, & turn-buffer state machine
- `scripts/procedural_meshes.gd` — Dynamic snake body extrusion, sculpted head/apple/boulder/wall generators
- `scripts/game_controller.gd` — 3D lighting, shaders, camera, particles, audio, and persistence
- `scripts/ui_controller.gd` — Subway-Surfers-style open 3D start screen, HUD, modals, swipe/pinch & virtual D-Pad
- `assets/shaders/` — `planet_surface.gdshader`, `atmosphere.gdshader`, `starfield.gdshader`
- `assets/textures/` & `assets/audio/` — Generated PBR maps, UI icons, and WAV sound effects
- `tools/generate_assets.py` — Reproducible Python asset generator (`numpy`, `Pillow`, `wave`)
- `tests/run_tests.gd` — Automated headless topology, game logic, mesh, and scene tests

## Running Automated Tests

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless -s res://tests/run_tests.gd
```

## Exporting Locally

All export presets are pre-configured in `export_presets.cfg`.

### Windows
```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --export-release "Windows Desktop" build/windows/PlanetSnake3D.exe
```

### Android
```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --export-debug "Android" build/android/PlanetSnake3D.apk
adb install -r build/android/PlanetSnake3D.apk
```

### iOS
```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --export-release "iOS" build/ios/PlanetSnake3D_iOS.ipa
```
Open `build/ios/PlanetSnake3D_iOS.xcodeproj` in Xcode on macOS, configure your Apple Developer Team & bundle ID (`com.planetsnake.game3d`), and build/archive.
