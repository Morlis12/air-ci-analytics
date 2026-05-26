-- models/marts/facts/fct_tickets.sql
with tickets as (
    select * from {{ ref('stg_Customer_service_tickets') }}
),

flights as (
    select
        flight_id,
        route_id,
        flight_date,
        is_delayed,
        is_cancelled,
        delay_minutes,
        is_operational_delay,
        is_weather_driven_delay,
        load_factor_pct
    from {{ ref('fct_Flights') }}
),

customers as (
    select
        customer_id,
        customer_segment,
        loyalty_tier,
        is_high_value,
        is_at_risk,
        customer_value_score,
        avg_sentiment_score
    from {{ ref('dim_Customers') }}
),

final as (
    select
        -- =========================================
        -- CLÉS
        -- =========================================
        t.ticket_id,
        t.customer_id,
        t.flight_id,
        f.route_id,

        -- =========================================
        -- TICKET
        -- =========================================
        t.ticket_category,
        t.customer_comments,
        t.resolution_status,
        t.resolution_time_days,
        t.is_resolved,
        t.is_open,
        t.is_in_progress,
        t.is_sla_breached,

        -- =========================================
        -- SENTIMENT & URGENCE
        -- =========================================
        t.sentiment_score,
        t.sentiment_label,
        t.urgency_level,

        -- =========================================
        -- CATÉGORIES PLAINTES
        -- recalculées ici depuis customer_comments
        -- car colonnes absentes du staging simplifié
        -- =========================================
        case
            when lower(t.customer_comments) like '%remboursement%'
            or lower(t.customer_comments) like '%débité%'
            then true else false
        end                                             as has_refund_keyword,

        case
            when lower(t.customer_comments) like '%bagage%'
            or lower(t.customer_comments) like '%valise%'
            or lower(t.customer_comments) like '%sac de voyage%'
            then true else false
        end                                             as has_baggage_keyword,

        case
            when lower(t.customer_comments) like '%retard%'
            or lower(t.customer_comments) like '%retardé%'
            or lower(t.customer_comments) like '%correspondance%'
            then true else false
        end                                             as has_delay_keyword,

        case
            when lower(t.customer_comments) like '%annulé%'
            or lower(t.customer_comments) like '%annulation%'
            or lower(t.customer_comments) like '%sans préavis%'
            then true else false
        end                                             as has_cancellation_keyword,

        case
            when lower(t.customer_comments) like '%surréservation%'
            or lower(t.customer_comments) like '%refusé l''embarquement%'
            or lower(t.customer_comments) like '%avion était plein%'
            then true else false
        end                                             as has_overbooking_keyword,

        case
            when lower(t.customer_comments) like '%repas%'
            or lower(t.customer_comments) like '%immangeable%'
            or lower(t.customer_comments) like '%végétarien%'
            then true else false
        end                                             as has_meal_keyword,

        case
            when lower(t.customer_comments) like '%siège%'
            or lower(t.customer_comments) like '%hublot%'
            or lower(t.customer_comments) like '%sièges sales%'
            then true else false
        end                                             as has_seat_keyword,

        case
            when lower(t.customer_comments) like '%climatisation%'
            or lower(t.customer_comments) like '%insupportable%'
            then true else false
        end                                             as has_comfort_keyword,

        case
            when lower(t.customer_comments) like '%application%'
            or lower(t.customer_comments) like '%site web%'
            or lower(t.customer_comments) like '%débité deux fois%'
            then true else false
        end                                             as has_digital_keyword,

        case
            when lower(t.customer_comments) like '%personnel%'
            or lower(t.customer_comments) like '%désagréable%'
            or lower(t.customer_comments) like '%peu professionnel%'
            then true else false
        end                                             as has_staff_keyword,

        case
            when lower(t.customer_comments) like '%très bon%'
            or lower(t.customer_comments) like '%attentionnée%'
            or lower(t.customer_comments) like '%service correct%'
            then true else false
        end                                             as has_positive_keyword,

        -- catégorie principale du ticket
        case
            when lower(t.customer_comments) like '%remboursement%'
            then 'refund'
            when lower(t.customer_comments) like '%bagage%'
            or lower(t.customer_comments) like '%valise%'
            then 'baggage'
            when lower(t.customer_comments) like '%retard%'
            then 'delay'
            when lower(t.customer_comments) like '%annulé%'
            then 'cancellation'
            when lower(t.customer_comments) like '%surréservation%'
            then 'overbooking'
            when lower(t.customer_comments) like '%siège%'
            then 'seat'
            when lower(t.customer_comments) like '%climatisation%'
            then 'comfort'
            when lower(t.customer_comments) like '%application%'
            or lower(t.customer_comments) like '%site web%'
            then 'digital'
            when lower(t.customer_comments) like '%personnel%'
            then 'staff'
            when lower(t.customer_comments) like '%très bon%'
            then 'positive'
            else 'other'
        end                                             as primary_complaint_category,

        -- =========================================
        -- CONTEXTE VOL
        -- =========================================
        f.flight_date,
        f.is_delayed                                    as flight_was_delayed,
        f.delay_minutes                                 as flight_delay_minutes,
        f.is_cancelled                                  as flight_was_cancelled,
        f.is_operational_delay,
        f.is_weather_driven_delay,
        f.load_factor_pct,

        -- cohérence ticket/vol
        case
            when lower(t.customer_comments) like '%retard%'
            and f.is_delayed = true
            then true else false
        end                                             as is_delay_complaint_confirmed,

        case
            when lower(t.customer_comments) like '%annulé%'
            and f.is_cancelled = true
            then true else false
        end                                             as is_cancellation_complaint_confirmed,

        -- =========================================
        -- PROFIL CLIENT
        -- =========================================
        c.customer_segment,
        c.loyalty_tier,
        c.is_high_value,
        c.is_at_risk,
        c.customer_value_score,

        -- =========================================
        -- FLAGS DÉCISIONNELS
        -- =========================================
        case
            when c.is_high_value = true
            and t.urgency_level in ('critical', 'high')
            then true else false
        end                                             as is_high_value_critical_ticket,

        case
            when t.is_resolved = false
            and t.resolution_time_days > 7
            then true else false
        end                                             as is_overdue_ticket

    from tickets t
    left join flights f
        on f.flight_id = t.flight_id
    left join customers c
        on c.customer_id = t.customer_id
)

select * from final