# mcp_server.py
# MCP Server — Air CI Project
import sys
import duckdb
import json
from mcp.server.fastmcp import FastMCP

# Force UTF-8 encoding pour Windows
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

# =========================================
# INITIALISATION
# =========================================
mcp = FastMCP("Air CI Analytics")
DB_PATH = "C:\\Users\\Laptop Studio\\Documents\\Air Ci Project\\air_ci.db"

def get_db():
    """Connexion a la base DuckDB"""
    con = duckdb.connect(DB_PATH)
    con.execute("LOAD spatial")
    return con

# =========================================
# OUTIL 1 — PERFORMANCE DES ROUTES
# =========================================
@mcp.tool()
def get_route_performance(route_id: str = None) -> str:
    """
    Retourne la performance financiere et operationnelle des routes.
    Inclut : revenue, marge, load factor, taux de retard.
    Si route_id est fourni, retourne les details d une route specifique.
    """
    con = get_db()
    
    if route_id:
        query = f"""
            SELECT 
                f.route_id,
                r.route_key,
                r.route_type,
                r.distance_category,
                COUNT(f.flight_id)                  as nb_flights,
                ROUND(AVG(f.load_factor_pct), 2)    as avg_load_factor_pct,
                ROUND(SUM(f.total_revenue_usd), 2)  as total_revenue_usd,
                ROUND(SUM(f.total_cost_usd), 2)     as total_cost_usd,
                ROUND(SUM(f.flight_margin_usd), 2)  as total_margin_usd,
                ROUND(AVG(f.flight_margin_pct), 2)  as avg_margin_pct,
                ROUND(AVG(f.delay_minutes), 1)      as avg_delay_minutes,
                SUM(CASE WHEN f.is_delayed THEN 1 ELSE 0 END) as nb_delayed,
                SUM(CASE WHEN f.is_cancelled THEN 1 ELSE 0 END) as nb_cancelled,
                r.nb_competitors,
                r.competitive_intensity,
                r.avg_competitor_fare_usd
            FROM main_marts.fct_Flights f
            LEFT JOIN main_marts.dim_routes r ON r.route_id = f.route_id
            WHERE f.route_id = '{route_id}'
            GROUP BY f.route_id, r.route_key, r.route_type,
                     r.distance_category, r.nb_competitors,
                     r.competitive_intensity, r.avg_competitor_fare_usd
        """
    else:
        query = """
            SELECT 
                f.route_id,
                r.route_key,
                r.route_type,
                r.distance_category,
                COUNT(f.flight_id)                  as nb_flights,
                ROUND(AVG(f.load_factor_pct), 2)    as avg_load_factor_pct,
                ROUND(SUM(f.total_revenue_usd), 2)  as total_revenue_usd,
                ROUND(SUM(f.total_cost_usd), 2)     as total_cost_usd,
                ROUND(SUM(f.flight_margin_usd), 2)  as total_margin_usd,
                ROUND(AVG(f.flight_margin_pct), 2)  as avg_margin_pct,
                ROUND(AVG(f.delay_minutes), 1)      as avg_delay_minutes,
                r.nb_competitors,
                r.competitive_intensity
            FROM main_marts.fct_Flights f
            LEFT JOIN main_marts.dim_routes r ON r.route_id = f.route_id
            GROUP BY f.route_id, r.route_key, r.route_type,
                     r.distance_category, r.nb_competitors,
                     r.competitive_intensity
            ORDER BY total_margin_usd DESC
        """
    
    result = con.execute(query).fetchall()
    columns = [desc[0] for desc in con.execute(query).description]
    con.close()
    
    data = [dict(zip(columns, row)) for row in result]
    return json.dumps(data, indent=2, ensure_ascii=False)

# =========================================
# OUTIL 2 — CLIENTS A RISQUE
# =========================================
@mcp.tool()
def get_high_value_at_risk_customers(limit: int = 20) -> str:
    """
    Retourne les clients haute valeur a risque de churn.
    Criteres : segment premium OU loyalty Gold/Platinum
               ET sentiment negatif OU tickets critiques
               OU inactif depuis plus de 90 jours.
    """
    con = get_db()
    
    query = f"""
        SELECT
            d.entity_id                             as customer_id,
            d.entity_label                          as customer_name,
            d.ontology_label,
            d.recommendation,
            ROUND(d.metric_1, 2)                    as total_revenue_usd,
            ROUND(d.metric_2, 2)                    as ancillary_attach_rate,
            ROUND(d.metric_3, 0)                    as days_since_last_flight,
            ROUND(d.metric_4, 3)                    as sentiment_score,
            ROUND(d.metric_5, 0)                    as total_miles
        FROM main_marts.mart_decision_layer d
        WHERE d.decision_entity_type = 'customer'
        AND d.ontology_label = 'HighValueAtRisk'
        ORDER BY d.metric_1 DESC
        LIMIT {limit}
    """
    
    result = con.execute(query).fetchall()
    columns = [desc[0] for desc in con.execute(query).description]
    con.close()
    
    data = [dict(zip(columns, row)) for row in result]
    return json.dumps(data, indent=2, ensure_ascii=False)

