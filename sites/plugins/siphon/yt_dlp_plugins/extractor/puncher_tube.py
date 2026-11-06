from yt_dlp.extractor.common import InfoExtractor


class PuncherTubeIE(InfoExtractor):
    """puncher.tube pages embed the player from another host in an iframe that yt-dlp's
    generic extractor doesn't follow; the embed itself is a KVS player the generic
    extractor already handles."""

    IE_NAME = 'puncher.tube'
    _VALID_URL = r'https?://(?:www\.)?puncher\.tube/video/(?P<id>\d+)'

    def _real_extract(self, url):
        video_id = self._match_id(url)
        webpage = self._download_webpage(url, video_id)
        embed_url = self._search_regex(
            r'class="player-box"[^>]*>\s*<iframe[^>]+src="(?P<url>https?://[^"]+)"',
            webpage, 'embed URL', group='url')
        # The embed's own title is clean; the page's og:title carries site boilerplate
        return self.url_result(embed_url, ie='Generic', video_id=video_id)
