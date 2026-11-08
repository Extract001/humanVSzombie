# Research / spikes

Throwaway experiments that informed design decisions. **Not game code.** Files are kept as `.txt` so Godot never imports or runs them.

## lighting_spike (2026-11-08)
Question: can a dark warehouse interior exist inside one continuous scene, without darkening the outdoor street, using Godot 4.7.2's Compatibility renderer?

Method: a standalone project rendered with Godot 4.7.2 (Linux, `--rendering-driver opengl3`, Mesa llvmpipe software OpenGL, virtual X display). The interior darkness is a Subtract-mode `PointLight2D` with a soft rectangular mask; the flashlight is an Add-mode `PointLight2D` cone with shadows; zombie eyes use an Unshaded material.

Result `[LINUX-AUTO]` (pixel luminance 0–1):

| Probe | Value | Check |
|-------|-------|-------|
| Outdoor street | 0.459 | > 0.40 ✅ |
| Street just outside the doorway | 0.459 | > 0.40 ✅ |
| Interior floor (dark) | 0.053 | < 0.10 ✅ |
| Interior floor in the flashlight cone | 0.395 | > 0.30 ✅ |
| Behind a shelf (flashlight shadow) | 0.053 | < 0.10 ✅ |
| Zombie eyes in the dark | 0.826 | > 0.50 ✅ |

Screenshot: `lighting_spike.png`. Code: `lighting_spike_main.gd.txt`.

Observed issue to handle in production: the mask also darkened the building's outer walls (visible as a dark rim). Fix: light cull masks so walls and roofs aren't affected, and a mask sized exactly to the floor.

Limits: software rendering on Linux. It does **not** show how this looks on your Windows GPU or in a browser. Those are checked in Phase 1 (test-yard dark room) as `[WIN-PLAY]`, `[VISUAL]` and `[WEB-EXPORT]`.
