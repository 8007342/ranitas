# Ranitas

Two little frogs. Nothing to win. Nowhere to hurry.

A Flutter + Flame widescreen landscape pixel pond for high-resolution displays,
inspired by the gentle premise of Frog Bog. Tap anywhere in the pond to jump;
hold a little or longer to choose a higher arc. Your companion hunts the same
insects. No scores, lives, menus, or replay. Over a few foreground minutes the
landscape and original synthesized soundscape wake up, the light changes, and
both frogs go to sleep. Their pond keeps living. Reloading the page is the only
way to begin another visit.

```sh
npm ci
npm run build
npx wrangler deploy
```

The build uses installed Flutter or downloads pinned Flutter 3.47.7 if absent.
For development: `flutter pub get`, then `flutter run -d web-server
--web-hostname 0.0.0.0 --web-port 8080`. `flutter analyze` and `flutter test`
validate the Dart code. `npm run check:assets` checks the deployment file budget.

Workers custom domain: **ranitas.tlatoani.net** (Cloudflare authentication and
zone access required). See [deployment](docs/deployment.md) for Workers, Pages,
and the original construction page. No PWA service worker is registered.

[Experience specification](openspec/specs/experience/spec.md) ·
[Art & animation styleguide](art/STYLEGUIDE.md) ·
[Research and limits](docs/research.md) ·
[Audio provenance](docs/audio.md)

The browser game occupies a widescreen landscape frame (`641:359` prime logical
canvas backed by `2557 × 1439` prime scenic exports and `1031 × 521` multi-pose
frog sprite sheets) across seven seeded biomes (`willow`, `blossom`, `cypress`,
`maple`, `sanctuary`, `grotto`, and `alpine`). Native builds request landscape
orientation. The current synthesized soundscape targets browsers; native
platform audio is a documented follow-up.
