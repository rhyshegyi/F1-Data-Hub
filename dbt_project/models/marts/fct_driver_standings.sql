-- Final drivers' championship standings, one row per driver per season, widened
-- with that season's race statistics.
--
-- Championship columns come from the published classification, not from
-- summing points scored. Those differ before 1991, when only a driver's best N
-- results counted: Prost outscored Senna 105 to 94 in 1988 and Hill outscored
-- Surtees 41 to 40 in 1964, yet Senna and Surtees are the champions. Both
-- numbers are exposed, with points_dropped between them, so the difference is
-- visible rather than hidden behind whichever one happened to be chosen.
--
-- No arrays: Power BI cannot import them. A driver's teams for the season are
-- a joined string instead.

with standings as (

    select * from {{ ref('stg_jolpica__driver_standings') }}

),

season_stats as (

    select
        season,
        driver_id,
        count(distinct round)                                        as races_entered,
        sum(points)                                                  as race_points_scored,
        sum(case when was_classified and finish_position = 1 then 1 else 0 end)
                                                                     as race_wins,
        sum(case when was_classified and finish_position <= 3 then 1 else 0 end)
                                                                     as podiums,
        sum(case when qualifying_position = 1 then 1 else 0 end)      as poles,
        sum(case when not was_classified then 1 else 0 end)           as did_not_finish,
        avg(case when was_classified then finish_position end)        as avg_finish_position,
        avg(grid_position)                                            as avg_grid_position,
        sum(positions_gained)                                         as net_positions_gained

    from {{ ref('int_results_joined_to_qualifying') }}
    group by season, driver_id

),

sprint_points as (

    -- Sprints award championship points from 2021, so they have to be counted
    -- or points_scored disagrees with the published standings from then on.
    select season, driver_id, sum(points) as sprint_points_scored
    from {{ ref('stg_jolpica__sprint_results') }}
    group by season, driver_id

)

select
    standings.season,
    standings.driver_id,

    array_join(standings.constructor_names, ', ') as constructor_names,

    -- As published.
    standings.championship_position,
    standings.championship_position_text,
    standings.championship_points,
    standings.wins                                as championship_wins,
    coalesce(standings.championship_position = 1, false) as is_champion,

    -- As scored, races and sprints combined. Equal to championship_points from
    -- 1991 onwards; lower before that, depending on how many results were
    -- dropped.
    coalesce(season_stats.race_points_scored, 0)
        + coalesce(sprint_points.sprint_points_scored, 0) as points_scored,
    coalesce(season_stats.race_points_scored, 0)          as race_points_scored,
    coalesce(sprint_points.sprint_points_scored, 0)       as sprint_points_scored,
    standings.championship_points
        - (coalesce(season_stats.race_points_scored, 0)
           + coalesce(sprint_points.sprint_points_scored, 0)) as points_dropped,

    season_stats.races_entered,
    season_stats.race_wins,
    season_stats.podiums,
    season_stats.poles,
    season_stats.did_not_finish,
    round(season_stats.avg_finish_position, 2)     as avg_finish_position,
    round(season_stats.avg_grid_position, 2)       as avg_grid_position,
    season_stats.net_positions_gained

from standings
left join season_stats
    on standings.season = season_stats.season
   and standings.driver_id = season_stats.driver_id
left join sprint_points
    on standings.season = sprint_points.season
   and standings.driver_id = sprint_points.driver_id
