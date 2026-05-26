# Air CI Project — Analytics Engineering Challenge

## Vue d'ensemble

Pipeline analytics complet pour une compagnie aérienne basée à Abidjan (Côte d'Ivoire).
Ce projet couvre : traitement des données, modélisation dimensionnelle, 
semantic layer, dashboard décisionnel et interface IA via MCP.

---

## Architecture
Excel (Donn.xlsx)
↓
DuckDB (air_ci.db)         ← base de données locale
↓
dbt-fusion                 ← transformation des données
├── staging/             ← 12 modèles de nettoyage
└── marts/               ← 7 modèles analytiques
├── dimensions/    ← dim_date, dim_routes, dim_customers
└── facts/         ← fct_flights, fct_bookings, fct_tickets ,mart_decision_layer
↓
Power BI                   ← dashboard décisionnel (4 pages)
↓
MCP Server (Python)        ← interface IA avec 8 outils

---

## Prérequis

- Python 3.10+
- dbt-fusion 2.0+
- DuckDB 1.5+
- Power BI Desktop (Windows)

---

## Installation

### 1. Clone ou télécharge le projet

```bash
cd "Air Ci Project"
```

### 2. Crée l'environnement virtuel

```powershell
python -m venv superset-env
.\superset-env\Scripts\Activate.ps1
python -m pip install duckdb mcp numpy pandas
```

### 3. Configure DuckDB — crée les vues Excel

```powershell
.\duckdb.exe air_ci.db
```

Dans DuckDB :
```sql
INSTALL spatial;
LOAD spatial;
CREATE SCHEMA IF NOT EXISTS excel_source;

CREATE OR REPLACE VIEW excel_source.Flights AS
SELECT * FROM st_read('Donn.xlsx', layer='Flights');

-- (répéter pour les 12 tables)
.quit
```

### 4. Lance le pipeline dbt

```powershell
dbt run
```

Résultat attendu :
35 total | 35 success

### 5. Lance le MCP Server

```powershell
python mcp_server.py
```

### 6. Ouvre le Dashboard
Ouvre Power BI Desktop
→ Fichier → Ouvrir → air_ci_dashboard.pbix

---

## Structure du projet
Air Ci Project/
├── models/
│   ├── staging/           ← 12 fichiers stg_*.sql
│   └── marts/
│       ├── dimensions/    ← dim_date, dim_routes, dim_customers
│       └── facts/         ← fct_flights, fct_bookings,
│                             fct_tickets, mart_decision_layer
├── macros/
│   └── load_spatial.sql
├── mcp_server.py          ← MCP Server (8 outils IA)
├── test_mcp.py            ← Tests des outils MCP
├── dbt_project.yml        ← Configuration dbt
├── air_ci.db              ← Base DuckDB
├── Donn.xlsx              ← Données source Excel
├── README.md
├── DATA_DICTIONARY.md
└── WRITE_UP.md

---

## Commandes utiles

```powershell
# Lancer le pipeline complet
dbt run

# Tester les modèles
dbt test

# Voir les modèles détectés
dbt list

# Tester le MCP Server
python test_mcp.py

# Lancer le MCP Server
python mcp_server.py
```

---

## Questions d'acceptance couvertes

| Question | Outil MCP | Mart |
|---|---|---|
| Routes à budgéter Q4 ? | get_routes_budget_recommendation | mart_decision_layer |
| Routes non rentables opérationnellement ? | get_route_performance | fct_flights |
| Clients haute valeur à risque ? | get_high_value_at_risk_customers | mart_decision_layer |
| Segments pour offres premium ? | get_upsell_segments | mart_decision_layer |
| Comparer deux routes ? | compare_routes | fct_flights + fct_tickets |
| Preuves d'une recommandation ? | get_unstructured_insights | fct_tickets |
## Connexion Claude Desktop (MCP)

### Prérequis
- Claude Desktop installé (https://claude.ai/download)

### Configuration
1. Ouvre le fichier de config Claude Desktop :
   %APPDATA%\Claude\claude_desktop_config.json

2. Remplace le contenu par (Attention utiser le lien de son propre éberger):
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