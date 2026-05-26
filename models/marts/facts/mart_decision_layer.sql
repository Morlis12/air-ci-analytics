-- models/marts/facts/mart_decision_layer.sql
with flights as (
    select * from {{ ref('fct_Flights') }}
),

bookings as (
    select * from {{ ref('fct_Bookings') }}
),

tickets as (
    select * from {{ ref('fct_tickets') }}
),

customers as (
    select * from {{ ref('dim_Customers') }}
),

routes as (
    select * from {{ ref('dim_routes') }}
),

-- =========================================
-- AGRÉGATION PAR ROUTE
-- =========================================
route_performance as (
    select
        f.route_id,

        -- volume
        count(*)                                        as nb_flights,
        sum(f.nb_passengers)                            as total_passengers,
        round(avg(f.load_factor_pct), 2)                as avg_load_factor_pct,

        -- revenus & coûts
        sum(f.total_revenue_usd)                        as total_revenue_usd,
        sum(f.total_cost_usd)                           as total_cost_usd,
        sum(f.flight_margin_usd)                        as total_margin_usd,
        round(avg(f.flight_margin_pct), 2)              as avg_margin_pct,

        -- yield & RASK
        round(avg(f.yield_usd_per_km), 4)               as avg_yield,
        round(avg(f.rask), 6)                           as avg_rask,
        round(avg(f.cask), 6)                           as avg_cask,

        -- ponctualité
        round(avg(f.delay_minutes), 1)                  as avg_delay_minutes,
        sum(case when f.is_delayed then 1 else 0 end)   as nb_delayed_flights,
        sum(case when f.is_cancelled then 1 else 0 end) as nb_cancelled_flights,
        round(
            sum(case when f.is_delayed then 1 else 0 end)::double
            / nullif(count(*), 0) * 100
        , 2)                                            as delay_rate_pct,
        round(
            sum(case when f.is_cancelled then 1 else 0 end)::double
            / nullif(count(*), 0) * 100
        , 2)                                            as cancellation_rate_pct,

        -- problèmes opérationnels vs météo
        sum(case when f.is_operational_delay
            then 1 else 0 end)                          as nb_operational_delays,
        sum(case when f.is_weather_driven_delay
            then 1 else 0 end)                          as nb_weather_delays,

        -- rentabilité
        sum(case when f.is_profitable
            then 1 else 0 end)                          as nb_profitable_flights,
        round(
            sum(case when f.is_profitable then 1 else 0 end)::double
            / nullif(count(*), 0) * 100
        , 2)                                            as profitable_flight_pct

    from flights f
    group by f.route_id
),

-- =========================================
-- AGRÉGATION SENTIMENT PAR ROUTE
-- =========================================
route_sentiment as (
    select
        t.route_id,
        count(*)                                        as nb_tickets,
        round(avg(t.sentiment_score), 3)                as avg_sentiment_score,
        sum(case when t.urgency_level = 'critical'
            then 1 else 0 end)                          as nb_critical_tickets,
        sum(case when t.has_delay_keyword
            then 1 else 0 end)                          as nb_delay_complaints,
        sum(case when t.has_baggage_keyword
            then 1 else 0 end)                          as nb_baggage_complaints,
        sum(case when t.has_refund_keyword
            then 1 else 0 end)                          as nb_refund_complaints,
        sum(case when t.is_operational_delay
            and t.has_delay_keyword
            then 1 else 0 end)                          as nb_operational_delay_complaints
    from tickets t
    where t.route_id is not null
    group by t.route_id
),

-- =========================================
-- AGRÉGATION PAR CLIENT
-- =========================================
customer_performance as (
    select
        b.customer_id,
        count(distinct b.booking_id)                    as total_bookings,
        sum(b.total_revenue_usd)                        as total_revenue_usd,
        round(avg(b.total_revenue_usd), 2)              as avg_revenue_per_booking,
        sum(b.ancillary_revenue_usd)                    as total_ancillary_usd,
        max(b.flight_date)                              as last_flight_date,
        datediff('day', max(b.flight_date), current_date)
                                                        as days_since_last_flight,
        sum(case when b.has_ancillary_purchase
            then 1 else 0 end)                          as nb_bookings_with_ancillary,
        round(
            sum(case when b.has_ancillary_purchase
                then 1 else 0 end)::double
            / nullif(count(*), 0) * 100
        , 2)                                            as ancillary_attach_rate_pct
    from bookings b
    group by b.customer_id
),

