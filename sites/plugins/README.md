yt-dlp plugins for sites that need custom extraction a recipe can't express (see `recipe`
in `../sites.json`). Siphon passes this folder to yt-dlp with `--plugin-dirs`; each plugin
is listed in `../sites.json`. Retired plugins live in `../plugins-archive/`.

yt-dlp looks for plugin packages one level below a plugin directory, so the layout is
`siphon/yt_dlp_plugins/extractor/<name>.py` (a `yt_dlp_plugins` folder directly in this
folder is ignored). Siphon removes files from its persistent `plugins/siphon/` that the
app no longer ships.
