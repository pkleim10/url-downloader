yt-dlp plugins for sites that need custom extraction. The server passes this
folder to yt-dlp with `--plugin-dirs`; each plugin is listed in `../sites.json`.
Layout follows yt-dlp's plugin package format: `yt_dlp_plugins/extractor/<name>.py`.