-- =========================================
-- COUCHE ONTOLOGIE ROUTES
-- =========================================
route_ontology as (
    select
        r.route_id,
        r.route_key,
        r.route_type,
        r.distance_category,
        r.nb_competitors,
        r.competitive_intensity,
        r.avg_competitor_fare_usd,
        r.is_strategic_route,
        r.origin_city,
        r.destination_city,

        -- métriques performance
        rp.nb_flights,
        rp.total_passengers,
        rp.avg_load_factor_pct,
        rp.total_revenue_usd,
        rp.total_cost_usd,
        rp.total_margin_usd,
        rp.avg_margin_pct,
        rp.avg_yield,
        rp.avg_rask,
        rp.avg_cask,
        rp.delay_rate_pct,
        rp.cancellation_rate_pct,
        rp.nb_operational_delays,
        rp.nb_weather_delays,
        rp.profitable_flight_pct,

        -- métriques sentiment
        rs.avg_sentiment_score,
        rs.nb_tickets,
        rs.nb_critical_tickets,
        rs.nb_delay_complaints,
        rs.nb_operational_delay_complaints,

        -- =========================================
        -- RÈGLES ONTOLOGIQUES ROUTES
        -- =========================================

        -- 🟢 ROUTE À DÉVELOPPER
        -- forte demande + bonne marge + peu de concurrence
        case
            when rp.avg_load_factor_pct >= 80
            and rp.avg_margin_pct >= 15
            and r.nb_competitors <= 1
            then true else false
        end                                             as is_route_to_grow,

        -- 🔴 ROUTE STRATÉGIQUE SOUS-PERFORMANTE
        -- route importante MAIS marge faible OU retards opérationnels élevés
        case
            when r.is_strategic_route = true
            and (
                rp.avg_margin_pct < 10
                or rp.delay_rate_pct > 30
                or rp.profitable_flight_pct < 60
            )
            then true else false
        end                                             as is_strategic_underperforming,

        -- 🟡 ROUTE NON RENTABLE PAR PROBLÈME OPÉRATIONNEL
        -- perte d'argent mais demande potentielle (load factor correct)
        case
            when rp.avg_margin_pct < 0
            and rp.avg_load_factor_pct >= 65
            and rp.nb_operational_delays > rp.nb_weather_delays
            then true else false
        end                                             as is_operationally_unprofitable,

        -- 🔵 ROUTE NON RENTABLE PAR FAIBLE DEMANDE
        -- perte d'argent ET load factor faible
        case
            when rp.avg_margin_pct < 0
            and rp.avg_load_factor_pct < 65
            then true else false
        end                                             as is_demand_unprofitable,

        -- 🛡️ ROUTE À DÉFENDRE
        -- bonne marge MAIS forte concurrence ET sentiment négatif
        case
            when rp.avg_margin_pct >= 10
            and r.nb_competitors >= 3
            and coalesce(rs.avg_sentiment_score, 0) < -0.3
            then true else false
        end                                             as is_route_to_defend,

        -- label ontologique final route
        case
            when rp.avg_load_factor_pct >= 80
            and rp.avg_margin_pct >= 15
            and r.nb_competitors <= 1
            then '🟢 GrowthOpportunity'
            when r.is_strategic_route = true
            and (rp.avg_margin_pct < 10 or rp.delay_rate_pct > 30)
            then '🔴 StrategicUnderperformer'
            when rp.avg_margin_pct < 0
            and rp.avg_load_factor_pct >= 65
            and rp.nb_operational_delays > rp.nb_weather_delays
            then '🟠 OperationallyUnprofitable'
            when rp.avg_margin_pct < 0
            and rp.avg_load_factor_pct < 65
            then '⚪ DemandUnprofitable'
            when rp.avg_margin_pct >= 10
            and r.nb_competitors >= 3
            then '🔵 RouteToDefend'
            else '🟡 StableRoute'
        end                                             as route_ontology_label

    from routes r
    left join route_performance rp on rp.route_id = r.route_id
    left join route_sentiment rs on rs.route_id = r.route_id
),

