-- models/marts/facts/fct_bookings.sql
with bookings as (
    select * from {{ ref('stg_Bookings') }}
),

flights as (
    select
        flight_id,
        route_id,
        flight_date,
        seat_capacity,
        is_delayed,
        is_cancelled,
        delay_minutes,
        load_factor_pct,
        total_cost_usd,
        is_profitable
    from {{ ref('fct_Flights') }}
),

customers as (
    select
        customer_id,
        customer_segment,
        loyalty_tier,
        is_loyalty_member,
        is_high_value,
        is_at_risk,
        is_upsell_candidate,
        age_years,
        generation,
        country,
        customer_value_score
    from {{ ref('dim_Customers') }}
),

-- agrégation ancillaire par booking
ancillary_agg as (
    select
        booking_id,
        count(*)                                        as nb_ancillary_items,
        sum(item_revenue_usd)                           as total_ancillary_detail_usd,
        sum(case when item_category_normalized = 'baggage'
            then item_revenue_usd else 0 end)           as baggage_revenue_usd,
        sum(case when item_category_normalized = 'seat'
            then item_revenue_usd else 0 end)           as seat_revenue_usd,
        sum(case when item_category_normalized = 'meal'
            then item_revenue_usd else 0 end)           as meal_revenue_usd,
        sum(case when is_premium_seat
            then 1 else 0 end)                          as nb_premium_seats,
        sum(case when is_digital_purchase
            then 1 else 0 end)                          as nb_digital_purchases
    from {{ ref('stg_Ancillary_details') }}
    group by booking_id
),

-- historique bookings par client (repeat booking)
customer_booking_history as (
    select
        customer_id,
        count(*)                                        as total_past_bookings,
        sum(total_revenue_usd)                          as total_past_revenue_usd,
        min(booking_date)                               as first_booking_date,
        max(booking_date)                               as last_booking_date
    from {{ ref('stg_Bookings') }}
    where booking_status != 'cancelled'
    group by customer_id
),

final as (
    select
        -- =========================================
        -- CLÉS
        -- =========================================
        b.booking_id,
        b.customer_id,
        b.flight_id,
        f.route_id,
        cast(strftime(b.booking_date, '%Y%m%d') as integer)
                                                        as date_id,
        b.booking_date,

        -- =========================================
        -- INFOS BOOKING
        -- =========================================
        b.booking_channel,
        b.fare_class,
        b.fare_family,
        b.booking_status,
        b.is_confirmed,
        b.is_flown,
        b.is_cancelled,
        b.bags_count,
        b.has_seat_selection,
        b.ticket_price_category,

        -- =========================================
        -- REVENUS
        -- =========================================
        b.ticket_price_usd,
        b.ancillary_revenue_usd,
        b.total_revenue_usd,
        b.ancillary_revenue_pct,

        -- détail ancillaire
        coalesce(a.nb_ancillary_items, 0)               as nb_ancillary_items,
        coalesce(a.baggage_revenue_usd, 0)              as baggage_revenue_usd,
        coalesce(a.seat_revenue_usd, 0)                 as seat_revenue_usd,
        coalesce(a.meal_revenue_usd, 0)                 as meal_revenue_usd,
        coalesce(a.nb_premium_seats, 0)                 as nb_premium_seats,
        coalesce(a.nb_digital_purchases, 0)             as nb_digital_purchases,

        -- flag achat ancillaire
        case
            when coalesce(a.nb_ancillary_items, 0) > 0
            then true else false
        end                                             as has_ancillary_purchase,

        -- ancillary attach rate (booléen par booking)
        case
            when coalesce(a.nb_ancillary_items, 0) >= 2
            then 'high'
            when coalesce(a.nb_ancillary_items, 0) = 1
            then 'low'
            else 'none'
        end                                             as ancillary_attach_level,

        -- =========================================
        -- CONTEXTE VOL
        -- =========================================
        f.flight_date,
        f.is_delayed                                    as flight_was_delayed,
        f.delay_minutes                                 as flight_delay_minutes,
        f.is_cancelled                                  as flight_was_cancelled,
        f.load_factor_pct,
        f.is_profitable                                 as flight_is_profitable,

        -- =========================================
        -- PROFIL CLIENT
        -- =========================================
        c.customer_segment,
        c.loyalty_tier,
        c.is_loyalty_member,
        c.is_high_value,
        c.is_at_risk,
        c.is_upsell_candidate,
        c.age_years,
        c.generation,
        c.country                                       as customer_country,
        c.customer_value_score,

        -- =========================================
        -- COMPORTEMENT REPEAT
        -- =========================================
        coalesce(h.total_past_bookings, 0)              as customer_total_bookings,
        coalesce(h.total_past_revenue_usd, 0)           as customer_total_revenue_usd,
        h.first_booking_date,
        h.last_booking_date,

        -- flag client repeat (plus d'un vol)
        case
            when coalesce(h.total_past_bookings, 0) > 1
            then true else false
        end                                             as is_repeat_customer,

        -- nombre de jours depuis dernier vol
        datediff('day', h.last_booking_date, current_date)
                                                        as days_since_last_booking,

        -- flag client inactif (> 180 jours)
        case
            when datediff('day', h.last_booking_date, current_date) > 180
            then true else false
        end                                             as is_inactive_customer

    from bookings b
    left join flights f
        on f.flight_id = b.flight_id
    left join {{ ref('dim_Customers') }} c        -- ✅ CORRIGÉ
        on c.customer_id = b.customer_id
    left join ancillary_agg a
        on a.booking_id = b.booking_id
    left join customer_booking_history h
        on h.customer_id = b.customer_id
)

select * from final