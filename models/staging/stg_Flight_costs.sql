with source as (
    select * from {{ source('excel_source', 'Flight_costs') }}
),

prep as (
    select
        nullif(trim(flight_id::varchar), '')                as f_id,
        nullif(trim(route_id::varchar), '')                 as r_id,
        flight_date::date                                   as f_date,
        fuel_cost_usd::double                               as fuel,
        airport_fees_usd::double                            as fees,
        crew_cost_usd::double                               as crew,
        maintenance_cost_usd::double                        as maint,
        catering_cost_usd::double                           as cater
    from source
),

renamed as (
    select
        f_id as flight_id,
        r_id as route_id,
        f_date as flight_date,

        -- Combinaison propre sans aucun conflit de nom possible
        coalesce(f_id, '') || '|' || coalesce(r_id, '') || '|' || coalesce(f_date::varchar, '') as flight_cost_key,

        fuel as fuel_cost_usd,
        fees as airport_fees_usd,
        crew as crew_cost_usd,
        maint as maintenance_cost_usd,
        cater as catering_cost_usd,

        round(fuel + fees + crew + maint + cater, 2) as total_cost_usd,
        round(fuel / nullif(fuel + fees + crew + maint + cater, 0) * 100, 2) as fuel_cost_pct,
        round(crew / nullif(fuel + fees + crew + maint + cater, 0) * 100, 2) as crew_cost_pct,
        round(maint / nullif(fuel + fees + crew + maint + cater, 0) * 100, 2) as maintenance_cost_pct,
        round(cater / nullif(fuel + fees + crew + maint + cater, 0) * 100, 2) as catering_cost_pct,

        case when fuel < 0 or fuel > 15000 then true else false end as is_fuel_suspect,
        case when fees < 0 or fees > 5000 then true else false end as is_airport_fees_suspect,
        case when crew < 0 or crew > 5000 then true else false end as is_crew_suspect,
        case when maint < 0 or maint > 3000 then true else false end as is_maintenance_suspect,
        case when cater < 0 or cater > 500 then true else false end as is_catering_suspect,
        
        case 
            when fuel < 0 or fuel > 15000
                or fees < 0 or fees > 5000
                or crew < 0 or crew > 5000
                or maint < 0 or maint > 3000
                or cater < 0 or cater > 500
            then true else false 
        end as is_any_cost_suspect,

        case when f_id is null then true else false end as is_id_missing,
        case when r_id is null then true else false end as is_route_missing,
        case when f_date is null then true else false end as is_date_missing,
        case when f_id is null or r_id is null or f_date is null then true else false end as is_composite_key_incomplete
    from prep
),

final as (
    select * from renamed
    where is_composite_key_incomplete = false
)

select * from final
