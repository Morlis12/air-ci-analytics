# test_mcp.py
import duckdb
import json

DB_PATH = "air_ci.db"

def get_db():
    con = duckdb.connect(DB_PATH)
    con.execute("LOAD spatial")
    return con

def test_all_tools():
    con = get_db()
    
    print("\n=== TEST 1 : KPIs Globaux ===")
    result = con.execute("""
        SELECT 
            ROUND(SUM(total_revenue_usd), 2)    as total_revenue,
            ROUND(AVG(load_factor_pct), 2)      as avg_load_factor,
            ROUND(AVG(flight_margin_pct), 2)    as avg_margin,
            COUNT(flight_id)                    as nb_flights
        FROM main_marts.fct_Flights
    """).fetchall()
    print(f"Revenue: {result[0][0]} USD")
    print(f"Load Factor: {result[0][1]}%")
    print(f"Marge moyenne: {result[0][2]}%")
    print(f"Nb vols: {result[0][3]}")

    print("\n=== TEST 2 : Routes Budget Q4 ===")
    result = con.execute("""
        SELECT entity_label, ontology_label, recommendation
        FROM main_marts.mart_decision_layer
        WHERE decision_entity_type = 'route'
        ORDER BY metric_2 DESC
        LIMIT 5
    """).fetchall()
    for row in result:
        print(f"{row[0]} → {row[1]}")
        print(f"   Recommandation : {row[2]}")

    print("\n=== TEST 3 : Clients High Value At Risk ===")
    result = con.execute("""
        SELECT entity_label, ontology_label, 
               metric_4 as sentiment, recommendation
        FROM main_marts.mart_decision_layer
        WHERE decision_entity_type = 'customer'
        AND ontology_label = '🔴 HighValueAtRisk'
        LIMIT 5
    """).fetchall()
    if result:
        for row in result:
            print(f"{row[0]} → Sentiment: {row[2]}")
            print(f"   Action: {row[3]}")
    else:
        print("Aucun client HighValueAtRisk trouvé")

    print("\n=== TEST 4 : Top Plaintes ===")
    result = con.execute("""
        SELECT primary_complaint_category,
               COUNT(*) as nb,
               ROUND(AVG(sentiment_score), 3) as sentiment
        FROM main_marts.fct_tickets
        GROUP BY primary_complaint_category
        ORDER BY nb DESC
        LIMIT 5
    """).fetchall()
    for row in result:
        print(f"{row[0]} : {row[1]} tickets, sentiment: {row[2]}")

    print("\n=== TEST 5 : Comparaison R001 vs R009 ===")
    result = con.execute("""
        SELECT 
            f.route_id,
            r.route_key,
            ROUND(AVG(f.load_factor_pct), 2)    as load_factor,
            ROUND(AVG(f.flight_margin_pct), 2)  as margin_pct,
            ROUND(AVG(f.delay_minutes), 1)      as avg_delay
        FROM main_marts.fct_Flights f
        LEFT JOIN main_marts.dim_routes r ON r.route_id = f.route_id
        WHERE f.route_id IN ('R001', 'R009')
        GROUP BY f.route_id, r.route_key
    """).fetchall()
    for row in result:
        print(f"{row[1]} → LF: {row[2]}%, Marge: {row[3]}%, Délai: {row[4]}min")

    con.close()
    print("\n✅ Tous les tests passent !")

if __name__ == "__main__":
    test_all_tools()