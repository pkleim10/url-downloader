# Tube-site survey: results (2026-11-06)

Sites that yt-dlp 2026.10.26 has no extractor for (or a broken one). Each working site had a
20-second sample of its home page's first video downloaded into `/tmp`, checked with `ffprobe`
and a full `ffmpeg` decode, and deleted. Every site is recorded in `sites/sites.json`.

Result: 24 working (14 by yt-dlp's generic extractor, 10 by recipes), 3 aggregators whose links
work, 2 broken, 5 untested (no public video), 8 offline. No plugins were needed.

## Working

| Site | How | Sample |
|---|---|---|
| 3Movs | yt-dlp generic (HQ preferred) | 1280x720 H.264 |
| Analdin | yt-dlp generic | 960x540 H.264 |
| AnySex | yt-dlp generic | 1920x1080 H.264 |
| BravoTube | yt-dlp generic (HQ preferred) | 1280x720 H.264 |
| KatesTube | yt-dlp generic | 1280x720 AV1 |
| PerfectGirls | yt-dlp generic | 1280x720 H.264 |
| Porn300 | yt-dlp generic | 640x360 H.264 (only quality offered) |
| PornGo | yt-dlp generic | 854x480 H.264 |
| PornHat | yt-dlp generic | 682x480 H.264 |
| PornOne (ex vPorn) | yt-dlp generic | 1920x1080 H.264 |
| PunishBang | yt-dlp generic | 1280x960 H.264 |
| XBabe | yt-dlp generic | 1280x720 H.264 |
| XCafe | yt-dlp generic | 1280x720 H.264 |
| Xozilla | yt-dlp generic | 1280x720 H.264 |
| BoyfriendTV | recipe: playerConfig | 3840x2160 H.264 |
| PornoXO | recipe: playerConfig | 1280x720 H.264 |
| Brighteon | recipe: playerConfig | 1280x720 H.264 |
| SexVid | recipe: playerConfig | 1280x720 H.264 |
| ZBPorn | recipe: playerConfig (reads the player's quality labels) | 898x480 H.264 |
| PornDig | recipe: smartScan | 3840x2160 H.264 |
| Tranny.one | recipe: pageSources | 1280x720 H.264 |
| PornZog | recipe: embedPage (vxxx.com video page) | 1280x720 H.264 |
| IcePorn | recipe: playerAPI | 854x480 H.264 |
| PornDoe | custom recipe (its own data address; 1080p is members-only) | 1280x720 H.264 |
| Fuq / PornHD / GotPorn | aggregator: /out/ links redirect to the host (xHamster, eporner, ...) | 1920x1080 H.264 via xHamster |

## Not working

| Site | Result |
|---|---|
| LindellTV (Frank Speech) | broken: Rumble embeds; yt-dlp's Rumble extractor gets a Cloudflare 403 |
| Hanime | broken: Cloudflare JavaScript challenge even with browser impersonation |
| BitView, Sendvid, Locals, Threads, CloutHub | untested: maintenance, login, paywall or no public videos |
| Veoh, Metacafe, Utreon, Trovo, Streamja, Streamff, ShemaleTubes | offline (no DNS, server down, or parked) |
