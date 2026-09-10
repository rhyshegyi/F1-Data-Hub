{#
    from_json schemas for the raw Jolpica payloads.

    Declared explicitly rather than inferred so the contract between the raw
    layer and staging is visible, and so a change to the source shows up as a
    diff here rather than as silently-null columns downstream.

    Every field is typed as string: the API returns all scalars quoted, and
    casting is staging's job, done once at the point of selection.
#}

{% macro jolpica_circuit_schema() %}
Circuit:struct<circuitId:string,url:string,circuitName:string,
               Location:struct<lat:string,long:string,locality:string,country:string>>
{%- endmacro %}

{% macro jolpica_driver_schema() %}
Driver:struct<driverId:string,permanentNumber:string,code:string,url:string,
              givenName:string,familyName:string,dateOfBirth:string,nationality:string>
{%- endmacro %}

{% macro jolpica_constructor_schema() %}
Constructor:struct<constructorId:string,url:string,name:string,nationality:string>
{%- endmacro %}

{% macro jolpica_session_schema(name) %}
{{ name }}:struct<date:string,time:string>
{%- endmacro %}


{% macro jolpica_races_schema() -%}
array<struct<season:string,round:string,url:string,raceName:string,
  {{ jolpica_circuit_schema() }},
  date:string,time:string,
  {{ jolpica_session_schema('FirstPractice') }},
  {{ jolpica_session_schema('SecondPractice') }},
  {{ jolpica_session_schema('ThirdPractice') }},
  {{ jolpica_session_schema('Qualifying') }},
  {{ jolpica_session_schema('Sprint') }},
  {{ jolpica_session_schema('SprintQualifying') }}>>
{%- endmacro %}


{% macro jolpica_results_schema() -%}
array<struct<season:string,round:string,url:string,raceName:string,
  {{ jolpica_circuit_schema() }},
  date:string,time:string,
  Results:array<struct<number:string,position:string,positionText:string,points:string,
    {{ jolpica_driver_schema() }},
    {{ jolpica_constructor_schema() }},
    grid:string,laps:string,status:string,
    Time:struct<millis:string,time:string>,
    FastestLap:struct<rank:string,lap:string,
                      Time:struct<time:string>,
                      AverageSpeed:struct<units:string,speed:string>>>>>>
{%- endmacro %}


{% macro jolpica_qualifying_schema() -%}
array<struct<season:string,round:string,url:string,raceName:string,
  {{ jolpica_circuit_schema() }},
  date:string,time:string,
  QualifyingResults:array<struct<number:string,position:string,
    {{ jolpica_driver_schema() }},
    {{ jolpica_constructor_schema() }},
    Q1:string,Q2:string,Q3:string>>>>
{%- endmacro %}


{% macro jolpica_drivers_schema() -%}
array<struct<driverId:string,permanentNumber:string,code:string,url:string,
             givenName:string,familyName:string,dateOfBirth:string,nationality:string>>
{%- endmacro %}


{% macro jolpica_driver_standings_schema() -%}
array<struct<season:string,round:string,
  DriverStandings:array<struct<position:string,positionText:string,points:string,wins:string,
    {{ jolpica_driver_schema() }},
    Constructors:array<struct<constructorId:string,url:string,name:string,nationality:string>>>>>>
{%- endmacro %}


{% macro jolpica_constructor_standings_schema() -%}
array<struct<season:string,round:string,
  ConstructorStandings:array<struct<position:string,positionText:string,points:string,wins:string,
    {{ jolpica_constructor_schema() }}>>>>
{%- endmacro %}


{% macro jolpica_sprint_schema() -%}
array<struct<season:string,round:string,url:string,raceName:string,
  {{ jolpica_circuit_schema() }},
  date:string,time:string,
  SprintResults:array<struct<number:string,position:string,positionText:string,points:string,
    {{ jolpica_driver_schema() }},
    {{ jolpica_constructor_schema() }},
    grid:string,laps:string,status:string>>>>
{%- endmacro %}
