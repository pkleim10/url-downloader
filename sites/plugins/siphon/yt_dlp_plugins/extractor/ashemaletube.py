from yt_dlp.extractor.common import InfoExtractor
from yt_dlp.networking.exceptions import HTTPError
from yt_dlp.networking.impersonate import ImpersonateTarget
from yt_dlp.utils import ExtractorError, int_or_none, url_or_none


class AShemaleTubeIE(InfoExtractor):
    IE_NAME = 'ashemaletube'
    _VALID_URL = r'https?://(?:www\.)?ashemaletube\.com/videos/(?P<id>\d+)'

    def _real_extract(self, url):
        video_id = self._match_id(url)
        webpage = self._download_page(url, video_id)

        sources = self._search_json(r'\bsources\s*:', webpage, 'sources', video_id)
        formats = []
        if url_or_none(sources.get('hlsAuto')):
            formats.extend(self._extract_m3u8_formats(
                sources['hlsAuto'], video_id, 'mp4', m3u8_id='hls', fatal=False))
        for kind in ('mp4', 'hls'):
            for source in sources.get(kind) or []:
                src = url_or_none(source.get('src')) if isinstance(source, dict) else None
                if not src:
                    continue
                height = int_or_none(str(source.get('quality') or '').rstrip('p'))
                if kind == 'hls':
                    formats.extend(self._extract_m3u8_formats(
                        src, video_id, 'mp4', m3u8_id=f'hls-{height or "x"}', fatal=False))
                else:
                    formats.append({'url': src, 'format_id': f'mp4-{height or "x"}', 'height': height, 'ext': 'mp4'})

        title = (self._html_search_meta(['og:title', 'twitter:title'], webpage, default=None)
                 or self._html_search_regex(r'<title>([^<|]+?)\s*(?:\||</title>)', webpage, 'title'))
        return {
            'id': video_id,
            'title': title.strip(),
            'formats': formats,
            'thumbnail': self._html_search_meta(['og:image', 'twitter:image'], webpage, default=None),
            'description': self._html_search_meta('description', webpage, default=None),
            'duration': int_or_none(self._search_regex(r'\bvideoDuration\s*:\s*(\d+)', webpage, 'duration', default=None)),
            'age_limit': 18,
        }

    # The page sits behind a Cloudflare challenge that desktop Chrome fingerprints usually pass
    # and Safari's never do; a challenged request is retried as another Chrome version.
    _TARGETS = ('chrome-131:macos-14', 'chrome-136:macos-15', 'chrome-133:macos-15', 'chrome')

    def _download_page(self, url, video_id):
        for index, target in enumerate(self._TARGETS):
            last = index == len(self._TARGETS) - 1
            try:
                return self._download_webpage(
                    url, video_id, impersonate=ImpersonateTarget.from_str(target),
                    note='Downloading webpage' if index == 0 else f'Retrying webpage as {target}')
            except ExtractorError as error:
                if last or not isinstance(error.cause, HTTPError) or error.cause.status != 403:
                    raise
