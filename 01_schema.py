"""
owl/01_schema.py — VERSION COMPLÈTE CORRIGÉE
Inclut Route ET Customer avec toutes leurs
sous-classes métier du projet Air CI.
"""

from rdflib import Graph, Namespace, RDF, RDFS, OWL, XSD, Literal
import os

AIR = Namespace("http://airci.com/ontology#")
g = Graph()
g.bind("air", AIR)
g.bind("owl", OWL)
g.bind("rdfs", RDFS)

# ===========================================
# HELPER
# ===========================================
def classe(nom, parent=None, label=None, comment=None):
    uri = AIR[nom]
    g.add((uri, RDF.type, OWL.Class))
    if parent:
        g.add((uri, RDFS.subClassOf, parent))
    if label:
        g.add((uri, RDFS.label, Literal(label, lang="fr")))
    if comment:
        g.add((uri, RDFS.comment, Literal(comment, lang="fr")))
    return uri

def data_prop(nom, domaine, xsd_type, comment=None):
    uri = AIR[nom]
    g.add((uri, RDF.type, OWL.DatatypeProperty))
    g.add((uri, RDFS.domain, domaine))
    g.add((uri, RDFS.range, xsd_type))
    if comment:
        g.add((uri, RDFS.comment, Literal(comment, lang="fr")))
    return uri

def obj_prop(nom, domaine, range_, comment=None):
    uri = AIR[nom]
    g.add((uri, RDF.type, OWL.ObjectProperty))
    g.add((uri, RDFS.domain, domaine))
    g.add((uri, RDFS.range, range_))
    if comment:
        g.add((uri, RDFS.comment, Literal(comment, lang="fr")))
    return uri

# ===========================================
# CLASSES DE DÉPART
# Ces classes correspondent aux dimensions dbt.
# Elles définissent ce qu'est une entité.
# ===========================================

# Route = dim_routes dans dbt
Route = classe("Route",
    label="Route aérienne",
    comment="Équivalent de la table main_marts.dim_routes."
)

# Customer = dim_customers dans dbt
Customer = classe("Customer",
    label="Client Air CI",
    comment="Équivalent de la table main_marts.dim_customers."
)

# Classes de contexte (pour les ObjectProperty)
Airport = classe("Airport",
    label="Aéroport",
    comment="Classe de contexte. Permet hasOrigin et hasDestination."
)
Airline = classe("Airline",
    label="Compagnie aérienne",
    comment="Classe de contexte. Permet hasCompetitor."
)

# ===========================================
# PROPRIÉTÉS DE DONNÉES — ROUTE
# Sélection : uniquement celles utiles aux règles
# Source : dim_routes + AVG(fct_flights)
# ===========================================

# Pour les règles GrowthOpportunity et autres
data_prop("hasLoadFactorPct", Route, XSD.decimal,
    "AVG(fct_flights.load_factor_pct). Seuils: <60% bas, >85% haut.")
data_prop("hasMarginPct", Route, XSD.decimal,
    "AVG(fct_flights.flight_margin_pct). <0% = non rentable.")
data_prop("hasDelayRatePct", Route, XSD.decimal,
    "% vols retardés. >30% = problème opérationnel.")
data_prop("hasNbCompetitors", Route, XSD.integer,
    "dim_routes.nb_competitors. 0=monopole.")
data_prop("isStrategicRoute", Route, XSD.boolean,
    "dim_routes.is_strategic_route.")
data_prop("hasRouteKey", Route, XSD.string,
    "dim_routes.route_key. Ex: ABJ-CDG.")
data_prop("hasAvgSentimentScore", Route, XSD.decimal,
    "AVG sentiment des tickets sur cette route. Pour RouteToDefend.")

# ===========================================
# PROPRIÉTÉS DE DONNÉES — CUSTOMER
# Source : dim_customers
# ===========================================

# Pour les règles HighValueAtRisk, LoyaltyConversionTarget...
data_prop("isHighValue", Customer, XSD.boolean,
    "dim_customers.is_high_value. True si segment premium "
    "OU tier Gold/Platinum OU miles >= 10000.")

data_prop("isAtRisk", Customer, XSD.boolean,
    "dim_customers.is_at_risk. True si sentiment < -0.3 "
    "OU critical_tickets >= 1 OU inactif > 90j.")

data_prop("hasSentimentScore", Customer, XSD.decimal,
    "dim_customers.avg_sentiment_score. Échelle -1 à +1.")

data_prop("hasTotalMiles", Customer, XSD.integer,
    "dim_customers.total_miles. Pour PremiumUpgradeCandidate.")

data_prop("hasTotalBookings", Customer, XSD.integer,
    "Nombre total de réservations. Pour LoyaltyConversionTarget.")

data_prop("hasTotalRevenue", Customer, XSD.decimal,
    "Revenu total généré par ce client. USD.")

data_prop("hasAncillaryAttachRate", Customer, XSD.decimal,
    "% de réservations avec achat ancillaire. "
    "Pour AncillaryOfferTarget et PremiumUpgradeCandidate.")

data_prop("hasDaysSinceLastFlight", Customer, XSD.integer,
    "Jours depuis le dernier vol. >180j = ReactivationTarget.")

data_prop("isLoyaltyMember", Customer, XSD.boolean,
    "True si loyalty_tier NOT IN (None, null, ''). "
    "Pour LoyaltyConversionTarget.")

