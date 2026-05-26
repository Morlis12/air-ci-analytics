-- models/marts/dimensions/dim_date.sql
with date_spine as (
    -- génère toutes les dates de 2024-01-01 à 2025-12-31
    select
        range as date_day
    from range(
        date '2024-01-01',
        date '2025-12-31',
        interval '1 day'
    )
),

final as (
    select
        -- =========================================
        -- CLÉ
        -- =========================================
        cast(strftime(date_day, '%Y%m%d') as integer)   as date_id,
        date_day                                         as full_date,

        -- =========================================
        -- COMPOSANTES DATE
        -- =========================================
        year(date_day)                                   as year,
        quarter(date_day)                                as quarter,
        month(date_day)                                  as month,
        day(date_day)                                    as day_of_month,
        dayofweek(date_day)                              as day_of_week,
        dayname(date_day)                                as day_name,
        monthname(date_day)                              as month_name,
        weekofyear(date_day)                             as week_of_year,

        -- =========================================
        -- LABELS UTILES
        -- =========================================
        'Q' || quarter(date_day)
            || ' ' || year(date_day)                     as quarter_label,

        year(date_day) || '-'
            || lpad(month(date_day)::varchar, 2, '0')    as year_month,

        -- =========================================
        -- FLAGS
        -- =========================================
        case
            when dayofweek(date_day) in (1, 7)
            then true else false
        end                                              as is_weekend,

        case
            when month(date_day) in (12, 1, 2)
            then 'peak'
            when month(date_day) in (6, 7, 8)
            then 'high'
            else 'normal'
        end                                              as season_demand,

        -- trimestre fiscal (suppose année fiscale = année calendaire)
        case
            when month(date_day) between 1 and 3   then 'FY-Q1'
            when month(date_day) between 4 and 6   then 'FY-Q2'
            when month(date_day) between 7 and 9   then 'FY-Q3'
            else                                        'FY-Q4'
        end                                              as fiscal_quarter

    from date_spine
)

select * from final