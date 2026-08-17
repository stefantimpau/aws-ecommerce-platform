# Product photos go here

Drop a photo per product, named exactly `<productId>.jpg` (or `.jpeg` / `.png` / `.webp`) — e.g. `prod-001.jpg`. `seed.js` picks up any file here automatically and uses it instead of the generated placeholder box for that product; anything without a matching file here still gets the placeholder, so you can do this incrementally.

The current 8 photos here are the site owner's own, taken specifically for this project — no stock-photo licensing question. `products.json` only lists the 8 products with a real photo; the two that never got one (a monitor arm, a hardware security key) were removed from the catalog entirely rather than left showing a stock photo or an indefinite placeholder — see `seed.js`'s `removeStaleProducts()` for how removing an entry here also removes its stale row from DynamoDB, not just skips re-adding it.

If you add a product back (or a new one) with your own photo: add its entry to `products.json`, drop the matching file here, and re-run `npm run seed` from `scripts/seed/` — no other code changes needed.

Photos should be resized to something reasonable before dropping them in (this project resizes to ~1200px wide, JPEG quality ~82) — a phone camera's full-resolution original can be several MB, and the catalog page loads all of them at once.

After dropping files here, re-run `npm run seed` from `scripts/seed/` to upload them and reconcile the table; re-running `../deploy-frontend.sh` is NOT needed — the frontend reads images and product data by URL at request time, not at build time, so a re-seed alone is enough. If old images or removed products still show, see the CloudFront cache note in the main README's Incident Notes — the `/images/*` path caches for 24 hours at the edge, so a stale photo (not a stale product listing — that's DynamoDB, no caching) may need `aws cloudfront create-invalidation --paths "/images/*"` to update immediately instead of waiting out the TTL.
