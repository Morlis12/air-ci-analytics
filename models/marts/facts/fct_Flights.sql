-- models/marts/facts/fct_flights.sql
with flights as (
    select * from {{ ref('stg_Flights') }}
),

routes as (
    select * from {{ ref('dim_routes') }}
),

dates as (
    select * from {{ ref('dim_date') }}
),

flight_costs as (
    select * from {{ ref('stg_Flight_costs') }}
),

weather as (
    select * from {{ ref('stg_Weather_impact') }}
),

cargo as (
    select
        flight_id,
        count(*)                            as nb_cargo_shipments,
        sum(weight_kg)                      as total_cargo_weight_kg,
        sum(cargo_revenue_usd)              as total_cargo_revenue_usd,
        round(avg(space_utilization_pct),2) as avg_cargo_utilization_pct,
        sum(case when is_sensitive_cargo
            then 1 else 0 end)              as nb_sensitive_shipments
    from {{ ref('stg_Cargo_operations') }}
    group by flight_id
),

-- revenus bookings agrégés par vol
booking_revenue as (
    select
        flight_id,
        count(*)                                as nb_bookings,
        count(distinct customer_id)             as nb_unique_passengers,
        sum(ticket_price_usd)                   as total_ticket_revenue_usd,
        sum(ancillary_revenue_usd)              as total_ancillary_revenue_usd,
        sum(total_revenue_usd)                  as total_revenue_usd,
        sum(bags_count)                         as total_bags,
        sum(case when is_cancelled
            then 1 else 0 end)                  as nb_cancelled_bookings,
        sum(case when is_flown
            then 1 else 0 end)                  as nb_flown_bookings,
        sum(case when has_seat_selection
            then 1 else 0 end)                  as nb_seat_selections
    from {{ ref('stg_Bookings') }}
    group by flight_id
),

