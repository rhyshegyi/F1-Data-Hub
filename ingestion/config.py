"""Project configuration, read from the same places dbt reads it.

`dbt_project.yml` is the single source of truth for source coverage, so the
ingestion scripts and the dbt models can never disagree about what the raw
layer is supposed to contain.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
DBT_PROJECT_FILE = REPO_ROOT / "dbt_project" / "dbt_project.yml"


@dataclass(frozen=True)
class DatabricksConfig:
    host: str
    http_path: str
    token: str
    catalog: str
    raw_schema: str

    def table(self, name: str) -> str:
        return f"{self.catalog}.{self.raw_schema}.{name}"


@lru_cache(maxsize=1)
def _dbt_vars() -> dict:
    with DBT_PROJECT_FILE.open(encoding="utf-8") as f:
        return yaml.safe_load(f)["vars"]


def first_season() -> int:
    """Earliest championship season Jolpica carries."""
    return int(_dbt_vars()["first_season"])


def base_url() -> str:
    return str(_dbt_vars()["jolpica_base_url"]).rstrip("/")


def page_limit() -> int:
    """Jolpica caps `limit` at this; asking for more silently returns this."""
    return int(_dbt_vars()["jolpica_page_limit"])


def databricks_config() -> DatabricksConfig:
    """Read connection settings from the environment.

    dbt auto-loads .env, but these scripts run outside dbt, so load it here
    too. Raises rather than silently connecting to the wrong place.
    """
    _load_dotenv()

    missing = [
        k
        for k in ("DATABRICKS_HOST", "DATABRICKS_HTTP_PATH", "DATABRICKS_TOKEN")
        if not os.environ.get(k)
    ]
    if missing:
        raise RuntimeError(
            f"Missing required environment variable(s): {', '.join(missing)}. "
            "Copy .env.example to .env and fill it in."
        )

    return DatabricksConfig(
        host=os.environ["DATABRICKS_HOST"],
        http_path=os.environ["DATABRICKS_HTTP_PATH"],
        token=os.environ["DATABRICKS_TOKEN"],
        catalog=os.environ.get("DATABRICKS_CATALOG", "workspace"),
        raw_schema=os.environ.get("DATABRICKS_RAW_SCHEMA", "f1_raw"),
    )


def _load_dotenv() -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(REPO_ROOT / ".env")
