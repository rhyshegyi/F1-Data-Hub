"""Jolpica API client: pagination, throttling and backoff.

Jolpica is the actively maintained successor to Ergast, which shut down in
2024, and keeps Ergast's response shape: everything is wrapped in an `MRData`
envelope carrying `limit`, `offset` and `total`.

The one surprise worth internalising is that **pagination is over result rows,
not races**. `/2024/results/?limit=100` returns 100 result rows spanning six
races, so a page routinely straddles round boundaries. Nothing here tries to
split a page along race lines -- the page is the grain of the raw layer.

The transport is injected so every behaviour below is testable without a
network: it is any callable taking a URL and returning an object with
`status_code`, `text` and `headers`. `requests.get` satisfies that.
"""

from __future__ import annotations

import json
import logging
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass

from .config import base_url, page_limit

log = logging.getLogger(__name__)

# Documented anonymous budget is roughly 4 requests/second burst and 500/hour
# sustained. A full backfill is ~585 requests, so the hourly cap is the real
# constraint; pace below the burst limit and let backoff handle the rest.
THROTTLE_SECONDS = 0.34

MAX_ATTEMPTS = 5

# 5xx from the origin, plus Cloudflare's own edge errors (520-524), which
# Jolpica sits behind. A real backfill lost a season to an unretried 520.
RETRYABLE_STATUS = {429, 500, 502, 503, 504, 520, 521, 522, 523, 524}


class JolpicaError(RuntimeError):
    """A request could not be completed after retrying."""


@dataclass(frozen=True)
class Page:
    """One verbatim API response page, as it will be stored in the raw layer."""

    endpoint: str
    season: int
    offset: int
    limit: int
    total: int
    request_url: str
    payload: str

    @property
    def row_count(self) -> int:
        """Rows this page contributed.

        Derived from the envelope rather than by counting parsed records: the
        record shape differs per endpoint (RaceTable/Races, DriverTable/Drivers)
        and the raw layer has no business knowing about either.
        """
        return max(0, min(self.limit, self.total - self.offset))


def fetch_pages(
    endpoint: str,
    season: int,
    *,
    transport: Callable[[str], object],
    limit: int | None = None,
    sleep: Callable[[float], None] = time.sleep,
    url_base: str | None = None,
) -> Iterator[Page]:
    """Yield every page of `endpoint` for `season`, oldest offset first.

    A season the endpoint has no data for (qualifying before 1994) yields
    nothing at all. That is absence, not failure.
    """
    cap = page_limit()
    limit = cap if limit is None else min(limit, cap)
    url_base = (url_base or base_url()).rstrip("/")

    offset = 0
    total = None
    while total is None or offset < total:
        url = f"{url_base}/{season}/{endpoint}/?limit={limit}&offset={offset}"
        response = _get(url, transport=transport, sleep=sleep)

        envelope = json.loads(response.text)["MRData"]
        total = int(envelope["total"])
        if total == 0:
            return

        yield Page(
            endpoint=endpoint,
            season=season,
            offset=offset,
            limit=limit,
            total=total,
            request_url=url,
            payload=response.text,
        )

        offset += limit
        if offset < total:
            sleep(THROTTLE_SECONDS)


def max_round(payload: str) -> int | None:
    """Highest round number in a payload page, or None if it has no races.

    Used only to set the ingestion watermark. The drivers endpoint is
    season-scoped rather than round-scoped, hence the None.
    """
    races = json.loads(payload)["MRData"].get("RaceTable", {}).get("Races", [])
    rounds = [int(race["round"]) for race in races if "round" in race]
    return max(rounds) if rounds else None


def _get(url: str, *, transport, sleep):
    """Request `url`, retrying transient failures with exponential backoff."""
    for attempt in range(MAX_ATTEMPTS):
        response = transport(url)
        status = response.status_code

        if status == 200:
            return response

        if status not in RETRYABLE_STATUS:
            raise JolpicaError(f"{url} returned HTTP {status}")

        if attempt == MAX_ATTEMPTS - 1:
            break

        delay = _retry_delay(response, attempt)
        log.warning("HTTP %s from %s -- retrying in %ss", status, url, delay)
        sleep(delay)

    raise JolpicaError(
        f"{url} still returning HTTP {status} after {MAX_ATTEMPTS} attempts. "
        "The season is left unwatermarked; re-run to resume."
    )


def _retry_delay(response, attempt: int) -> float:
    """Honour Retry-After when the server sends it, back off otherwise."""
    header = getattr(response, "headers", {}).get("Retry-After")
    if header:
        try:
            return float(header)
        except ValueError:
            pass
    return float(2**attempt)
