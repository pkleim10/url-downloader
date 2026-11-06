yt-dlp plugins for sites that need custom extraction. Siphon passes this folder to yt-dlp
with `--plugin-dirs`; each plugin is listed in `../sites.json`.

yt-dlp looks for plugin packages one level below a plugin directory, so the layout is
`siphon/yt_dlp_plugins/extractor/<name>.py` (a `yt_dlp_plugins` folder directly in this
folder is ignored).
