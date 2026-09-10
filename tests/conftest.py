"""Shared test helpers.

Fixtures under `fixtures/jolpica/` are real Jolpica responses recorded with
`limit=2` -- small enough to read, structurally identical to production pages.
"""

from __future__ import annotations

from pathlib import Path

import pytest

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "jolpica"


def fixture_text(name: str) -> str:
    return (FIXTURE_DIR / name).read_text(encoding="utf-8")


class FakeResponse:
    def __init__(self, text: str, status_code: int = 200, headers: dict | None = None):
        self.text = text
        self.status_code = status_code
        self.headers = headers or {}


class FakeTransport:
    """Records the URLs requested and replays canned responses.

    A list of responses is consumed in order; a single response is returned
    for every request.
    """

    def __init__(self, responses):
        self._responses = list(responses) if isinstance(responses, list) else None
        self._single = None if self._responses else responses
        self.urls: list[str] = []

    def __call__(self, url: str) -> FakeResponse:
        self.urls.append(url)
        if self._single is not None:
            return self._single
        if not self._responses:
            raise AssertionError(f"unexpected extra request: {url}")
        return self._responses.pop(0)


class RecordingSleep:
    """Stands in for time.sleep so backoff tests run instantly."""

    def __init__(self):
        self.delays: list[float] = []

    def __call__(self, seconds: float) -> None:
        self.delays.append(seconds)


class FakeCursor:
    """Records statements and bound parameters instead of talking to Databricks."""

    def __init__(self, rows=()):
        self.calls: list[tuple[str, list | None]] = []
        self._rows = list(rows)

    def execute(self, statement: str, parameters=None) -> None:
        self.calls.append((statement, parameters))

    def fetchall(self):
        return self._rows

    @property
    def statements(self) -> list[str]:
        return [s for s, _ in self.calls]


@pytest.fixture
def cursor() -> FakeCursor:
    return FakeCursor()
