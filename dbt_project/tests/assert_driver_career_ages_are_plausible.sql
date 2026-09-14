-- Age records are only as good as the dates behind them. A driver younger than
-- 16 or older than 60 at a win, podium or title means a wrong date of birth or
-- a wrong join, not a record. Luigi Fagioli, 53 at his shared 1951 win, is the
-- oldest genuine case.

with ages as (

    select driver_id, 'first_win' as record, age_first_win_days as age_days from {{ ref('fct_driver_careers') }}
    union all
    select driver_id, 'last_win', age_last_win_days from {{ ref('fct_driver_careers') }}
    union all
    select driver_id, 'first_podium', age_first_podium_days from {{ ref('fct_driver_careers') }}
    union all
    select driver_id, 'last_podium', age_last_podium_days from {{ ref('fct_driver_careers') }}
    union all
    select driver_id, 'first_title', age_first_title_days from {{ ref('fct_driver_careers') }}
    union all
    select driver_id, 'last_title', age_last_title_days from {{ ref('fct_driver_careers') }}

)

select *
from ages
where age_days < 16 * 365
   or age_days > 60 * 366
