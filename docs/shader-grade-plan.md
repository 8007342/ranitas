# Enhancement Plan: Shader-Based Colour Grade

Status: **approved as an enhancement plan** (2026-10-25). Not implemented yet.
Today's grade is a 4×5 colour matrix (`lib/game/scene_grade.dart`, design D3),
and it stays as the fallback.

## Why

A colour matrix can only scale, mix and offset channels. That rules out three
things a painter's night grade does:

- **Hue-selective shifts.** Warm skies should go violet while foliage goes
  teal-black and water keeps its jewel cyan. A matrix moves every hue the same
  way.
- **Tone-curve shaping.** Highlights should be crushed while the midtones keep
  their colour, so the art reads as night rather than as "darker".
- **Pixel-art palette fidelity.** Graded colours should snap to a limited
  per-biome night palette with an ordered dither, as 1990s scenery did,
  instead of drifting into thousands of in-between colours.

A 3-D look-up table (LUT) applied in a fragment shader does all of this in one
texture fetch per pixel.

## Approach

1. **LUT authoring as Hald CLUTs.**
   - **Identity:** `magick hald:8 identity.png` produces a 512×512 identity
     image.
   - **Grading:** an artist (or an image-generation agent) grades that image in
     any editor with the same adjustments they would apply to a backdrop. The
     result is the LUT for one keyframe.
   - **Sets:** one set per biome, `art/grade/<biome>-<key>.png`, with key ∈
     `sunset`, `dusk`, `night`. Day stays identity.
   - **Bootstrap:** a script can first bake every LUT from today's matrices, so
     the shader path starts visually identical to the matrix path. Artists then
     refine.
2. **Runtime.**
   - **Shader:** a Flutter `FragmentProgram` (`shaders:` in `pubspec.yaml`,
     GLSL compiled at build time). The shader samples the backdrop texture,
     looks the colour up in two LUTs (the keyframes either side of the current
     daylight), mixes them by a `mix` uniform, adds the rain cloud term, and
     optionally snaps to a 16–32 colour night palette through a 4×4 Bayer
     ordered dither.
   - **Same shader for every painted layer:** canopy, mid-bank, foreground and
     palette cycles each pass their own texture to it.
   - **Emissive pass:** the emissive mask becomes a second sampler, which
     removes today's `saveLayer` + `dstIn` + `plus` composite.
3. **Fallback.** If `FragmentProgram.fromAsset` throws (old browser, shader
   compile failure) or a LUT asset is missing, `SceneGrade` keeps today's matrix
   path. The visual contract is unchanged, only its fidelity.

## Platform notes

- Fragment shaders are supported on Flutter web with the CanvasKit and Skwasm
  renderers, and on Impeller for iOS and Android.
- Web compiles the shader at first use. Warm it once while loading, behind
  `sceneReady()`, so dusk has no hitch.
- Cost: two 3-D LUT fetches (each stored as a 2-D strip with manual slice
  interpolation) per backdrop pixel. That is trivial on any GPU that runs
  the game today. Draw-call count is unchanged.
- `flutter test` support for custom shaders varies by version. Keep the grade
  maths testable by sampling LUT PNGs in Dart, and treat the shader as a thin
  sampler with no logic of its own.

## Tasks

1. Add `scripts/make-grade-luts.mjs` (sharp) that bakes the current matrices
   into Hald CLUTs per biome and key, and an `art/grade/README.md` with the
   authoring workflow.
2. Add `shaders/grade.frag` (backdrop sampler, two LUT samplers, emissive
   sampler, uniforms: mix, cloud, emissive strength, dither on/off).
3. Add `SceneGrade.shaderFor(model)` with a cached `FragmentShader` per layer
   image and the matrix fallback. Switch the backdrop, painted layers and cycles
   over to it.
4. Tests:
   - Dart-side LUT sampling matches the matrix for the bootstrap LUTs.
   - Missing LUTs or a failed shader fall back to the matrix.
   - Smoke renders across all 12 biomes still pass.
5. Request painted LUTs per biome in `art/ASSET_REQUESTS.md`: grade the Hald
   identity image as you would grade the scene at sunset, dusk and night.
6. Check in a browser and on a phone that the shader warm-up has no visible
   stall.

## Risks

- **Web shader compile stall on first use:** mitigated by warming the shader
  during loading.
- **Dither crawl:** an ordered dither in screen space shimmers when layers
  sway. Anchor the dither to texture space, not screen space.
- **Asset count:** 12 biomes × 3 keys = 36 small PNGs (about 100–300 KB each
  as lossless WebP, 512×512). Load only the current biome's three.
