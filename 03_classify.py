"""
owl/03_classify.py — VERSION COMPLÈTE CORRIGÉE
Classifie les routes (6 labels) ET les customers (6 labels)
"""

from rdflib import Graph, Namespace, RDF
import os

AIR = Namespace("http://airci.com/ontology#")
g = Graph()
g.parse("owl/air_ci_schema.ttl", format="turtle")
g.parse("owl/air_ci_data.ttl",   format="turtle")
g.bind("air", AIR)

print(f"Base chargée : {len(g)} triplets\n")

# ===========================================
# RÈGLES ROUTES (6 labels)
# ===========================================
regles_routes = [

    ("GrowthOpportunity", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?r a air:GrowthOpportunity . }
        WHERE {
            ?r a air:Route ;
               air:hasLoadFactorPct  ?lf ;
               air:hasMarginPct      ?margin ;
               air:hasNbCompetitors  ?nc .
            FILTER(?lf >= 80.0 && ?margin >= 15.0 && ?nc <= 1)
        }
    """),

    ("StrategicUnderperformer", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?r a air:StrategicUnderperformer . }
        WHERE {
            ?r a air:Route ;
               air:isStrategicRoute true ;
               air:hasMarginPct     ?margin ;
               air:hasDelayRatePct  ?delay .
            FILTER(?margin < 10.0 || ?delay > 30.0)
        }
    """),

    ("OperationallyUnprofitable", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?r a air:OperationallyUnprofitable . }
        WHERE {
            ?r a air:Route ;
               air:hasMarginPct     ?margin ;
               air:hasLoadFactorPct ?lf .
            FILTER(?margin < 0.0 && ?lf >= 65.0)
        }
    """),

    ("DemandUnprofitable", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?r a air:DemandUnprofitable . }
        WHERE {
            ?r a air:Route ;
               air:hasMarginPct     ?margin ;
               air:hasLoadFactorPct ?lf .
            FILTER(?margin < 0.0 && ?lf < 65.0)
        }
    """),

    ("RouteToDefend", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?r a air:RouteToDefend . }
        WHERE {
            ?r a air:Route ;
               air:hasMarginPct          ?margin ;
               air:hasNbCompetitors      ?nc ;
               air:hasAvgSentimentScore  ?sent .
            FILTER(?margin >= 10.0 && ?nc >= 3 && ?sent < -0.3)
        }
    """),

    ("StableRoute", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?r a air:StableRoute . }
        WHERE {
            ?r a air:Route .
            FILTER NOT EXISTS { ?r a air:GrowthOpportunity      }
            FILTER NOT EXISTS { ?r a air:StrategicUnderperformer }
            FILTER NOT EXISTS { ?r a air:OperationallyUnprofitable}
            FILTER NOT EXISTS { ?r a air:DemandUnprofitable      }
            FILTER NOT EXISTS { ?r a air:RouteToDefend           }
        }
    """),
]

# ===========================================
# RÈGLES CUSTOMERS (6 labels)
# ===========================================
regles_customers = [

    ("HighValueAtRisk", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?c a air:HighValueAtRisk . }
        WHERE {
            ?c a air:Customer ;
               air:isHighValue        true ;
               air:hasSentimentScore  ?sent ;
               air:hasCriticalTickets ?crit ;
               air:hasDaysSinceLastFlight ?days .
            FILTER(?sent < -0.3 || ?crit >= 1 || ?days > 90)
        }
    """),

    ("LoyaltyConversionTarget", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?c a air:LoyaltyConversionTarget . }
        WHERE {
            ?c a air:Customer ;
               air:isLoyaltyMember  false ;
               air:hasTotalBookings ?bookings ;
               air:hasTotalRevenue  ?rev .
            FILTER(?bookings >= 2 && ?rev >= 300.0)
        }
    """),

    ("PremiumUpgradeCandidate", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?c a air:PremiumUpgradeCandidate . }
        WHERE {
            ?c a air:Customer ;
               air:hasCustomerSegment   ?seg ;
               air:hasTotalMiles        ?miles ;
               air:hasAncillaryAttachRate ?anc .
            FILTER(?seg = "standard" && ?miles >= 5000 && ?anc >= 50.0)
        }
    """),

    ("AncillaryOfferTarget", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?c a air:AncillaryOfferTarget . }
        WHERE {
            ?c a air:Customer ;
               air:hasTotalBookings      ?bookings ;
               air:hasAncillaryAttachRate ?anc ;
               air:hasSentimentScore     ?sent .
            FILTER(?bookings >= 2 && ?anc < 30.0 && ?sent >= -0.2)
        }
    """),

    ("ReactivationTarget", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?c a air:ReactivationTarget . }
        WHERE {
            ?c a air:Customer ;
               air:hasDaysSinceLastFlight ?days ;
               air:hasTotalBookings       ?bookings .
            FILTER(?days > 180 && ?bookings >= 1)
        }
    """),

    ("StableCustomer", """
        PREFIX air: <http://airci.com/ontology#>
        CONSTRUCT { ?c a air:StableCustomer . }
        WHERE {
            ?c a air:Customer .
            FILTER NOT EXISTS { ?c a air:HighValueAtRisk          }
            FILTER NOT EXISTS { ?c a air:LoyaltyConversionTarget  }
            FILTER NOT EXISTS { ?c a air:PremiumUpgradeCandidate  }
            FILTER NOT EXISTS { ?c a air:AncillaryOfferTarget     }
            FILTER NOT EXISTS { ?c a air:ReactivationTarget       }
        }
    """),
]

# ===========================================
# APPLICATION
# ===========================================
print("=== CLASSIFICATION DES ROUTES ===")
for nom, regle in regles_routes:
    triplets = list(g.query(regle))
    for t in triplets: g.add(t)
    print(f"  {nom:30} → {len(triplets)} route(s)")

print("\n=== CLASSIFICATION DES CUSTOMERS ===")
for nom, regle in regles_customers:
    triplets = list(g.query(regle))
    for t in triplets: g.add(t)
    print(f"  {nom:30} → {len(triplets)} customer(s)")

# ===========================================
# RÉSUMÉ FINAL
# ===========================================
print("\n=== RÉSUMÉ FINAL ===")
for entite, classe_mere in [("Routes", "Route"), ("Customers", "Customer")]:
    res = g.query(f"""
        PREFIX air: <http://airci.com/ontology#>
        SELECT ?e ?label WHERE {{
            ?e a air:{classe_mere} ; a ?label .
            FILTER(?label != air:{classe_mere})
            FILTER(STRSTARTS(STR(?label), STR(air:)))
        }} ORDER BY ?e
    """)
    print(f"\n{entite} :")
    for row in res:
        eid   = str(row.e).split("#")[-1]
        label = str(row.label).split("#")[-1]
        print(f"  {eid:15} → {label}")

os.makedirs("owl", exist_ok=True)
g.serialize(destination="owl/air_ci_classified.ttl", format="turtle")
print(f"\nFichier final : {len(g)} triplets")