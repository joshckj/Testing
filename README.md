# backend_gasleakagent

> **SP Digital — Gas Leak Prediction Agent**
> A production-ready FastAPI backend that accepts natural language messages, routes them through a Qwen-powered LangChain agent, and executes the appropriate ML skill — either running a gas leak risk prediction or retraining the CatBoost model.

---

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Folder Structure](#folder-structure)
- [How It Works](#how-it-works)
- [API Reference](#api-reference)
- [Skills](#skills)
- [Data Sources](#data-sources)
- [Infrastructure](#infrastructure)
- [Setup](#setup)
- [Environment Variables](#environment-variables)
- [Creating a New Skill](#creating-a-new-skill)
- [Common Errors](#common-errors)

---

## Overview

This backend serves as the intelligence layer for SP Digital's gas leak prediction system. It:

- Accepts natural language from a frontend via a single `/chat` endpoint
- Uses a **Qwen LLM** (via LangChain) to understand user intent and route to the correct skill
- Fetches operational data from **PostgreSQL**
- Loads the trained ML model from **Azure Blob Storage**
- Runs a **CatBoost** regression model to predict gas leak risk across Singapore's hex grid
- Returns predictions and an interactive hex map to the frontend

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        Frontend                         │
│                  POST /chat { message }                 │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│                   FastAPI Backend                        │
│                                                         │
│   api/routes.py → gasleakagent/agent.py (Qwen LLM)     │
│                            │                            │
│          ┌─────────────────┴──────────────────┐         │
│          │                                    │         │
│   analysis_map skill                retrain_model skill │
│          │                                    │         │
│   PostgreSQL (data)          PostgreSQL (data)          │
│   Azure Blob (model)         Azure Blob (model upload)  │
└─────────────────────────────────────────────────────────┘
```

---

## Folder Structure

```
backend_gasleakagent/
│
├── Dockerfile                          ← Builds app into a container image
├── docker-compose.yml                  ← Runs app + PostgreSQL locally
├── .dockerignore                       ← Files excluded from Docker build
├── Makefile                            ← Shortcuts for common commands
├── run.py                              ← FastAPI app entry point
├── requirements.txt                    ← Python dependencies
├── start.sh                            ← Local dev startup script
├── nginx.conf                          ← Nginx reverse proxy config
├── .env                                ← Secrets and API keys (never commit)
├── .env.example                        ← Template for environment variables
├── .gitignore                          ← Files excluded from Git
├── .dockerignore                       ← Files excluded from Docker
├── README.md                           ← This file
│
├── build/                              ← Infrastructure and deployment
│   ├── ci/
│   │   ├── Jenkinsfile                 ← Jenkins CI/CD pipeline
│   │   └── ci.yml                      ← GitHub/GitLab Actions pipeline
│   └── k8s/
│       ├── deployment.yaml             ← Kubernetes deployment config
│       ├── service.yaml                ← Kubernetes service (exposes app)
│       └── configmap.yaml              ← Non-secret environment variables
│
├── data/                               ← Reference documents only (not operational data)
│   ├── domain_knowledge/               ← SP Digital domain context and guides
│   └── ...
│
├── docs/                               ← Project documentation
│   └── ...
│
├── ingestion/                          ← Data pipeline scripts
│   └── ...                             ← Scripts for loading data into PostgreSQL
│
├── others/                             ← Miscellaneous files
│   └── ...
│
├── utils/
│   └── scripts/                        ← Shared utility scripts
│
└── gasleakagent/                       ← Main application package
    │
    ├── api/                            ← API layer
    │   ├── __init__.py
    │   └── routes.py                   ← POST /chat, GET /map, GET /download, GET /health
    │
    ├── core/                           ← App-wide configuration
    │   ├── __init__.py
    │   ├── config.py                   ← All settings and file paths
    │   └── llm.py                      ← Qwen LLM connection via LangChain
    │
    ├── db/                             ← Data layer
    │   ├── __init__.py
    │   ├── client.py                   ← PostgreSQL engine + Azure Blob connection
    │   └── queries.py                  ← SQL queries for leaks and pipe data
    │
    ├── agent.py                        ← LangChain agent — routes messages to skills
    │
    ├── skills/                         ← Self-contained ML skill pipelines
    │   │
    │   ├── template/                   ← Starter template for new skills
    │   │   ├── SKILL.md                ← Skill documentation
    │   │   ├── assets/                 ← Static files (shapefiles, configs)
    │   │   ├── scripts/
    │   │   │   ├── __init__.py
    │   │   │   └── main.py             ← Skill entry point
    │   │   └── utils/                  ← Skill-specific helpers
    │   │
    │   ├── analysis_map/               ← Gas leak risk prediction + hex map
    │   │   ├── SKILL.md
    │   │   ├── assets/
    │   │   │   ├── hexagon_data/       ← Singapore hexagon shapefile (static)
    │   │   │   └── mapsheet_data/      ← Mapsheet shapefile (static)
    │   │   └── scripts/
    │   │       ├── __init__.py
    │   │       ├── main.py
    │   │       ├── gas_leak_cleaner.py
    │   │       ├── pipe_data_cleaner.py
    │   │       ├── hex_mapper.py
    │   │       ├── pipe_aggregator.py
    │   │       ├── prediction_period_filter.py
    │   │       ├── predictor.py
    │   │       └── hex_map_visualiser.py
    │   │
    │   └── retrain_model/              ← CatBoost model retraining
    │       ├── SKILL.md
    │       ├── assets/
    │       │   ├── hexagon_data/       ← Singapore hexagon shapefile (static)
    │       │   └── mapsheet_data/      ← Mapsheet shapefile (static)
    │       └── scripts/
    │           ├── __init__.py
    │           ├── main.py
    │           ├── gas_leak_cleaner.py
    │           ├── pipe_data_cleaner.py
    │           ├── hex_mapper.py
    │           ├── pipe_aggregator.py
    │           ├── data_builder.py
    │           └── model_trainer.py
    │
    └── utils/                          ← Shared backend helpers
        └── models.py                   ← Pydantic request/response shapes
```

---

## How It Works

```
1. Server starts
      → Downloads gasleakmodel.cbm from Azure Blob Storage

2. Frontend sends POST /chat { "message": "run analysis for Q1 2025" }
      → api/routes.py receives the request

3. gasleakagent/agent.py passes message to Qwen LLM via LangChain
      → Qwen reads skill descriptions and decides which tool to call
      → Asks user for any missing inputs (quarter, year, thresholds)

4. Skill executes
      → Fetches data from PostgreSQL
      → Runs CatBoost model loaded from Azure Blob
      → Generates prediction CSV and interactive HTML hex map

5. Response returned to frontend
      → GET /map/<filename>      displays hex map on UI
      → GET /download/<filename> downloads prediction CSV
```

---

## API Reference

### `POST /chat`
Send a natural language message to the agent.

| | |
|---|---|
| **URL** | `http://localhost:8000/chat` |
| **Auth** | None (internal use) |
| **Content-Type** | `application/json` |

**Request:**
```json
{
  "message": "Run analysis for Q1 2025"
}
```

**Response (success):**
```json
{
  "response": "Q1 2025 analysis complete. High: 4 hex cells, Medium: 11, Low: 23, Minimal: 108."
}
```

**Response (validation error):**
```json
{
  "detail": "Message cannot be empty."
}
```

---

### `GET /map/{filename}`
Serve the generated Folium HTML hex map to the frontend for display.

```
GET /map/Q1_2025_25_15_5.html
→ Returns full HTML map for embedding in frontend UI
```

---

### `GET /download/{filename}`
Download the prediction output as a CSV file.

```
GET /download/Prediction-Q12025.csv
→ Returns CSV file as a download
```

---

### `GET /health`
Check if the server is running.

```json
{ "status": "ok" }
```

---

## HTTP Status Codes

| Code | Meaning |
|---|---|
| `200` | Success |
| `404` | File not found |
| `422` | Validation error — message empty or wrong format |
| `500` | Internal server error |

---

## Skills

### `analysis_map`
Predicts gas leak risk across Singapore's hex grid for a given quarter and year.
Uses the CatBoost model to classify each hex cell into a risk tier and generates
an interactive Folium HTML map.

| | |
|---|---|
| **Triggered by** | "run analysis", "predict risk", "show map", "Q1 2025", "high risk areas" |
| **Required inputs** | Quarter (Q1–Q4), Year |
| **Optional inputs** | Risk thresholds — defaults: High=25, Medium=15, Low=5 |
| **Data source** | PostgreSQL — `dmis_main_leaks`, `pipe_data_files` |
| **Model** | CatBoost — downloaded from Azure Blob on startup |
| **Risk tiers** | High / Medium / Low / Minimal |

---

### `retrain_model`
Retrains the CatBoost model on all available historical data from PostgreSQL
and uploads the new model back to Azure Blob Storage.

| | |
|---|---|
| **Triggered by** | "retrain", "update model", "new data added", "train again" |
| **Required inputs** | None — fetches all data from PostgreSQL automatically |
| **Data source** | PostgreSQL — `dmis_main_leaks`, `pipe_data_files` |
| **Output** | New `gasleakmodel.cbm` uploaded to Azure Blob |

---

## Data Sources

| Data | Storage | Access Method |
|---|---|---|
| Gas leak incident records | PostgreSQL — `dmis_main_leaks` | `db/queries.fetch_leaks()` |
| Pipe asset attributes | PostgreSQL — `pipe_data_files` | `db/queries.fetch_pipes()` |
| Trained CatBoost model | Azure Blob Storage | Downloaded on server startup |
| Hex map output | Returned in memory | Served via `GET /map/<filename>` |
| Prediction CSV | Returned in memory | Downloaded via `GET /download/<filename>` |

---

## Infrastructure

### Local Development
```bash
# Start with venv
./start.sh

# Or with Docker Compose (includes PostgreSQL)
docker-compose up
```

### Docker
```bash
# Build image
docker build -t backend-gasleakagent .

# Run container
docker run -p 8000:8000 --env-file .env backend-gasleakagent
```

### Makefile shortcuts
```bash
make run       # start locally
make build     # build Docker image
make up        # start with docker-compose
make down      # stop docker-compose
make deploy    # deploy to Kubernetes
make logs      # tail k8s logs
```

### Kubernetes
```bash
kubectl apply -f build/k8s/
```

Configs in `build/k8s/`:
- `deployment.yaml` — how to run the app
- `service.yaml` — how to expose it
- `configmap.yaml` — non-secret environment config

### CI/CD
Pipeline configs in `build/ci/`:
- `Jenkinsfile` — Jenkins pipeline
- `ci.yml` — GitHub/GitLab Actions

On every push to `main`:
1. Installs dependencies
2. Builds Docker image
3. Pushes to Azure Container Registry
4. Deploys to Kubernetes cluster

---

## Setup

### Prerequisites
- Python 3.11+
- Docker (for containerised dev)
- Access to PostgreSQL database
- Access to Azure Blob Storage
- Qwen API key

### 1. Clone and navigate
```bash
cd backend_gasleakagent
```

### 2. Create virtual environment
```bash
python3 -m venv .venv
source .venv/bin/activate
```

### 3. Install dependencies
```bash
pip install -r requirements.txt
```

### 4. Set up environment variables
```bash
cp .env.example .env
# Fill in all values — see Environment Variables section
```

### 5. Start the server
```bash
chmod +x start.sh
./start.sh
```

Server runs at `http://localhost:8000`

---

## Environment Variables

| Variable | Description |
|---|---|
| `QWEN_API_KEY` | Qwen API key |
| `QWEN_BASE_URL` | Qwen API base URL |
| `QWEN_MODEL` | Model name e.g. `Qwen/Qwen3-30B-A3B` |
| `DB_URL` | PostgreSQL connection string e.g. `postgresql://user:pass@host:5432/db` |
| `AZURE_STORAGE_CONNECTION_STRING` | Azure Blob Storage connection string |
| `AZURE_CONTAINER_NAME` | Azure Blob container name |
| `AZURE_MODEL_BLOB_NAME` | Path to model blob e.g. `models/gasleakmodel.cbm` |

---

## Dependencies

```
fastapi
uvicorn
pydantic
pydantic-settings
langchain
langchain-openai
catboost
geopandas
folium
pandas
numpy
python-dotenv
sqlalchemy
psycopg2-binary
azure-storage-blob
```

---

## Creating a New Skill

1. Copy the template:
```bash
cp -r gasleakagent/skills/template gasleakagent/skills/your_skill_name
```

2. Fill in `SKILL.md` — document inputs, outputs, and when the agent should call it

3. Write your pipeline in `scripts/main.py`

4. Register as a LangChain tool in `gasleakagent/agent.py`:
```python
@tool
def your_skill_name(param: str) -> str:
    """Describe what this skill does so the LLM knows when to call it."""
    result = subprocess.run(
        ["python3", "gasleakagent/skills/your_skill_name/scripts/main.py"],
        capture_output=True, text=True,
        cwd=ROOT_DIR
    )
    return result.stdout or result.stderr

tools = [analysis_map, retrain_model, your_skill_name]
```

---

## Common Errors

| Error | Cause | Fix |
|---|---|---|
| `ModuleNotFoundError: core.config` | Wrong working directory | Run from project root |
| `ModuleNotFoundError: backend_gasleakagent` | Wrong import path | Change to `from core.config import ...` |
| `OperationalError` | PostgreSQL unreachable | Check `DB_URL` in `.env` |
| `ResourceNotFoundError` | Azure Blob not connected | Check Azure credentials in `.env` |
| `FileNotFoundError` on scripts | Wrong `cwd` in subprocess | Set `cwd=ROOT_DIR` in `agent.py` |
| `ValueError: all targets equal` | Bad data in PostgreSQL | Check `dmis_main_leaks` table |
| `uvicorn: command not found` | Not in venv | Run `source .venv/bin/activate` first |

---

## Notes

- Always run from the project root — not from inside any subfolder
- Use `python3` not `python` on Mac
- Model source of truth is **Azure Blob Storage** — downloaded fresh on every server start
- After retraining, new model is auto-uploaded to Azure Blob and available immediately
- Shapefiles in `assets/` are static — do not modify unless boundaries officially change
- `catboost_info/` is auto-generated during retraining — already in `.gitignore`
- `data/` folder contains reference documents only — not operational data
- `ingestion/` contains data pipeline scripts for loading data into PostgreSQL
- Secrets must never be committed — always use `.env` and check `.gitignore`
