import json
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

from .config import Error


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Unauthorized(Error):
    pass


def request(url, data=None, headers=None, method=None, limit=2 * 1024 * 1024, timeout=10, raw=False, control=False, form=False):
    headers = dict(headers or {})
    if data is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded" if form else "application/json"
    payload = (urlencode(data) if form else json.dumps(data, ensure_ascii=False)).encode() if data is not None else None
    try:
        with build_opener(ProxyHandler({}), NoRedirect()).open(Request(url, payload, headers, method=method), timeout=timeout) as response:
            body = response.read(limit + 1)
            if len(body) > limit:
                raise Error("Service response exceeds the configured limit")
            return body if raw else json.loads(body)
    except HTTPError as exc:
        if exc.code == 401:
            raise Unauthorized("Service authentication failed") from None
        if control:
            try:
                message = json.loads(exc.read(16384)).get("error")
                if isinstance(message, str) and len(message) <= 8192:
                    raise Error(message) from None
            except (ValueError, AttributeError):
                pass
        raise Error("Service request failed; check connection, credentials, and doctor") from None
    except (URLError, TimeoutError, OSError, ValueError):
        raise Error("Service request failed; check connection, credentials, and doctor") from None
