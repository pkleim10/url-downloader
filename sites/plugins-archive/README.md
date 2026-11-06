Retired yt-dlp plugins, kept so they can be restored. Nothing here is passed to yt-dlp.

| Plugin | Replaced by | Restore |
|---|---|---|
| `siphon/yt_dlp_plugins/extractor/puncher_tube.py` | `recipe` in the `puncher-tube` entry | Move it back to `sites/plugins/siphon/yt_dlp_plugins/extractor/`, then in `sites/sites.json` set `"method": "plugin"`, add `"plugin": "siphon/yt_dlp_plugins/extractor/puncher_tube.py"`, remove `recipe`, and bump `lastTested`. |
| `siphon/yt_dlp_plugins/extractor/hqporner.py` | `recipe` in the `hqporner-com` entry | Same steps with `hqporner.py` and the `hqporner-com` entry. |

The git tag `plugins-before-recipes` marks the last commit where both sites used these plugins.
