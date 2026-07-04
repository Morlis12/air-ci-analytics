"""
owl/02_export.py — VERSION COMPLÈTE CORRIGÉE
Exporte dim_routes ET dim_customers depuis air_ci.db
"""

import duckdb, os
from rdflib import Graph, Namespace, RDF, XSD, Literal

AIR = Namespace("http://airci.com/ontology#")

DB_PATH = r"C:\Users\Laptop Studio\Documents\Air Ci Project\air_ci.db"

con = duckdb.connect(DB_PATH)
con.execute("LOAD spatial")

g = Graph()
g.bind("air", AIR)

# ===========================================
# EXPORT DES ROUTES
# ===========================================
print("Export des routes...")

routes = con.execute("""
    SELECT
        r.route_id,
        r.route_key,
        r.origin_airport_code,
        r.destination_airport_code,
        COALESCE(r.is_strategic_route, false) AS is_strategic_route,
        COALESCE(r.nb_competitors, 0)          AS nb_competitors,
        COALESCE(ROUND(AVG(f.load_factor_pct), 2), 0)    AS avg_load_factor_pct,
        COALESCE(ROUND(AVG(f.flight_margin_pct), 2), 0)   AS avg_margin_pct,
        COALESCE(ROUND(
            100.0 * SUM(CASE WHEN f.is_delayed THEN 1 ELSE 0 END)
            / NULLIF(COUNT(f.flight_id), 0), 2), 0)       AS delay_rate_pct,
        COALESCE(ROUND(AVG(t.sentiment_score), 2), 0)     AS avg_sentiment_score
    FROM main_marts.dim_routes r
    LEFT JOIN main_marts.fct_Flights f ON f.route_id = r.route_id
    LEFT JOIN main_marts.fct_tickets t ON t.flight_id = f.flight_id
    GROUP BY
        r.route_id, r.route_key,
        r.origin_airport_code, r.destination_airport_code,
        r.is_strategic_route, r.nb_competitors
    ORDER BY r.route_id
""").fetchall()
rcols = [d[0] for d in con.description]

for row in routes:
    d = dict(zip(rcols, row))
    uri = AIR[d["route_id"]]
    g.add((uri, RDF.type, AIR.Route))
    g.add((uri, AIR.hasRouteKey,
           Literal(str(d["route_key"]), datatype=XSD.string)))
    g.add((uri, AIR.hasLoadFactorPct,
           Literal(float(d["avg_load_factor_pct"]), datatype=XSD.decimal)))
    g.add((uri, AIR.hasMarginPct,
           Literal(float(d["avg_margin_pct"]), datatype=XSD.decimal)))
    g.add((uri, AIR.hasDelayRatePct,
           Literal(float(d["delay_rate_pct"]), datatype=XSD.decimal)))
    g.add((uri, AIR.hasNbCompetitors,
           Literal(int(d["nb_competitors"]), datatype=XSD.integer)))
    g.add((uri, AIR.isStrategicRoute,
           Literal(bool(d["is_strategic_route"]), datatype=XSD.boolean)))
    g.add((uri, AIR.hasAvgSentimentScore,
           Literal(float(d["avg_sentiment_score"]), datatype=XSD.decimal)))

    # Aéroports comme individus liés
    origin = AIR[str(d["origin_airport_code"])]
    dest   = AIR[str(d["destination_airport_code"])]
    g.add((origin, RDF.type, AIR.Airport))
    g.add((dest,   RDF.type, AIR.Airport))
    g.add((uri, AIR.hasOrigin, origin))
    g.add((uri, AIR.hasDestination, dest))
    print(f"  Route {d['route_id']} ({d['route_key']}) exportée")

# ===========================================
# EXPORT DES CUSTOMERS
# ===========================================
print("\nExport des customers...")

customers = con.execute("""
    SELECT
        c.customer_id,
        c.is_high_value,
        c.is_at_risk,
        COALESCE(c.avg_sentiment_score, 0)       AS avg_sentiment_score,
        COALESCE(c.total_miles, 0)               AS total_miles,
        COALESCE(c.is_loyalty_member, false)     AS is_loyalty_member,
        COALESCE(c.customer_segment, 'standard') AS customer_segment,

        -- Métriques depuis fct_bookings
        COALESCE(COUNT(b.booking_id), 0)         AS total_bookings,
        COALESCE(SUM(b.total_revenue_usd), 0)    AS total_revenue,
        COALESCE(ROUND(
            100.0 * SUM(CASE WHEN b.has_ancillary_purchase
                         THEN 1 ELSE 0 END)
            / NULLIF(COUNT(b.booking_id), 0), 2), 0) AS ancillary_attach_rate,

        -- Jours depuis dernier vol
        COALESCE(MAX(b.days_since_last_booking), 999) AS days_since_last_flight,

        -- Tickets critiques
        COALESCE(SUM(CASE WHEN t.urgency_level = 'critical'
                     THEN 1 ELSE 0 END), 0)      AS critical_tickets

    FROM main_marts.dim_customers c
    LEFT JOIN main_marts.fct_Bookings b
        ON b.customer_id = c.customer_id
    LEFT JOIN main_marts.fct_tickets t
        ON t.customer_id = c.customer_id
    GROUP BY
        c.customer_id, c.is_high_value, c.is_at_risk,
        c.avg_sentiment_score, c.total_miles,
        c.is_loyalty_member, c.customer_segment
    ORDER BY c.customer_id
""").fetchall()
ccols = [d[0] for d in con.description]

for row in customers:
    d = dict(zip(ccols, row))
    uri = AIR[d["customer_id"]]
    g.add((uri, RDF.type, AIR.Customer))
    g.add((uri, AIR.hasCustomerKey,
           Literal(str(d["customer_id"]), datatype=XSD.string)))
    g.add((uri, AIR.isHighValue,
           Literal(bool(d["is_high_value"]), datatype=XSD.boolean)))
    g.add((uri, AIR.isAtRisk,
           Literal(bool(d["is_at_risk"]), datatype=XSD.boolean)))
    g.add((uri, AIR.hasSentimentScore,
           Literal(float(d["avg_sentiment_score"]), datatype=XSD.decimal)))
    g.add((uri, AIR.hasTotalMiles,
           Literal(int(d["total_miles"]), datatype=XSD.integer)))
    g.add((uri, AIR.isLoyaltyMember,
           Literal(bool(d["is_loyalty_member"]), datatype=XSD.boolean)))
    g.add((uri, AIR.hasCustomerSegment,
           Literal(str(d["customer_segment"]), datatype=XSD.string)))
    g.add((uri, AIR.hasTotalBookings,
           Literal(int(d["total_bookings"]), datatype=XSD.integer)))
    g.add((uri, AIR.hasTotalRevenue,
           Literal(float(d["total_revenue"]), datatype=XSD.decimal)))
    g.add((uri, AIR.hasAncillaryAttachRate,
           Literal(float(d["ancillary_attach_rate"]), datatype=XSD.decimal)))
    g.add((uri, AIR.hasDaysSinceLastFlight,
           Literal(int(d["days_since_last_flight"]), datatype=XSD.integer)))
    g.add((uri, AIR.hasCriticalTickets,
           Literal(int(d["critical_tickets"]), datatype=XSD.integer)))

con.close()
print(f"  {len(customers)} customers exportés")

os.makedirs("owl", exist_ok=True)
g.serialize(destination="owl/air_ci_data.ttl", format="turtle")
print(f"\nDonnées exportées : {len(g)} triplets total")