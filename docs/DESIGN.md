# Brand and interface

**Awake Lock — A little guard for big ideas.**

Friendly without being distracting. Rounded typography, a smiling lavender lock, restrained accents, and a compact native panel.

| Role | Color |
| --- | --- |
| Main actions / mascot | Lavender `#7D66C7` |
| Verified awake state | Mint `#3B876E` |
| Light surface | Warm ivory `#FBF9F6` |
| Dark surface | Charcoal `#1F1F26` |

Use 22 pt outer padding, 16–18 pt card radii, subtle borders, and system typography. The mascot uses SwiftUI vector shapes. No decorative animation is needed; only the session countdown changes continuously.

## State communication

- Outline menu-bar lock: normal sleep allowed.
- Filled lock + dot: native idle-sleep assertion active.
- On Duty / Off Duty: explicit text status, not color alone.
- Closed-lid mode has a separate confirmed helper state.
- Timer chips start immediately and use the saved session duration for selection.

## Recreate the icon

```bash
mkdir -p build/AwakeLock.iconset
swift scripts/make-icon.swift build/AwakeLock.iconset
iconutil -c icns build/AwakeLock.iconset -o Resources/AwakeLock.icns
```

The original icon artwork is included under the repository’s MIT license.