# =========================================
# OUTIL 3 — ROUTES A DEVELOPPER
# =========================================
@mcp.tool()
def get_routes_budget_recommendation() -> str:
    """
    Retourne les recommandations budgetaires par route.
    Identifie : routes a developper, defendre, restructurer.
    Base sur la couche ontologique du mart_decision_layer.
    """
    con = get_db()
    
    query = """
        SELECT
            d.entity_id                             as route_id,
            d.entity_label                          as route_key,
            d.ontology_label,
            d.recommendation,
            ROUND(d.metric_1, 2)                    as avg_load_factor_pct,
            ROUND(d.metric_2, 2)                    as avg_margin_pct,
            ROUND(d.metric_3, 2)                    as delay_rate_pct,
            ROUND(d.metric_4, 3)                    as avg_sentiment_score,
            ROUND(d.metric_5, 2)                    as total_revenue_usd
        FROM main_marts.mart_decision_layer d
        WHERE d.decision_entity_type = 'route'
        ORDER BY d.metric_2 DESC
    """
    
    result = con.execute(query).fetchall()
    columns = [desc[0] for desc in con.execute(query).description]
    con.close()
    
    data = [dict(zip(columns, row)) for row in result]
    return json.dumps(data, indent=2, ensure_ascii=False)

# =========================================
# OUTIL 4 — PLAINTES PAR ROUTE
# =========================================
@mcp.tool()
def get_complaints_by_route(route_id: str = None) -> str:
    """
    Retourne l analyse des plaintes clients par route.
    Combine donnees structurees et non structurees (NLP).
    Si route_id fourni, detaille les plaintes de cette route.
    """
    con = get_db()
    
    if route_id:
        query = f"""
            SELECT
                t.route_id,
                t.primary_complaint_category,
                COUNT(*)                                as nb_tickets,
                ROUND(AVG(t.sentiment_score), 3)        as avg_sentiment,
                SUM(CASE WHEN t.urgency_level = 'critical'
                    THEN 1 ELSE 0 END)                  as nb_critical,
                SUM(CASE WHEN t.is_resolved = true
                    THEN 1 ELSE 0 END)                  as nb_resolved,
                SUM(CASE WHEN t.is_sla_breached = true
                    THEN 1 ELSE 0 END)                  as nb_sla_breached,
                SUM(CASE WHEN t.has_delay_keyword
                    THEN 1 ELSE 0 END)                  as nb_delay_complaints,
                SUM(CASE WHEN t.has_baggage_keyword
                    THEN 1 ELSE 0 END)                  as nb_baggage_complaints,
                SUM(CASE WHEN t.has_refund_keyword
                    THEN 1 ELSE 0 END)                  as nb_refund_complaints
            FROM main_marts.fct_tickets t
            WHERE t.route_id = '{route_id}'
            GROUP BY t.route_id, t.primary_complaint_category
            ORDER BY nb_tickets DESC
        """
    else:
        query = """
            SELECT
                t.route_id,
                COUNT(*)                                as nb_tickets,
                ROUND(AVG(t.sentiment_score), 3)        as avg_sentiment,
                SUM(CASE WHEN t.urgency_level = 'critical'
                    THEN 1 ELSE 0 END)                  as nb_critical,
                SUM(CASE WHEN t.has_delay_keyword
                    THEN 1 ELSE 0 END)                  as nb_delay_complaints,
                SUM(CASE WHEN t.has_baggage_keyword
                    THEN 1 ELSE 0 END)                  as nb_baggage_complaints,
                SUM(CASE WHEN t.has_refund_keyword
                    THEN 1 ELSE 0 END)                  as nb_refund_complaints
            FROM main_marts.fct_tickets t
            GROUP BY t.route_id
            ORDER BY avg_sentiment ASC
        """
    
    result = con.execute(query).fetchall()
    columns = [desc[0] for desc in con.execute(query).description]
    con.close()
    
    data = [dict(zip(columns, row)) for row in result]
    return json.dumps(data, indent=2, ensure_ascii=False)

