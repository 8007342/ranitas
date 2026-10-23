# Roadmap

- [x] Publish construction page and Cloudflare configuration to main.
- [x] Initialize OpenSpec and Flutter + Flame for web, Android, and iOS.
- [x] Integrate coherent seeded scenes, generated prime-sized art, frogs, wildlife, and original browser ambience.
- [x] Train and validate a tiny local action prior; keep geometric timing and safety authoritative.
- [x] Validate portrait browser views, touch audio, deployment asset limits, and 22 automated tests.
- [x] Verify 100 seeded worlds and 30 minutes of permanent sleep ambience in model simulation.
- [x] Push game milestones and prepare the tested game for main.

Production deploys automatically from `main` through the connected Cloudflare
Worker using `npm run build` and `npx wrangler deploy`. The custom-domain trigger
is `ranitas.tlatoani.net`; consult the Worker build history for live status.

Future refinement: listening and comfort sessions with real players; physical
phone/tablet performance checks; native Android/iOS audio parity. The delivered
mobile-browser game has synthesized audio; native audio is currently a no-op.
