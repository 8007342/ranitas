# Deployment

`main` initially received the construction page in commit `1c5c8c2`.
For that page specifically, check out that commit, `npm ci`, then `npm run deploy`.

For the game:

```sh
npm ci
flutter pub get
npm run build
npm run check:assets
npx wrangler login
npx wrangler deploy
```

Cloudflare build command: `npm run build`. Output: `build/web`.
The build script uses Flutter from PATH (or `FLUTTER_BIN`). If absent, it
fetches the pinned Flutter 3.47.7 SDK into `.cache/flutter` automatically.
Allow the build environment outbound access to GitHub and Flutter artifacts.
Cache `.cache/flutter` between builds when possible.
`npx wrangler deploy` publishes Workers static assets using `wrangler.jsonc`.
The configured custom domain is `ranitas.tlatoani.net`. Deployment requires an
account authorized for the `tlatoani.net` Cloudflare zone. Wrangler provisions
the custom domain and certificate when this authorization exists; an existing
conflicting DNS record may require removal in Cloudflare first.

Alternative Pages deployment: `npm run deploy:pages`. Add the custom domain
in the Pages project's Custom domains settings; Workers routes do not configure
Pages domains. Do not configure both products to own the same hostname.

All gameplay runs locally. No server, database, analytics, remote inference,
API secrets, or audio downloads are needed. Static assets are served directly.
`npm run check:assets` enforces the 25 MiB per-file limit and a conservative
20,000-file ceiling. The Flutter engine is bundled locally rather than loaded
from a third-party CDN. No service worker or offline PWA is registered.

The forge had no Cloudflare authentication (`wrangler whoami`), so a live
Cloudflare deployment or DNS activation cannot be claimed from this session.