-- =========================================
-- COUCHE ONTOLOGIE CLIENTS
-- =========================================
customer_ontology as (
    select
        c.customer_id,
        c.first_name,
        c.last_name,
        c.customer_segment,
        c.loyalty_tier,
        c.is_loyalty_member,
        c.is_high_value,
        c.is_at_risk,
        c.is_upsell_candidate,
        c.age_years,
        c.generation,
        c.country,
        c.total_miles,
        c.avg_sentiment_score,
        c.customer_value_score,
        c.total_tickets,
        c.critical_tickets,

        -- métriques comportement
        cp.total_bookings,
        cp.total_revenue_usd,
        cp.avg_revenue_per_booking,
        cp.total_ancillary_usd,
        cp.last_flight_date,
        cp.days_since_last_flight,
        cp.ancillary_attach_rate_pct,

        -- =========================================
        -- RÈGLES ONTOLOGIQUES CLIENTS
        -- =========================================

        -- 🔴 CLIENT HAUTE VALEUR À RISQUE
        -- client premium MAIS insatisfait ou inactif
        case
            when c.is_high_value = true
            and (
                c.avg_sentiment_score < -0.3
                or c.critical_tickets >= 1
                or cp.days_since_last_flight > 90
            )
            then true else false
        end                                             as is_high_value_at_risk,

        -- 🟢 CLIENT À FIDÉLISER
        -- bon comportement d'achat MAIS pas encore loyalty member
        case
            when c.is_loyalty_member = false
            and cp.total_bookings >= 2
            and cp.total_revenue_usd >= 300
            then true else false
        end                                             as is_loyalty_conversion_target,

        -- 🔵 CLIENT CANDIDAT UPGRADE PREMIUM
        -- segment standard MAIS miles élevés + ancillary actif
        case
            when c.customer_segment = 'standard'
            and c.total_miles >= 5000
            and cp.ancillary_attach_rate_pct >= 50
            then true else false
        end                                             as is_premium_upgrade_candidate,

        -- 🟡 CLIENT CANDIDAT OFFRES ANCILLAIRES
        -- vol régulier MAIS faible taux ancillaire
        case
            when cp.total_bookings >= 2
            and cp.ancillary_attach_rate_pct < 30
            and c.avg_sentiment_score >= -0.2
            then true else false
        end                                             as is_ancillary_offer_target,

        -- ⚪ CLIENT INACTIF À RÉACTIVER
        -- n'a pas volé depuis longtemps
        case
            when cp.days_since_last_flight > 180
            and cp.total_bookings >= 1
            then true else false
        end                                             as is_reactivation_target,

        -- label ontologique final client
        case
            when c.is_high_value = true
            and (
                c.avg_sentiment_score < -0.3
                or c.critical_tickets >= 1
                or cp.days_since_last_flight > 90
            )
            then '🔴 HighValueAtRisk'
            when c.is_loyalty_member = false
            and cp.total_bookings >= 2
            and cp.total_revenue_usd >= 300
            then '🟢 LoyaltyConversionTarget'
            when c.customer_segment = 'standard'
            and c.total_miles >= 5000
            and cp.ancillary_attach_rate_pct >= 50
            then '🔵 PremiumUpgradeCandidate'
            when cp.total_bookings >= 2
            and cp.ancillary_attach_rate_pct < 30
            and c.avg_sentiment_score >= -0.2
            then '🟡 AncillaryOfferTarget'
            when cp.days_since_last_flight > 180
            then '⚪ ReactivationTarget'
            else '✅ StableCustomer'
        end                                             as customer_ontology_label

    from customers c
    left join customer_performance cp
        on cp.customer_id = c.customer_id
),

-- =========================================
-- TABLE FINALE DÉCISIONNELLE
-- =========================================
final as (

    -- BLOC 1 : décisions routes
    select
        'route'                                         as decision_entity_type,
        ro.route_id                                     as entity_id,
        ro.route_key                                    as entity_label,
        ro.route_ontology_label                         as ontology_label,

        -- flags décisionnels
        ro.is_route_to_grow                             as flag_1,
        ro.is_strategic_underperforming                 as flag_2,
        ro.is_operationally_unprofitable                as flag_3,
        ro.is_demand_unprofitable                       as flag_4,
        ro.is_route_to_defend                           as flag_5,

        -- métriques clés
        ro.avg_load_factor_pct                          as metric_1,
        ro.avg_margin_pct                               as metric_2,
        ro.delay_rate_pct                               as metric_3,
        ro.avg_sentiment_score                          as metric_4,
        ro.total_revenue_usd                            as metric_5,

        -- recommandation actionnable
        case
            when ro.is_route_to_grow
            then 'Augmenter fréquence et budget marketing sur cette route'
            when ro.is_strategic_underperforming
            then 'Audit opérationnel urgent — route stratégique en difficulté'
            when ro.is_operationally_unprofitable
            then 'Revoir les coûts opérationnels — la demande est présente'
            when ro.is_demand_unprofitable
            then 'Évaluer suspension ou restructuration tarifaire'
            when ro.is_route_to_defend
            then 'Améliorer satisfaction client pour contrer la concurrence'
            else 'Maintenir le cap — route stable'
        end                                             as recommendation

    from route_ontology ro

    union all

    -- BLOC 2 : décisions clients
    select
        'customer'                                      as decision_entity_type,
        co.customer_id                                  as entity_id,
        co.first_name || ' ' || co.last_name           as entity_label,
        co.customer_ontology_label                      as ontology_label,

        -- flags décisionnels
        co.is_high_value_at_risk                        as flag_1,
        co.is_loyalty_conversion_target                 as flag_2,
        co.is_premium_upgrade_candidate                 as flag_3,
        co.is_ancillary_offer_target                    as flag_4,
        co.is_reactivation_target                       as flag_5,

        -- métriques clés
        co.total_revenue_usd                            as metric_1,
        co.ancillary_attach_rate_pct                    as metric_2,
        co.days_since_last_flight::double               as metric_3,
        co.avg_sentiment_score                          as metric_4,
        co.total_miles::double                          as metric_5,

        -- recommandation actionnable
        case
            when co.is_high_value_at_risk
            then 'Contact prioritaire — offrir geste commercial immédiat'
            when co.is_loyalty_conversion_target
            then 'Proposer adhésion programme fidélité avec bonus miles'
            when co.is_premium_upgrade_candidate
            then 'Offrir upgrade Business Class sur prochain vol'
            when co.is_ancillary_offer_target
            then 'Campagne ciblée bagage + siège premium'
            when co.is_reactivation_target
            then 'Email réactivation avec offre promotionnelle'
            else 'Maintenir engagement — client stable'
        end                                             as recommendation

    from customer_ontology co
)

select * from final