data_prop("hasCriticalTickets", Customer, XSD.integer,
    "Nombre de tickets urgency=critical. Pour is_at_risk.")

data_prop("hasCustomerSegment", Customer, XSD.string,
    "standard / business / premium.")

data_prop("hasCustomerKey", Customer, XSD.string,
    "dim_customers.customer_id.")

# ===========================================
# PROPRIÉTÉS D'OBJET
# Relations entre entités (les FK de dbt)
# ===========================================

obj_prop("hasOrigin", Route, Airport,
    "Aéroport de départ. = dim_routes.origin_airport_code.")
obj_prop("hasDestination", Route, Airport,
    "Aéroport d'arrivée.")
obj_prop("hasCompetitor", Route, Airline,
    "Compagnie concurrente sur cette route.")

# ===========================================
# SOUS-CLASSES MÉTIER — ROUTE (6 labels)
# Ces classes correspondent aux labels de
# mart_decision_layer WHERE entity_type='route'
# ===========================================

classe("GrowthOpportunity", Route,
    "Route à fort potentiel de croissance",
    "LF>=80% ET marge>=15% ET concurrents<=1. "
    "SQL: WHEN avg_load_factor_pct >= 80 "
    "AND avg_margin_pct >= 15 AND nb_competitors <= 1.")

classe("StrategicUnderperformer", Route,
    "Route stratégique sous-performante",
    "is_strategic=true ET (marge<10% OU retard>30%). "
    "SQL: WHEN is_strategic_route = true "
    "AND (avg_margin_pct < 10 OR delay_rate_pct > 30).")

classe("OperationallyUnprofitable", Route,
    "Route non rentable par problèmes opérationnels",
    "marge<0% ET LF>=65% ET retards opérationnels > météo. "
    "SQL: WHEN avg_margin_pct < 0 AND avg_load_factor_pct >= 65.")

classe("DemandUnprofitable", Route,
    "Route non rentable par manque de demande",
    "marge<0% ET LF<65%. "
    "SQL: WHEN avg_margin_pct < 0 AND avg_load_factor_pct < 65.")

classe("RouteToDefend", Route,
    "Route rentable sous pression concurrentielle",
    "marge>=10% ET concurrents>=3 ET sentiment<-0.3. "
    "SQL: WHEN avg_margin_pct >= 10 "
    "AND nb_competitors >= 3 AND avg_sentiment_score < -0.3.")

classe("StableRoute", Route,
    "Route stable sans signal particulier",
    "Défaut — aucun autre label applicable. "
    "SQL: ELSE 'StableRoute'.")

# ===========================================
# SOUS-CLASSES MÉTIER — CUSTOMER (6 labels)
# Ces classes correspondent aux labels de
# mart_decision_layer WHERE entity_type='customer'
# ===========================================

classe("HighValueAtRisk", Customer,
    "Client haute valeur à risque de churn",
    "is_high_value=true ET (sentiment<-0.3 "
    "OU critical_tickets>=1 OU inactif>90j). "
    "SQL: WHEN is_high_value = true "
    "AND (sentiment < -0.3 OR critical_tickets >= 1 "
    "OR days_inactive > 90).")

classe("LoyaltyConversionTarget", Customer,
    "Client à convertir au programme fidélité",
    "Non-membre ET bookings>=2 ET revenue>=300 USD. "
    "SQL: WHEN is_loyalty_member = false "
    "AND total_bookings >= 2 AND total_revenue >= 300.")

classe("PremiumUpgradeCandidate", Customer,
    "Client éligible à une offre premium",
    "Segment standard ET miles>=5000 ET ancillary>=50%. "
    "SQL: WHEN customer_segment = 'standard' "
    "AND total_miles >= 5000 "
    "AND ancillary_attach_rate >= 0.5.")

classe("AncillaryOfferTarget", Customer,
    "Client cible pour les offres ancillaires",
    "bookings>=2 ET ancillary<30% ET sentiment>=-0.2. "
    "SQL: WHEN total_bookings >= 2 "
    "AND ancillary_attach_rate < 0.3 "
    "AND avg_sentiment_score >= -0.2.")

classe("ReactivationTarget", Customer,
    "Client inactif à réactiver",
    "inactif>180j ET au moins 1 booking historique. "
    "SQL: WHEN days_since_last_flight > 180 "
    "AND total_bookings >= 1.")

classe("StableCustomer", Customer,
    "Client stable sans signal particulier",
    "Défaut — aucun autre label applicable. "
    "SQL: ELSE 'StableCustomer'.")

# ===========================================
# DISJONCTIONS LOGIQUES
# Un customer ne peut pas être à la fois
# HighValueAtRisk ET StableCustomer
# ===========================================

g.add((AIR.HighValueAtRisk, OWL.disjointWith, AIR.StableCustomer))
g.add((AIR.GrowthOpportunity, OWL.disjointWith, AIR.DemandUnprofitable))
g.add((AIR.GrowthOpportunity, OWL.disjointWith, AIR.StrategicUnderperformer))

# ===========================================
# SAUVEGARDE
# ===========================================
os.makedirs("owl", exist_ok=True)
g.serialize(destination="owl/air_ci_schema.ttl", format="turtle")
print(f"Schéma complet : {len(g)} triplets")
print(f"Classes Route   : 1 mère + 6 métier")
print(f"Classes Customer: 1 mère + 6 métier")
print(f"Classes contexte: Airport + Airline")