# =========================================
# OUTIL 5 — COMPARAISON DEUX ROUTES
# =========================================
@mcp.tool()
def compare_routes(route_id_1: str, route_id_2: str) -> str:
    """
    Compare deux routes sur tous les signaux financiers et satisfaction.
    Exemple : compare_routes('R001', 'R009')
    """
    con = get_db()
    
    query = f"""
        SELECT
            f.route_id,
            r.route_key,
            r.route_type,
            r.distance_km,
            r.nb_competitors,
            r.avg_competitor_fare_usd,
            COUNT(f.flight_id)                      as nb_flights,
            ROUND(AVG(f.load_factor_pct), 2)        as avg_load_factor_pct,
            ROUND(SUM(f.total_revenue_usd), 2)      as total_revenue_usd,
            ROUND(AVG(f.flight_margin_pct), 2)      as avg_margin_pct,
            ROUND(AVG(f.yield_usd_per_km), 4)       as avg_yield,
            ROUND(AVG(f.delay_minutes), 1)          as avg_delay_minutes,
            SUM(CASE WHEN f.is_operational_delay
                THEN 1 ELSE 0 END)                  as nb_operational_delays,
            (SELECT ROUND(AVG(t.sentiment_score), 3)
             FROM main_marts.fct_tickets t
             WHERE t.route_id = f.route_id)         as avg_sentiment,
            (SELECT COUNT(*)
             FROM main_marts.fct_tickets t
             WHERE t.route_id = f.route_id)         as nb_complaints
        FROM main_marts.fct_Flights f
        LEFT JOIN main_marts.dim_routes r
            ON r.route_id = f.route_id
        WHERE f.route_id IN ('{route_id_1}', '{route_id_2}')
        GROUP BY f.route_id, r.route_key, r.route_type,
                 r.distance_km, r.nb_competitors,
                 r.avg_competitor_fare_usd
    """
    
    result = con.execute(query).fetchall()
    columns = [desc[0] for desc in con.execute(query).description]
    con.close()
    
    data = [dict(zip(columns, row)) for row in result]
    return json.dumps(data, indent=2, ensure_ascii=False)

# =========================================
# OUTIL 6 — SEGMENTS POUR OFFRES PREMIUM
# =========================================
@mcp.tool()
def get_upsell_segments() -> str:
    """
    Identifie les segments clients prioritaires pour
    les offres premium et ancillaires.
    Retourne : candidats upgrade, ancillary targets,
               loyalty conversion targets.
    """
    con = get_db()
    
    query = """
        SELECT
            d.ontology_label,
            COUNT(*)                                as nb_customers,
            ROUND(AVG(d.metric_1), 2)               as avg_revenue_usd,
            ROUND(AVG(d.metric_2), 2)               as avg_ancillary_rate,
            ROUND(AVG(d.metric_5), 0)               as avg_miles,
            d.recommendation
        FROM main_marts.mart_decision_layer d
        WHERE d.decision_entity_type = 'customer'
        AND d.ontology_label IN (
            'PremiumUpgradeCandidate',
            'AncillaryOfferTarget',
            'LoyaltyConversionTarget'
        )
        GROUP BY d.ontology_label, d.recommendation
        ORDER BY nb_customers DESC
    """
    
    result = con.execute(query).fetchall()
    columns = [desc[0] for desc in con.execute(query).description]
    con.close()
    
    data = [dict(zip(columns, row)) for row in result]
    return json.dumps(data, indent=2, ensure_ascii=False)

