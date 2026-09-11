"""Guard the dbt descriptions that end up inside Databricks.

`persist_docs` is on for every model, so each model and column description is
written into Databricks as a table or column comment -- and Power BI's
Databricks connector reads those comments.

A single column description containing double quotes and a middle dot broke
Power BI's refresh of that table with "A cyclic reference was encountered during
evaluation". Rewriting the description in plain ASCII, with nothing else
changed, fixed it. This test keeps every persisted description inside that
safe subset, so the next quote mark fails here rather than in the report.
"""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

MODELS_DIR = Path(__file__).resolve().parent.parent / "dbt_project" / "models"


def persisted_descriptions():
    """Every (location, text) pair dbt will write into Databricks as a comment."""
    for yml in sorted(MODELS_DIR.rglob("*.yml")):
        doc = yaml.safe_load(yml.read_text(encoding="utf-8")) or {}
        # Sources are not models, so persist_docs never writes them anywhere.
        for model in doc.get("models", []):
            name = model["name"]
            if model.get("description"):
                yield f"{yml.name}: {name}", model["description"]
            for column in model.get("columns", []):
                if column.get("description"):
                    yield f"{yml.name}: {name}.{column['name']}", column["description"]


DESCRIPTIONS = list(persisted_descriptions())


def test_descriptions_are_found():
    """If the walk finds nothing, every other test here passes vacuously."""
    assert len(DESCRIPTIONS) > 20


@pytest.mark.parametrize("where, text", DESCRIPTIONS, ids=[w for w, _ in DESCRIPTIONS])
def test_persisted_description_contains_no_double_quotes(where, text):
    assert '"' not in text, f"{where} -- use single quotes, or rephrase"


@pytest.mark.parametrize("where, text", DESCRIPTIONS, ids=[w for w, _ in DESCRIPTIONS])
def test_persisted_description_is_plain_ascii(where, text):
    offenders = sorted({ch for ch in text if ord(ch) > 127})
    assert not offenders, f"{where} contains {offenders} -- use plain ASCII"
