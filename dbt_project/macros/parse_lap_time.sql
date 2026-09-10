{#
    Convert an Ergast/Jolpica time string to seconds.

    The source uses two formats and gives no indication which to expect:
      "1:29.179"     lap time            -> 89.179
      "1:31:44.742"  race duration       -> 5504.742
    and occasionally a bare number of seconds. Anything unrecognised, empty or
    null becomes null rather than zero -- a driver who set no time must not
    look like the fastest one.

    Character classes are used instead of backslash escapes because Databricks
    does not honour backslash escaping in string literals by default.
#}
{% macro parse_lap_time(column) %}
case
    when {{ column }} is null or trim({{ column }}) = '' then null
    when {{ column }} rlike '^[0-9]+:[0-9]{2}:[0-9]{2}([.][0-9]+)?$' then
          cast(split_part({{ column }}, ':', 1) as double) * 3600
        + cast(split_part({{ column }}, ':', 2) as double) * 60
        + cast(split_part({{ column }}, ':', 3) as double)
    when {{ column }} rlike '^[0-9]+:[0-9]{2}([.][0-9]+)?$' then
          cast(split_part({{ column }}, ':', 1) as double) * 60
        + cast(split_part({{ column }}, ':', 2) as double)
    when {{ column }} rlike '^[0-9]+([.][0-9]+)?$' then cast({{ column }} as double)
    else null
end
{% endmacro %}


{#
    Combine the source's separate date and time fields into one UTC timestamp.

    A missing time yields null, not midnight. Early races carry a date but no
    time, and defaulting those to 00:00 would state a start time the source
    never gave -- indistinguishable from a race that genuinely started at
    midnight. The date is not lost: it is kept separately as race_date.
#}
{% macro jolpica_session_start(date_column, time_column) %}
case
    when {{ date_column }} is null then null
    when {{ time_column }} is null or trim({{ time_column }}) = '' then null
    else to_timestamp(concat({{ date_column }}, 'T', {{ time_column }}))
end
{% endmacro %}
