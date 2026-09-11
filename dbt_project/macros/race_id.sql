{#
    Single-column surrogate key for a race: 2024 round 21 becomes 202421.

    Power BI relationships cannot join on two columns, so (season, round) has
    to become one. An integer rather than a string because it sorts in race
    order on its own and relates faster. Rounds never exceed 99, so the
    encoding cannot collide.

    Defined once here so every mart derives it identically -- a key computed
    two different ways is two different keys.
#}
{% macro race_id(season_column, round_column) -%}
    cast({{ season_column }} * 100 + {{ round_column }} as int)
{%- endmacro %}
