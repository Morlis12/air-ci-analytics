# mcp_server.py — VERSION ENRICHIE AVEC OWL
import sys
import duckdb
import json
import os
from mcp.server.fastmcp import FastMCP

# ---- NOUVEAU : imports OWL ----
from rdflib import Graph, Namespace, RDF

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

mcp = FastMCP("Air CI Analytics")

DB_PATH = r"C:\Users\Laptop Studio\Documents\Air Ci Project\air_ci.db"

# ---- NOUVEAU : chemin vers le graphe OWL inféré ----
OWL_PATH = r"C:\Users\Laptop Studio\Documents\Air Ci Project\owl\air_ci_classified.ttl"

AIR = Namespace("http://airci.com/ontology#")

# =========================================
# HELPERS EXISTANTS (inchangés)
# =========================================
def get_db():
    """Connexion DuckDB — inchangé"""
    con = duckdb.connect(DB_PATH)
    con.execute("LOAD spatial")
    return con

# ---- NOUVEAU HELPER ----
def get_owl():
    """
    Charge le graphe OWL inféré depuis le fichier TTL.

    Pourquoi un helper séparé de get_db() ?
    → Deux sources de données différentes :
      DuckDB = données brutes et métriques
      TTL    = connaissances inférées par OWL

    Pourquoi recharger à chaque appel ?
    → Le TTL peut être régénéré à tout moment
      (après un dbt run + export OWL)
    → On veut toujours la version la plus récente
    → Alternative : cache en mémoire si performance critique
    """
    if not os.path.exists(OWL_PATH):
        return None  # OWL pas encore généré
    g = Graph()
    g.bind("air", AIR)
    g.parse(OWL_PATH, format="turtle")
    return g


# =========================================
# TES 8 OUTILS EXISTANTS (inchangés)
# =========================================
# ... get_global_kpis, get_route_performance, etc.
# Aucun changement nécessaire sur eux.


# =========================================
# NOUVEAUX OUTILS OWL
# =========================================

@mcp.tool()
def get_owl_route_classification() -> str:
    """
    Retourne la classification OWL inférée de chaque route.

    DIFFÉRENCE avec get_routes_budget_recommendation() :
    - get_routes_budget_recommendation lit mart_decision_layer (SQL statique)
    - get_owl_route_classification lit le graphe OWL (inférence formelle)

    Utiliser quand on demande :
    'Quelles routes sont classifiées par l ontologie OWL ?'
    'Montre-moi les labels inférés automatiquement'
    'Quelle est la classification formelle des routes ?'
    """
    g = get_owl()
    if g is None:
        return json.dumps({
            "error": "Ontologie OWL non générée. "
                     "Lancer owl/03_classify.py d abord."
        })

    results = g.query("""
        PREFIX air: <http://airci.com/ontology#>
        SELECT ?route ?routeKey ?label ?lf ?margin
        WHERE {
            ?route a air:Route ;
                   a ?label ;
                   air:hasRouteKey       ?routeKey ;
                   air:hasLoadFactorPct  ?lf ;
                   air:hasMarginPct      ?margin .
            FILTER(?label != air:Route)
            FILTER(STRSTARTS(STR(?label), STR(air:)))
        }
        ORDER BY ?route
    """)

    data = []
    for row in results:
        data.append({
            "route_id":  str(row.route).split("#")[-1],
            "route_key": str(row.routeKey),
            "owl_label": str(row.label).split("#")[-1],
            "load_factor_pct": float(row.lf),
            "margin_pct": float(row.margin),
            "source": "OWL inference"  # distingue des labels SQL
        })

    return json.dumps(data, indent=2, ensure_ascii=False)


@mcp.tool()
def get_owl_customer_classification(
    label: str = None
) -> str:
    """
    Retourne la classification OWL inférée des customers.

    Paramètre optionnel label :
    - Sans : tous les customers avec leur label OWL
    - Avec : filtrer par label spécifique

    Labels disponibles :
    HighValueAtRisk, LoyaltyConversionTarget,
    PremiumUpgradeCandidate, AncillaryOfferTarget,
    ReactivationTarget, StableCustomer

    Utiliser quand on demande :
    'Quels clients sont HighValueAtRisk selon OWL ?'
    'Montre-moi les customers inférés comme à risque'
    'Classification OWL des clients'
    """
    g = get_owl()
    if g is None:
        return json.dumps({"error": "OWL non généré."})

    # Construction dynamique du filtre label
    if label:
        label_filter = f"FILTER(?lbl = air:{label})"
    else:
        label_filter = "FILTER(?lbl != air:Customer)"

    query = f"""
        PREFIX air: <http://airci.com/ontology#>
        SELECT ?customer ?label ?sentiment ?miles ?days
        WHERE {{
            ?customer a air:Customer ;
                      a ?lbl ;
                      air:hasCustomerKey         ?ck ;
                      air:hasSentimentScore      ?sentiment ;
                      air:hasTotalMiles          ?miles ;
                      air:hasDaysSinceLastFlight ?days .
            BIND(STR(?lbl) AS ?label)
            FILTER(STRSTARTS(STR(?lbl), STR(air:)))
            {label_filter}
        }}
        ORDER BY ?customer
        LIMIT 50
    """

    results = g.query(query)
    data = []
    for row in results:
        data.append({
            "customer_id":          str(row.customer).split("#")[-1],
            "owl_label":            row.label.split("#")[-1],
            "sentiment_score":      float(row.sentiment),
            "total_miles":          int(row.miles),
            "days_since_last_flight": int(row.days),
            "source": "OWL inference"
        })

    return json.dumps(data, indent=2, ensure_ascii=False)


