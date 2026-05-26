# Write-Up — Air CI Analytics Engineering Challenge

## 1. Assumptions

### Données
- Les données couvrent la période 2024-2025 pour une airline fictive
  basée à Abidjan (ABJ), Côte d'Ivoire
- 12 routes opérées : 3 domestiques, 8 régionales, 1 internationale (Paris)
- Le sentiment score des tickets est pré-calculé via NLP externe
- La date dans Flight_costs = date du vol concerné (clé composite)
- Les coûts sont en USD pour uniformité

### Modélisation
- Star Schema choisi vs Data Vault car :
  → Optimal pour les performances analytiques de DuckDB
  → Structure simple et lisible pour le MCP Server
  → Adapté à un volume de données moyen (< 1M lignes)
  → Facilite les requêtes Superset/Power BI

### Seuils métier
- Load Factor seuil : 60% (sous-rempli) / 85% (bien rempli)
- Délai significatif : >= 15 minutes (standard IATA)
- SLA tickets : 3 jours maximum
- Client inactif : > 180 jours sans vol
- Client à risque : sentiment < -0.3 OU tickets critiques >= 1

---

## 2. Architecture
COUCHE 1 — SOURCES
Excel (Donn.xlsx) → 12 onglets → vues DuckDB via st_read()
COUCHE 2 — STAGING (dbt views)
12 modèles stg_*.sql
→ Nettoyage, cast, nullif, trim
→ Flags qualité (is_id_missing, is_fk_missing...)
→ Colonnes calculées métier
→ Détection mots clés NLP (tickets)
COUCHE 3 — MARTS (dbt tables)
3 dimensions : dim_date, dim_routes, dim_customers
4 facts : fct_flights, fct_bookings, fct_tickets,
mart_decision_layer
COUCHE 4 — SEMANTIC LAYER
13 KPIs définis dans semantic_layer.yml
(load_factor, yield, RASK, CASK, CLV...)
COUCHE 5 — ONTOLOGIE
mart_decision_layer applique des règles d'inférence :
→ 6 labels routes (GrowthOpportunity, StrategicUnderperformer...)
→ 6 labels clients (HighValueAtRisk, PremiumUpgradeCandidate...)
→ Recommandations actionnables par entité
COUCHE 6 — EXPOSITION
Power BI : dashboard 4 pages via ODBC DuckDB
MCP Server : 8 outils Python exposant les marts à l'IA

---

## 3. Intégration données non structurées

Les commentaires clients (Customer_service_tickets) sont traités via :

### Approche 1 — Sentiment Score (pré-calculé)
sentiment_score : -1 à +1
→ Fourni dans les données source
→ Calculé externement via NLP multilingue
→ Catégorisé en : very_negative, negative, neutral, positive

### Approche 2 — Détection mots clés SQL
```sql
-- 10 catégories de plaintes détectées via LIKE
has_delay_keyword       → retard, retardé, correspondance
has_baggage_keyword     → bagage, valise, sac de voyage
has_refund_keyword      → remboursement, débité
has_cancellation_keyword→ annulé, annulation
has_overbooking_keyword → surréservation, refusé l'embarquement
has_meal_keyword        → repas, immangeable, végétarien
has_seat_keyword        → siège, hublot, sièges sales
has_comfort_keyword     → climatisation, insupportable
has_digital_keyword     → application mobile, site web
has_staff_keyword       → personnel, désagréable
```

### Approche 3 — Corrélation structuré/non-structuré
is_delay_complaint_confirmed :
→ Le ticket parle de retard ET le vol était retardé
→ Valide la cohérence des données
is_operational_delay :
→ Retard non expliqué par la météo
→ Croise fct_flights + stg_weather_impact

---

## 4. Limitations

### Techniques
- Python 3.14 incompatible avec Superset → utilisation Power BI
- dbt-fusion (preview) → syntaxe légèrement différente de dbt standard
- Semantic Layer non validé en local (nécessite dbt Cloud)

### Données
- Load Factor moyen faible (16%) → données partielles ou période courte
- Sentiment pré-calculé → pas de NLP custom développé
- Pas de données historiques longues → tendances limitées
- Cargo uniquement sur 3 vols → échantillon insuffisant

### Modélisation
- Star Schema → pas d'historisation (pas de SCD Type 2)
- Pas de tests dbt formels (dbt test)
- mart_decision_layer → règles ontologiques fixes (pas de ML)

---

