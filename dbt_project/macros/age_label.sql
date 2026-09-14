{#
    A driver's age on a date as "18y 228d", the way F1 age records are quoted.

    Whole years come from months_between rather than days / 365.25, so a driver
    is a year older exactly on their birthday, not somewhere near it. Null when
    either date is missing.
#}
{% macro age_label(event_date, date_of_birth) %}
case
    when {{ event_date }} is null or {{ date_of_birth }} is null then null
    else concat(
        cast(floor(months_between({{ event_date }}, {{ date_of_birth }}) / 12) as int),
        'y ',
        datediff(
            {{ event_date }},
            add_months(
                {{ date_of_birth }},
                cast(floor(months_between({{ event_date }}, {{ date_of_birth }}) / 12) as int) * 12
            )
        ),
        'd'
    )
end
{% endmacro %}
