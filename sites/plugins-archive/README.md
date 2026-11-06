Retired yt-dlp plugins, kept so they can be restored. Nothing here is passed to yt-dlp.

| Plugin | Replaced by | Restore |
|---|---|---|
| `siphon/yt_dlp_plugins/extractor/puncher_tube.py` | `recipe` in the `puncher-tube` entry | Move it back to `sites/plugins/siphon/yt_dlp_plugins/extractor/`, then in `sites/sites.json` set `"method": "plugin"`, add `"plugin": "siphon/yt_dlp_plugins/extractor/puncher_tube.py"`, remove `recipe`, and bump `lastTested`. |
| `siphon/yt_dlp_plugins/extractor/hqporner.py` | `recipe` in the `hqporner-com` entry | Same steps with `hqporner.py` and the `hqporner-com` entry. |
| `siphon/yt_dlp_plugins/extractor/ashemaletube.py` | `recipe` in the `ashemaletube-com` entry (browser fetch + pattern) | Same steps with `ashemaletube.py` and the `ashemaletube-com` entry; the plugin was last live in commit `4afbf07`. |

The git tag `plugins-before-recipes` marks the last commit where both sites used these plugins.
