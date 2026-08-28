# GETTING_STARTED.md — Project Setup and First Steps

## What has been created

A complete project skeleton for the **Manhattan Sidewalk Shade Index** has been initialized. This document guides you through the next steps.

### Project structure created

```
4.4-coding-agents/
├── CLAUDE.md                    ← Full project specification
├── README.md                    ← Project overview
├── GETTING_STARTED.md           ← This file
├── config.yaml                  ← All tunable parameters
├── environment.yml              ← Conda dependencies
├── Makefile                     ← Pipeline orchestration
├── LICENSE                      ← MIT license
├── .gitignore                   ← Version control exclusions
│
├── modern-gis/
│   └── SKILL.md                 ← Authoritative tech decisions
│
├── data/
│   └── SOURCES.md               ← Template for resolved data sources
│
├── src/
│   ├── s0_resolve_sources.ipynb    ← Stage 0 (partial implementation)
│   ├── s1_ingest.ipynb             ← Stage 1 (skeleton)
│   ├── s2_analysis_units.ipynb     ← Stage 2 (skeleton)
│   ├── s3_crown_geometry.ipynb     ← Stage 3 (skeleton)
│   ├── s4_shadows.ipynb            ← Stage 4 (skeleton)
│   ├── s5_shade_index.ipynb        ← Stage 5 (skeleton)
│   └── s6_tiles.ipynb              ← Stage 6 (skeleton)
│
├── docs/
│   ├── METHODOLOGY.md           ← Assumptions and math
│   ├── DECISIONS.md             ← Implementation choices log
│   └── VALIDATION.md            ← QA and spot-check results
│
├── web/
│   ├── index.html               ← MapLibre web map template
│   └── README.md                ← Deployment guide
│
└── notebooks/                   ← Exploration only (not pipeline)
```

### What's ready

✅ **S0 (Resolve sources)**: 
- Skeleton script with Socrata API integration
- Will verify NYC Open Data datasets before download

✅ **Configuration infrastructure**:
- `config.yaml` with all parameters
- `environment.yml` with conda dependencies
- Makefile for pipeline orchestration

✅ **Documentation framework**:
- Full methodology specification (with placeholders for allometry coefficients)
- Validation checklist (spot-checks, QA summaries)
- Decisions log (track deviations from spec)

✅ **Web map template**:
- Basic MapLibre GL JS structure
- Hour slider placeholder
- Feature info panel
- Legend and methodology caveat

### What needs implementation

⏳ **Stages 1–6**: Implement the pipeline scripts
⏳ **Data sources**: Download and verify NYC Open Data, DCP datasets
⏳ **Allometry table**: Replace placeholders with published coefficients
⏳ **Web map logic**: Integrate PMTiles, hour slider interactivity

---

## Next steps (Stage 0)

### 1. Set up the conda environment

This project uses the shared `gis` environment (see `modern-gis/SKILL.md` §10), not a
dedicated per-project one.

```bash
conda activate gis
conda install -n gis -c conda-forge pvlib   # only package missing from gis
```

### 2. Run Stage 0 (source resolution)

```bash
make s0
```

or

```bash
python src/_run_notebook.py src/s0_resolve_sources.ipynb
```

**What S0 does:**
- Queries NYC Open Data Socrata API by dataset title
- Verifies dataset IDs and column names
- Writes resolved URLs to `data/SOURCES.md`
- Stops with an error if any dataset is not found or columns don't match

**Accept when:**
- All 5 sources resolve successfully
- `data/SOURCES.md` lists verified URLs and column names
- No errors reported

### 3. Inspect `data/SOURCES.md`

Review the resolved endpoints. Example (partial):

```markdown
### street_trees_primary
**Status:** success
**Dataset ID:** ib47-dygz
**URL:** https://data.cityofnewyork.us/d/ib47-dygz
**Columns:** tree_id, status, tree_dbh, spc_latin, lat, lon
```

---

## Implementation workflow (one stage at a time)

Once S0 succeeds, proceed stage by stage:

### S1 — Ingest and clip (data/raw/ → data/interim/)

Edit `src/s1_ingest.ipynb`:
1. Parse `data/SOURCES.md` for resolved URLs
2. Download each dataset to `data/raw/`
3. Load as GeoDataFrame
4. Filter trees: `status='Alive'`, `tree_dbh > 0`
5. Convert DBH inches → cm
6. Load Manhattan boundary (`borocode = 1`)
7. Clip and reproject all to EPSG:32618
8. Write to `data/interim/{trees,sidewalks,lion}.parquet`
9. Print QA summary

**Acceptance criteria:** See [CLAUDE.md § 5](CLAUDE.md#s1--ingest-and-clip)

### S2–S6 — Follow the same pattern

Each stage:
1. Load output from previous stage
2. Process per the spec
3. Write to data directory (interim or processed)
4. Print QA summary
5. Pass acceptance criteria before moving to next stage

---

## Key files to keep in mind

| File | Purpose |
|------|---------|
| [CLAUDE.md](CLAUDE.md) | **Authoritative spec** — read before writing code |
| [modern-gis/SKILL.md](modern-gis/SKILL.md) | **Tech decisions** — Python, geopandas, pvlib, etc. |
| [config.yaml](config.yaml) | **Runtime parameters** — no magic numbers in code |
| [docs/METHODOLOGY.md](docs/METHODOLOGY.md) | **Assumptions** — update as you implement |
| [docs/DECISIONS.md](docs/DECISIONS.md) | **Log deviations** — record any changes to the spec |
| [docs/VALIDATION.md](docs/VALIDATION.md) | **QA results** — fill in acceptance checks |

---

## Testing a single stage

You don't need to run all stages in order. To test a single stage:

```bash
python src/_run_notebook.py src/s2_analysis_units.ipynb
```

Each script is standalone and idempotent (running it again produces the same output).

---

## Troubleshooting

### S0 fails to resolve a dataset

1. Go to [NYC Open Data](https://data.cityofnewyork.us) directly
2. Search for the dataset by title (e.g. "2015 Street Tree Census")
3. Find the dataset ID in the URL (e.g. `ib47-dygz`)
4. Check the data dictionary for column names
5. If S0 can't find it via API, manually add to `data/SOURCES.md` and update `config.yaml`
6. Document the fallback in `docs/DECISIONS.md`

### Import errors

Make sure the conda environment is activated:

```bash
conda activate gis
python src/_run_notebook.py src/s1_ingest.ipynb
```

### GeoParquet not readable

Ensure `pyarrow` is installed (should be via `environment.yml`):

```bash
conda install pyarrow
```

---

## Commits and version control

Before your first commit:

```bash
git init
git add CLAUDE.md README.md config.yaml environment.yml Makefile modern-gis/ src/ docs/ web/ .gitignore LICENSE
git commit -m "s0: project initialization and stage 0 skeleton"
```

**Never commit:**
- `data/raw/` (downloads, can be >1 GB)
- `data/interim/` (intermediate GeoParquet)
- `data/processed/` (final output)
- `.ipynb_checkpoints/`, `__pycache__/`

**Always commit:**
- `data/SOURCES.md` (tells others where to get data)
- All `src/`, `docs/`, `modern-gis/`, `web/`

---

## Questions?

See [CLAUDE.md](CLAUDE.md) for detailed specs, [modern-gis/SKILL.md](modern-gis/SKILL.md) for tech choices, and [docs/](docs/) for methodology notes.

Good luck! 🌳☀️