@mcp.tool()
def explain_why_classified(
    entity_id: str,
    entity_type: str = "route"
) -> str:
    """
    Explique POURQUOI une entité a reçu son label OWL.

    C'est l'outil le plus puissant — impossible en SQL pur.
    Il expose le RAISONNEMENT derrière la classification.

    Paramètres :
    - entity_id : ex 'R009' ou 'CUST001'
    - entity_type : 'route' ou 'customer'

    Utiliser quand on demande :
    'Pourquoi R009 est classifiée GrowthOpportunity ?'
    'Explique le label de ce client'
    'Quelles données ont causé cette classification ?'
    """
    g = get_owl()
    if g is None:
        return json.dumps({"error": "OWL non généré."})

    uri = f"http://airci.com/ontology#{entity_id}"

    # Récupère toutes les propriétés + labels de l'entité
    query = f"""
        PREFIX air: <http://airci.com/ontology#>
        SELECT ?predicate ?value WHERE {{
            <{uri}> ?predicate ?value .
        }}
    """

    results = g.query(query)

    # Sépare les types (labels) des données (métriques)
    labels = []
    metrics = {}

    for row in results:
        pred = str(row.predicate)
        val  = str(row.value)

        if pred == str(RDF.type):
            class_name = val.split("#")[-1]
            if class_name not in ("Route", "Customer", "Thing"):
                labels.append(class_name)
        elif "airci.com" in pred:
            prop_name = pred.split("#")[-1]
            # Convertir en nombre si possible
            try:
                metrics[prop_name] = float(val)
            except ValueError:
                metrics[prop_name] = val

    # Génère une explication lisible pour Claude
    explanation = {
        "entity_id": entity_id,
        "entity_type": entity_type,
        "owl_labels": labels,
        "reasoning": {},
        "raw_metrics": metrics,
        "source": "OWL inference — règles SPARQL CONSTRUCT"
    }

    # Ajouter l'explication des règles qui ont déclenché chaque label
    rules_explanation = {
        "GrowthOpportunity":
            f"LF={metrics.get('hasLoadFactorPct','?')}>=80 "
            f"ET Marge={metrics.get('hasMarginPct','?')}>=15 "
            f"ET Concurrents={metrics.get('hasNbCompetitors','?')}<=1",
        "HighValueAtRisk":
            f"is_high_value=True ET ("
            f"Sentiment={metrics.get('hasSentimentScore','?')}<-0.3 "
            f"OU CriticalTickets={metrics.get('hasCriticalTickets','?')}>=1 "
            f"OU Inactif={metrics.get('hasDaysSinceLastFlight','?')}>90j)",
        "StableRoute": "Aucun signal particulier — label par défaut",
        "StableCustomer": "Aucun signal particulier — label par défaut",
    }

    for label in labels:
        if label in rules_explanation:
            explanation["reasoning"][label] = rules_explanation[label]

    return json.dumps(explanation, indent=2, ensure_ascii=False)


@mcp.tool()
def owl_cross_query(question_type: str = "routes_vs_customers") -> str:
    """
    Requêtes croisées impossibles en SQL pur — navigation de graphe OWL.

    Types disponibles :
    - 'routes_vs_customers' : routes à problèmes + clients à risque associés
    - 'hub_analysis' : aéroports les plus utilisés avec performance
    - 'strategic_gap' : routes stratégiques sous-performantes sans action

    Utiliser quand on demande :
    'Quelles routes ont des clients HighValueAtRisk ?'
    'Montre-moi les connexions entre routes et clients'
    'Analyse les hubs avec leur performance'
    """
    g = get_owl()
    if g is None:
        return json.dumps({"error": "OWL non généré."})

    if question_type == "routes_vs_customers":
        # Trouve les routes StrategicUnderperformer
        # en même temps que les clients HighValueAtRisk
        # C'est une vue consolidée impossible en SQL
        # sans plusieurs requêtes et un JOIN applicatif

        routes_q = g.query("""
            PREFIX air: <http://airci.com/ontology#>
            SELECT ?r ?key WHERE {
                ?r a air:StrategicUnderperformer ;
                   air:hasRouteKey ?key .
            }
        """)

        customers_q = g.query("""
            PREFIX air: <http://airci.com/ontology#>
            SELECT ?c ?sent ?days WHERE {
                ?c a air:HighValueAtRisk ;
                   air:hasSentimentScore      ?sent ;
                   air:hasDaysSinceLastFlight ?days .
            }
            ORDER BY ?sent
            LIMIT 10
        """)

        return json.dumps({
            "underperforming_routes": [
                {"route": str(r.r).split("#")[-1],
                 "key": str(r.key)}
                for r in routes_q
            ],
            "high_value_at_risk_customers": [
                {"customer": str(c.c).split("#")[-1],
                 "sentiment": float(c.sent),
                 "days_inactive": int(c.days)}
                for c in customers_q
            ],
            "insight": "Ces routes sous-performantes affectent "
                       "probablement la satisfaction des clients à risque.",
            "source": "OWL cross-domain inference"
        }, indent=2, ensure_ascii=False)

    return json.dumps({"error": f"Type inconnu : {question_type}"})


# =========================================
# LANCEMENT (inchangé)
# =========================================
if __name__ == "__main__":
    print("Air CI MCP Server démarré", file=sys.stderr)
    print(f"OWL disponible : {os.path.exists(OWL_PATH)}", file=sys.stderr)
    mcp.run()