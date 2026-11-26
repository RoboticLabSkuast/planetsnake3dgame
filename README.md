# Planet Snake 3D

Classic arcade Snake reimagined on a realistic 3D planetary globe, built with **Godot 4.7.2** for **Windows**, **Android**, and **iOS**.

## Downloads

Pre-built binaries are published on the [**GitHub Releases**](https://github.com/RoboticLabSkuast/planetsnake3dgame/releases/latest) page:

- **Android (`.apk`)**: Download `PlanetSnake3D.apk` from [Releases](https://github.com/RoboticLabSkuast/planetsnake3dgame/releases/latest) and install directly on your Android device.
- **Windows (`.exe` / `.zip`)**: Download `PlanetSnake3D-Windows-x64.zip` from [Releases](https://github.com/RoboticLabSkuast/planetsnake3dgame/releases/latest), extract it, and run `PlanetSnake3D.exe`.
- **iOS (Xcode Project)**: Download `PlanetSnake3D-iOS-Xcode.zip` from [Releases](https://github.com/RoboticLabSkuast/planetsnake3dgame/releases/latest), open in Xcode on macOS, and sign with your Apple Developer team.

## Features

- **True Spherical 4-Connected Grid (`SphereGrid`)**: Equiangular cubed-sphere topology configurable from **`2x2` (`24` cells) up to `14x14` (`1,176` cells)** per face (`N x N x 6`) with seamless face/corner transitions, smooth spherical interpolation (`slerp`), rolling terrain bumps, and parallel-transport camera movement (zero polar gimbal flip).
- **Realistic Procedural 3D Visuals & Particle Effects**:
  - Sculpted continuous scaly viper body with Chaikin turn smoothing, sinusoidal slither motion, tapered tail, and **4 selectable shaders/skins** (**Emerald Viper**, **Magma Cobra**, **Frost Python**, **Royal Gold**).
  - Articulated 3D snake head with lower jaw animation, glossy slit-pupil eyes, flicking forked tongue, and translucent Shield energy aura.
  - Multi-layered GPU **particle VFX** (Boost spark trails, biome-tinted slither dust, Golden Fruit & power-up auras, crash explosions, distant shooting stars) plus additive 3D **surface shockwave rings**.
  - Multi-food crimson & golden bonus apples, continuous carved stone walls, rocky terrain bumps, atmospheric Rayleigh limb rim shader, drifting **orbital cloud shell**, distant cratered Moon, and starry deep-space skybox.
  - **Night-Side Orbital Street Lamps**: Sculpted miniature street lamps on grid intersections cast soft warm lantern glow pools across the dark hemisphere with moonlit grid rows so every lane remains clear on the night side.
  - Three selectable planetary biomes: **Mossy Terra**, **Volcanic Basalt** (animated magma cracks), and **Desert Sandstone**.
- **Classic Gameplay, Power-Ups & Modes**:
  - **Classic**: Stone walls, terrain bumps, multi-apple globe spawning, gradual speed progression over time + apples, 2-input turn buffering, combo scoring, timed golden bonus fruits, and **3D Power-Ups** (**Shield** to shatter 1 obstacle, **Magnet 2x** to pull nearby apples & double points, **Frost** to slow speed).
  - **Arcade**: Denser stone walls and rocky bumps across the planet.
  - **Open**: Pure obstacle-free spherical Snake (with **Magnet 2x** & **Frost**).
  - **Camera Modes**: `Globe 4-Way` (screen-relative WASD/Arrows/Swipe) or close-up `3D Chase` (behind-the-head left/right steering with dynamic Boost FOV punch).
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
- `assets/shaders/` — `planet_surface.gdshader`, `planet_clouds.gdshader`, `snake_skin.gdshader`, `atmosphere.gdshader`, `starfield.gdshader`
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
