import re

from yt_dlp.extractor.common import InfoExtractor
from yt_dlp.utils import int_or_none, unescapeHTML, urljoin


class MyDaddyIE(InfoExtractor):
    """mydaddy.cc embeds write their <video> from a JavaScript string, so every quote is
    escaped and yt-dlp's generic HTML5 parser reads each quality as a separate, misnamed
    video. The page refuses to render without a referer from the embedding site."""

    IE_NAME = 'mydaddy.cc'
    _VALID_URL = r'https?://(?:www\.)?mydaddy\.cc/video/(?P<id>[0-9a-f]+)'

    def _real_extract(self, url):
        video_id = self._match_id(url)
        referer = self._configuration_arg('referer', ['https://hqporner.com/'], casesense=True)[0]
        webpage = self._download_webpage(url, video_id, headers={'Referer': referer})
        html = webpage.replace('\\"', '"').replace("\\/", '/')

        formats, seen = [], set()
        # The page carries two copies of the player markup, so sources repeat
        for source in re.finditer(r'<source\b[^>]*>', html):
            tag = source.group(0)
            src = self._search_regex(r'\bsrc="([^"]+)"', tag, 'source', default=None)
            if not src or src in seen:
                continue
            seen.add(src)
            label = self._search_regex(r'\btitle="([^"]+)"', tag, 'label', default='')
            quality = re.match(r'(\d+)p(\d+)?', label)
            formats.append({
                'url': urljoin('https:', unescapeHTML(src)),
                'format_id': label or None,
                'height': int_or_none(quality.group(1)) if quality else None,
                'fps': int_or_none(quality.group(2)) if quality and quality.group(2) else None,
                'ext': 'mp4',
            })
        if not formats:
            self.raise_no_formats('No video sources in the mydaddy.cc player', expected=True)

        poster = self._search_regex(r'\bposter="([^"]+)"', html, 'thumbnail', default=None)
        return {
            'id': video_id,
            'title': video_id,
            'formats': formats,
            'thumbnail': urljoin('https:', poster) if poster else None,
        }


class HQPornerIE(InfoExtractor):
    """hqporner.com pages iframe a mydaddy.cc player (see MyDaddyIE); the title comes from the page."""

    IE_NAME = 'hqporner.com'
    _VALID_URL = r'https?://(?:www\.)?hqporner\.com/hdporn/(?P<id>\d+)'

    def _real_extract(self, url):
        video_id = self._match_id(url)
        webpage = self._download_webpage(url, video_id)
        embed = self._search_regex(
            r'<iframe[^>]+src="((?:https?:)?//(?:www\.)?mydaddy\.cc/video/[0-9a-f]+/?)"',
            webpage, 'player URL')
        title = self._html_search_regex(
            r'<title>([^<]+?)\s*-\s*HQporner\.com', webpage, 'title', default=None)
        return self.url_result(
            urljoin('https:', embed), ie=MyDaddyIE.ie_key(), url_transparent=True,
            video_id=video_id, video_title=title)