## 5. Next Steps

### Court terme

Connecter MCP Server à Claude.ai via claude_desktop_config.json
Ajouter dbt tests (unique, not_null, accepted_values)
Implémenter SCD Type 2 sur dim_customers pour l'historisation
Enrichir le NLP avec un modèle CamemBERT (français)


### Moyen terme

Ajouter des données temps réel (API météo, prix concurrents)
Construire un modèle de prédiction churn (scikit-learn)
Automatiser le pipeline avec Airflow ou dbt Cloud
Migrer vers une vraie base cloud (Snowflake, BigQuery)


### Long terme

Ontologie formelle OWL/RDF pour raisonnement automatique
Agent IA autonome qui génère des recommandations
et les envoie directement aux équipes concernées


---

## 6. Réponses aux questions d'acceptance

### Q1 : Quelles routes méritent plus de budget Q4 ?
→ Voir mart_decision_layer WHERE ontology_label = 'GrowthOpportunity'
→ Critères : LF >= 80%, marge >= 15%, peu de concurrence
→ Outil MCP : get_routes_budget_recommendation()

### Q2 : Routes non rentables par problèmes opérationnels ?
→ ontology_label = 'OperationallyUnprofitable'
→ Critères : marge < 0% MAIS LF >= 65% ET délais opérationnels > météo
→ Outil MCP : get_route_performance()

### Q3 : Clients haute valeur à risque de churn ?
→ dim_customers WHERE is_high_value = true AND is_at_risk = true
→ ontology_label = 'HighValueAtRisk'
→ Outil MCP : get_high_value_at_risk_customers()

### Q4 : Segments pour offres premium ?
→ PremiumUpgradeCandidate : standard + miles >= 5000
→ AncillaryOfferTarget : bookings >= 2 + ancillary < 30%
→ Outil MCP : get_upsell_segments()

### Q5 : Comparer deux routes ?
→ Outil MCP : compare_routes('R001', 'R009')
→ Signaux financiers : revenue, marge, yield, RASK/CASK
→ Signaux satisfaction : sentiment, plaintes, SLA

### Q6 : Preuves d'une recommandation ?
→ Outil MCP : get_unstructured_insights(category='delay')
→ Croise commentaires NLP + données opérationnelles
→ is_delay_complaint_confirmed valide la cohérence

## Connexion Claude Desktop (MCP)

### Prérequis
- Claude Desktop installé (https://claude.ai/download)

### Configuration
1. Ouvre le fichier de config Claude Desktop :
   %APPDATA%\Claude\claude_desktop_config.json

2. Remplace le contenu par (Changer le chemin en fonction devotre hebergement):
```json
{
  "mcpServers": {
    "air-ci-analytics": {
      "command": "C:\\Users\\Laptop Studio\\Documents\\Air Ci Project\\superset-env\\Scripts\\python.exe",
      "args": [
        "C:\\Users\\Laptop Studio\\Documents\\Air Ci Project\\mcp_server.py"
      ],
      "cwd": "C:\\Users\\Laptop Studio\\Documents\\Air Ci Project"
    }
  }
}
```

3. Redémarre Claude Desktop
4. Settings → Developer → air-ci-analytics → running

### Questions de démonstration
- "Which routes should receive more budget next quarter ?"
- "Which customers are high value and at risk of churn ?"
- "What complaints are driving low satisfaction on route R009 ?"
- "Compare routes R001 and R009 using financial and satisfaction signals."
- "Which customer segments should receive premium upgrade offers ?"

### Architecture MCP
Claude Desktop
↓ MCP Protocol
mcp_server.py (Python)
↓ SQL queries
DuckDB (air_ci.db)
↓
marts dbt (structured)
+
fct_tickets commentaires (unstructured NLP)

### 8 outils exposés
1. get_global_kpis            → vue d ensemble airline
2. get_route_performance      → performance par route
3. get_routes_budget_recommendation → budget Q4
4. get_complaints_by_route    → plaintes NLP par route
5. compare_routes             → comparaison 2 routes
6. get_high_value_at_risk_customers → churn risk
7. get_upsell_segments        → offres premium
8. get_unstructured_insights  → analyse commentaires

### Données non structurées
Le MCP expose les commentaires clients analysés via NLP :
- sentiment_score : -1 a +1
- primary_complaint_category : delay, baggage, refund...
- urgency_level : critical, high, medium, low
- is_high_value_critical_ticket : flag prioritaire