final as (
    select
        -- =========================================
        -- CLÉS
        -- =========================================
        f.flight_id,
        f.route_id,
        f.flight_cost_key,
        cast(strftime(f.flight_date, '%Y%m%d') as integer)
                                                as date_id,
        f.flight_date,

        -- =========================================
        -- INFOS VOL
        -- =========================================
        f.flight_number,
        f.aircraft_type,
        f.seat_capacity,
        f.flight_status,
        f.delay_minutes,
        f.computed_departure_delay_min,
        f.computed_arrival_delay_min,
        f.is_delayed,
        f.is_cancelled,

        -- =========================================
        -- CONTEXTE MÉTÉO
        -- =========================================
        w.disruption_risk_level,
        w.disruption_risk_score,
        w.average_delay_caused_min          as weather_delay_min,
        w.is_disruptive_weather,
        w.season_type_normalized,

        -- part du délai expliquée par météo
        case
            when f.delay_minutes > 0
            and w.average_delay_caused_min > 0
            then round(
                w.average_delay_caused_min::double
                / nullif(f.delay_minutes::double, 0) * 100
            , 2)
            else 0
        end                                     as weather_delay_share_pct,

        -- flag délai opérationnel vs météo
        case
            when f.is_delayed = true
            and (
                w.average_delay_caused_min is null
                or w.average_delay_caused_min < f.delay_minutes * 0.5
            )
            then true else false
        end                                     as is_operational_delay,

        case
            when f.is_delayed = true
            and w.average_delay_caused_min >= f.delay_minutes * 0.5
            then true else false
        end                                     as is_weather_driven_delay,

        -- =========================================
        -- PASSAGERS & LOAD FACTOR
        -- =========================================
        coalesce(b.nb_bookings, 0)              as nb_bookings,
        coalesce(b.nb_unique_passengers, 0)     as nb_passengers,
        coalesce(b.nb_flown_bookings, 0)        as nb_flown_passengers,
        coalesce(b.nb_cancelled_bookings, 0)    as nb_cancelled_bookings,

        -- load factor = passagers / capacité
        case
            when f.seat_capacity > 0
            then round(
                coalesce(b.nb_bookings, 0)::double
                / f.seat_capacity * 100
            , 2)
            else null
        end                                     as load_factor_pct,

        -- flag vol sous-rempli (< 60%)
        case
            when (coalesce(b.nb_bookings, 0)::double
                / nullif(f.seat_capacity, 0)) < 0.60
            then true else false
        end                                     as is_underloaded,

        -- flag vol bien rempli (>= 85%)
        case
            when (coalesce(b.nb_bookings, 0)::double
                / nullif(f.seat_capacity, 0)) >= 0.85
            then true else false
        end                                     as is_high_load,

        -- =========================================
        -- REVENUS
        -- =========================================
        coalesce(b.total_ticket_revenue_usd, 0)    as total_ticket_revenue_usd,
        coalesce(b.total_ancillary_revenue_usd, 0) as total_ancillary_revenue_usd,
        coalesce(cg.total_cargo_revenue_usd, 0)    as total_cargo_revenue_usd,

        -- revenu total = ticket + ancillary + cargo
        round(
            coalesce(b.total_ticket_revenue_usd, 0)
            + coalesce(b.total_ancillary_revenue_usd, 0)
            + coalesce(cg.total_cargo_revenue_usd, 0)
        , 2)                                        as total_revenue_usd,

        -- yield = revenu ticket / km parcouru / passager
        case
            when r.distance_km > 0
            and coalesce(b.nb_flown_bookings, 0) > 0
            then round(
                coalesce(b.total_ticket_revenue_usd, 0)
                / r.distance_km
                / b.nb_flown_bookings
            , 4)
            else null
        end                                         as yield_usd_per_km,

        -- revenu par siège disponible (RASK proxy)
        case
            when f.seat_capacity > 0
            and r.distance_km > 0
            then round(
                coalesce(b.total_ticket_revenue_usd, 0)
                / (f.seat_capacity * r.distance_km)
            , 6)
            else null
        end                                         as rask,

        -- =========================================
        -- COÛTS
        -- =========================================
        coalesce(fc.total_cost_usd, 0)          as total_cost_usd,
        coalesce(fc.fuel_cost_usd, 0)           as fuel_cost_usd,
        coalesce(fc.crew_cost_usd, 0)           as crew_cost_usd,
        coalesce(fc.airport_fees_usd, 0)        as airport_fees_usd,
        coalesce(fc.maintenance_cost_usd, 0)    as maintenance_cost_usd,
        coalesce(fc.catering_cost_usd, 0)       as catering_cost_usd,
        coalesce(fc.fuel_cost_pct, 0)           as fuel_cost_pct,

        -- coût par siège disponible (CASK proxy)
        case
            when f.seat_capacity > 0
            and r.distance_km > 0
            then round(
                coalesce(fc.total_cost_usd, 0)
                / (f.seat_capacity * r.distance_km)
            , 6)
            else null
        end                                     as cask,

        -- =========================================
        -- MARGE
        -- =========================================
        round(
            coalesce(b.total_ticket_revenue_usd, 0)
            + coalesce(b.total_ancillary_revenue_usd, 0)
            + coalesce(cg.total_cargo_revenue_usd, 0)
            - coalesce(fc.total_cost_usd, 0)
        , 2)                                    as flight_margin_usd,

        -- marge en %
        case
            when coalesce(fc.total_cost_usd, 0) > 0
            then round(
                (
                    coalesce(b.total_ticket_revenue_usd, 0)
                    + coalesce(b.total_ancillary_revenue_usd, 0)
                    + coalesce(cg.total_cargo_revenue_usd, 0)
                    - coalesce(fc.total_cost_usd, 0)
                )
                / fc.total_cost_usd * 100
            , 2)
            else null
        end                                     as flight_margin_pct,

        -- flag vol rentable
        case
            when (
                coalesce(b.total_ticket_revenue_usd, 0)
                + coalesce(b.total_ancillary_revenue_usd, 0)
                + coalesce(cg.total_cargo_revenue_usd, 0)
            ) > coalesce(fc.total_cost_usd, 0)
            then true else false
        end                                     as is_profitable,

        -- =========================================
        -- CARGO
        -- =========================================
        coalesce(cg.nb_cargo_shipments, 0)          as nb_cargo_shipments,
        coalesce(cg.total_cargo_weight_kg, 0)       as total_cargo_weight_kg,
        coalesce(cg.avg_cargo_utilization_pct, 0)   as avg_cargo_utilization_pct,

        -- =========================================
        -- ANCILLARY
        -- =========================================
        coalesce(b.nb_seat_selections, 0)           as nb_seat_selections,
        coalesce(b.total_bags, 0)                   as total_bags,

        -- taux d'achat ancillaire
        case
            when coalesce(b.nb_bookings, 0) > 0
            then round(
                coalesce(b.nb_seat_selections, 0)::double
                / b.nb_bookings * 100
            , 2)
            else 0
        end                                         as seat_selection_attach_rate_pct

    from flights f
    left join {{ ref('dim_routes') }} r
        on r.route_id = f.route_id
    left join {{ ref('dim_date') }} d
        on d.full_date = f.flight_date
    left join flight_costs fc
        on fc.flight_cost_key = f.flight_cost_key
    left join weather w
        on  w.airport_code = r.origin_airport_code
        and w.weather_date = f.flight_date
    left join booking_revenue b
        on b.flight_id = f.flight_id
    left join cargo cg
        on cg.flight_id = f.flight_id
)

select * from final