Retired yt-dlp plugins, kept so they can be restored. Nothing here is passed to yt-dlp, and no site uses a plugin today: each of these sites now runs on a built-in recipe with no site-specific settings.

| Plugin | Replaced by | Restore |
|---|---|---|
| `siphon/yt_dlp_plugins/extractor/puncher_tube.py` | `{"base": "followEmbed"}` in the `puncher-tube` entry | Move it back to `sites/plugins/siphon/yt_dlp_plugins/extractor/`, then in `sites/sites.json` set `"method": "plugin"`, set `"plugin": "siphon/yt_dlp_plugins/extractor/puncher_tube.py"`, remove `recipe`, and bump `lastTested`. |
| `siphon/yt_dlp_plugins/extractor/hqporner.py` | `{"base": "smartScan"}` in the `hqporner-com` entry | Same steps with `hqporner.py` and the `hqporner-com` entry. |
| `siphon/yt_dlp_plugins/extractor/ashemaletube.py` | `{"base": "playerConfig"}` in the `ashemaletube-com` entry | Same steps with `ashemaletube.py` and the `ashemaletube-com` entry; the plugin was last live in commit `4afbf07`. |

The git tag `plugins-before-recipes` marks the last commit where puncher.tube and hqporner used these plugins.
