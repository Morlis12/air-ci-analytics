-- models/marts/dimensions/dim_Customers.sql
with customers as (
    select * from {{ ref('stg_Customers') }}
),

-- agrégation loyalty par customer
loyalty_agg as (
    select
        customer_id,
        sum(miles_amount)                           as total_miles,
        sum(estimated_value_usd)                    as total_loyalty_value_usd,
        count(*)                                    as total_loyalty_transactions,
        sum(case when is_flight_earn then miles_amount else 0 end)
                                                    as flight_miles_earned,
        sum(case when is_purchased_miles then miles_amount else 0 end)
                                                    as purchased_miles,
        sum(case when is_bonus_miles then miles_amount else 0 end)
                                                    as bonus_miles
    from {{ ref('stg_Loyalty_activity') }}
    group by customer_id
),

-- agrégation tickets par customer
ticket_agg as (
    select
        customer_id,
        count(*)                                    as total_tickets,
        round(avg(sentiment_score), 3)              as avg_sentiment_score,
        sum(case when is_resolved then 1 else 0 end)
                                                    as resolved_tickets,
        sum(case when urgency_level = 'critical' then 1 else 0 end)
                                                    as critical_tickets,
        sum(case when is_sla_breached then 1 else 0 end)
                                                    as sla_breached_tickets
    from {{ ref('stg_Customer_service_tickets') }}
    group by customer_id
),

final as (
    select
        -- =========================================
        -- CLÉ
        -- =========================================
        c.customer_id,

        -- =========================================
        -- PROFIL
        -- =========================================
        c.first_name,
        c.last_name,
        c.gender,
        c.birth_date,
        c.age_years,
        c.generation,
        c.country,
        c.city,
        c.is_domestic_customer,

        -- =========================================
        -- SEGMENTATION
        -- =========================================
        c.customer_segment,
        c.loyalty_tier,
        c.preferred_channel,
        c.signup_date,
        c.customer_tenure_days,
        c.is_loyalty_member,

        -- =========================================
        -- LOYALTY
        -- =========================================
        coalesce(l.total_miles, 0)                  as total_miles,
        coalesce(l.total_loyalty_value_usd, 0)      as total_loyalty_value_usd,
        coalesce(l.total_loyalty_transactions, 0)   as total_loyalty_transactions,
        coalesce(l.flight_miles_earned, 0)          as flight_miles_earned,
        coalesce(l.purchased_miles, 0)              as purchased_miles,
        coalesce(l.bonus_miles, 0)                  as bonus_miles,

        -- engagement loyalty
        case
            when coalesce(l.total_miles, 0) >= 10000   then 'high'
            when coalesce(l.total_miles, 0) >= 3000    then 'medium'
            when coalesce(l.total_miles, 0) > 0        then 'low'
            else                                             'inactive'
        end                                             as loyalty_engagement_level,

        -- =========================================
        -- SATISFACTION
        -- =========================================
        coalesce(t.total_tickets, 0)                as total_tickets,
        coalesce(t.avg_sentiment_score, 0)          as avg_sentiment_score,
        coalesce(t.resolved_tickets, 0)             as resolved_tickets,
        coalesce(t.critical_tickets, 0)             as critical_tickets,
        coalesce(t.sla_breached_tickets, 0)         as sla_breached_tickets,

        -- label sentiment global client
        case
            when coalesce(t.avg_sentiment_score, 0) >=  0.5  then 'positive'
            when coalesce(t.avg_sentiment_score, 0) >=  0.0  then 'neutral'
            when coalesce(t.avg_sentiment_score, 0) >= -0.5  then 'negative'
            else                                                   'very_negative'
        end                                             as customer_sentiment_label,

        -- =========================================
        -- SCORE DE VALEUR CLIENT (CLV)
        -- =========================================
        round(
            coalesce(l.total_loyalty_value_usd, 0)
            + (coalesce(l.total_miles, 0) * 0.01)
        , 2)                                            as customer_value_score,

        -- =========================================
        -- FLAGS ONTOLOGIE (préparation mart_decision_layer)
        -- =========================================

        -- client haute valeur
        case
            when c.customer_segment in ('business', 'premium')
            or c.loyalty_tier in ('Gold', 'Platinum')
            or coalesce(l.total_miles, 0) >= 10000
            then true else false
        end                                             as is_high_value,

        -- client à risque de churn
        case
            when coalesce(t.avg_sentiment_score, 0) < -0.5
            or coalesce(t.critical_tickets, 0) >= 2
            or coalesce(t.sla_breached_tickets, 0) >= 1
            then true else false
        end                                             as is_at_risk,

        -- candidat upsell (loyalty actif + segment standard)
        case
            when c.customer_segment = 'standard'
            and c.is_loyalty_member = true
            and coalesce(l.total_miles, 0) >= 3000
            then true else false
        end                                             as is_upsell_candidate

    from customers c
    left join loyalty_agg l on l.customer_id = c.customer_id
    left join ticket_agg t on t.customer_id = c.customer_id
)

select * from final