# =========================================
# OUTIL 7 — ANALYSE NON STRUCTUREE
# =========================================
@mcp.tool()
def get_unstructured_insights(category: str = None) -> str:
    """
    Analyse les donnees non structurees (commentaires clients).
    Retourne les themes dominants et exemples de commentaires.
    Categories : delay, baggage, refund, cancellation,
                 overbooking, meal, seat, comfort, digital, staff
    """
    con = get_db()
    
    if category:
        query = f"""
            SELECT
                t.route_id,
                t.primary_complaint_category,
                t.urgency_level,
                t.sentiment_score,
                t.sentiment_label,
                t.customer_comments,
                t.resolution_status,
                t.resolution_time_days,
                t.is_sla_breached,
                t.flight_was_delayed,
                t.flight_was_cancelled,
                t.is_high_value_critical_ticket,
                c.customer_segment,
                c.loyalty_tier
            FROM main_marts.fct_tickets t
            LEFT JOIN main_marts.dim_Customers c
                ON c.customer_id = t.customer_id
            WHERE t.primary_complaint_category = '{category}'
            ORDER BY t.sentiment_score ASC
            LIMIT 20
        """
    else:
        query = """
            SELECT
                primary_complaint_category,
                COUNT(*)                            as nb_tickets,
                ROUND(AVG(sentiment_score), 3)      as avg_sentiment,
                SUM(CASE WHEN urgency_level = 'critical'
                    THEN 1 ELSE 0 END)              as nb_critical,
                SUM(CASE WHEN is_sla_breached
                    THEN 1 ELSE 0 END)              as nb_sla_breached,
                SUM(CASE WHEN is_high_value_critical_ticket
                    THEN 1 ELSE 0 END)              as nb_hv_critical
            FROM main_marts.fct_tickets
            GROUP BY primary_complaint_category
            ORDER BY nb_tickets DESC
        """
    
    result = con.execute(query).fetchall()
    columns = [desc[0] for desc in con.execute(query).description]
    con.close()
    
    data = [dict(zip(columns, row)) for row in result]
    return json.dumps(data, indent=2, ensure_ascii=False)

# =========================================
# OUTIL 8 — KPIs GLOBAUX
# =========================================
@mcp.tool()
def get_global_kpis() -> str:
    """
    Retourne les KPIs globaux de la compagnie aerienne.
    Vue d ensemble : revenue, marge, load factor,
    satisfaction, fidelite, ancillaire.
    """
    con = get_db()
    
    flights_query = """
        SELECT
            ROUND(SUM(f.total_revenue_usd), 2)          as total_revenue_usd,
            ROUND(SUM(f.total_cost_usd), 2)             as total_cost_usd,
            ROUND(SUM(f.flight_margin_usd), 2)          as total_margin_usd,
            ROUND(AVG(f.flight_margin_pct), 2)          as avg_margin_pct,
            COUNT(f.flight_id)                          as nb_flights,
            ROUND(AVG(f.load_factor_pct), 2)            as avg_load_factor_pct,
            ROUND(AVG(f.delay_minutes), 1)              as avg_delay_minutes,
            SUM(CASE WHEN f.is_delayed
                THEN 1 ELSE 0 END)                      as nb_delayed_flights,
            SUM(CASE WHEN f.is_cancelled
                THEN 1 ELSE 0 END)                      as nb_cancelled_flights,
            ROUND(AVG(f.yield_usd_per_km), 4)           as avg_yield,
            ROUND(AVG(f.rask), 6)                       as avg_rask,
            ROUND(AVG(f.cask), 6)                       as avg_cask,
            ROUND(SUM(f.total_ancillary_revenue_usd), 2) as total_ancillary_usd,
            ROUND(SUM(f.total_cargo_revenue_usd), 2)    as total_cargo_usd
        FROM main_marts.fct_Flights f
    """
    
    customer_query = """
        SELECT
            COUNT(customer_id)                          as nb_customers,
            SUM(CASE WHEN is_high_value
                THEN 1 ELSE 0 END)                      as nb_high_value,
            SUM(CASE WHEN is_at_risk
                THEN 1 ELSE 0 END)                      as nb_at_risk,
            SUM(CASE WHEN is_loyalty_member
                THEN 1 ELSE 0 END)                      as nb_loyalty_members,
            ROUND(AVG(avg_sentiment_score), 3)          as avg_sentiment
        FROM main_marts.dim_Customers
    """
    
    flights_result = con.execute(flights_query).fetchall()
    flights_cols = [desc[0] for desc in con.execute(flights_query).description]
    
    customer_result = con.execute(customer_query).fetchall()
    customer_cols = [desc[0] for desc in con.execute(customer_query).description]
    con.close()
    
    result = {
        "financial_kpis": [dict(zip(flights_cols, row)) for row in flights_result],
        "customer_kpis": [dict(zip(customer_cols, row)) for row in customer_result]
    }
    
    return json.dumps(result, indent=2, ensure_ascii=False)

# =========================================
# LANCEMENT DU SERVEUR
# =========================================
if __name__ == "__main__":
    print("Air CI MCP Server demarre !", file=sys.stderr)
    print("Connecte a : air_ci.db", file=sys.stderr)
    print("8 outils disponibles", file=sys.stderr)
    mcp.run()