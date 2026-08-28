# Manhattan Sidewalk Shade Index

**Question:** Which side of which Manhattan street should I walk on to stay in the shade on a summer day?

**Answer:** A reproducible analysis pipeline that ranks Manhattan sidewalk segments by tree-shade coverage over an 11-hour summer day (08:00–18:00).

**Live map:** [juanzotes.github.io/manhattan-shade-index/web/index.html](https://juanzotes.github.io/manhattan-shade-index/web/index.html)

## What this project does

1. Downloads street tree and sidewalk data from NYC Open Data.
2. Projects tree crowns as shadows for each hour of the day using solar geometry.
3. Computes a `shade_index` (0–1, hourly shade fraction integrated over the day) for each sidewalk segment.
4. Publishes an interactive web map with an hour slider, showing shade shifting across Manhattan as the sun moves.

## Why it matters (and what it doesn't)

**Tree shade only.** v1 ranks sidewalks by canopy contribution alone. In Manhattan, **building shadows dominate tree shadows**. A north–south avenue between tall towers is deeply shaded at 09:00 regardless of trees. This analysis answers: *"where does the urban forest do the work?"* — an interesting and honest question, but not *"where is it shadiest?"* See §2 of [CLAUDE.md](CLAUDE.md) for the caveat and the v2 plan.

## Quick start

### Prerequisites

- Conda (miniforge or mambaforge) with the shared `gis` environment used across this
  accelerator repo (see `modern-gis/SKILL.md` §10)
- ~2 GB disk for raw data
- Python 3.10 (via the `gis` env)

### Setup

```bash
# Activate the shared gis environment and add the one missing package
conda activate gis
conda install -n gis -c conda-forge pvlib

# Run the full pipeline (each stage is a notebook, executed headlessly)
make all
```

This will:
1. Resolve data sources (S0)
2. Ingest and clip to Manhattan (S1)
3. Build comparable analysis units from sidewalk polygons (S2)
4. Derive crown dimensions from tree diameter (S3)
5. Project shadows for each hour (S4)
6. Compute shade index per unit (S5)
7. Build vector tiles and deploy to web (S6)

Each stage is idempotent and produces its own QA summary. See [CLAUDE.md](CLAUDE.md) for detailed acceptance criteria and methodology.

## Outputs

- **GeoParquet**: `data/processed/shade_index_units.parquet` — analysis units with `shade_index`, `peak_heat_index`, and hourly shade fractions
- **GeoJSON**: `data/processed/shade_index_units.geojson` — web-ready summary
- **PMTiles**: `web/tiles/shade_index.pmtiles` — vector tiles for the map
- **Web map**: `web/index.html` — hour slider, clickable units, methodology panel
  - Deploy to GitHub Pages: `git push origin main` (see [web/README.md](web/README.md))

## Top 20 shadiest Manhattan sidewalks by peak-heat index (11:00–16:00)

From the 2025-07-15 reference day run (`data/processed/top20_shadiest.csv`). Note the
tree-only caveat above: this ranks *tree canopy* shade, not total shade.

| Rank | Street | Side | Peak Heat Index | Shade Hours |
|------|--------|------|---|---|
| 1 | West 81 Street | Left | 0.968 | 6.94 |
| 2 | West 81 Street | Left | 0.957 | 7.31 |
| 3 | East 13 Street | Left | 0.955 | 5.25 |
| 4 | East 97 Street | Right | 0.947 | 6.64 |
| 5 | East 57 Street | Left | 0.946 | 6.18 |
| 6 | East 57 Street | Left | 0.943 | 5.66 |
| 7 | Delancey Street | Right | 0.903 | 7.14 |
| 8 | East 85 Street | Right | 0.903 | 5.14 |
| 9 | West 77 Street | Right | 0.901 | 6.04 |
| 10 | 5 Avenue | Left | 0.901 | 4.69 |
| 11 | 5 Avenue | Left | 0.897 | 4.79 |
| 12 | Delancey Street | Right | 0.891 | 7.14 |
| 13 | East 71 Street | Left | 0.883 | 5.57 |
| 14 | West 73 Street | Right | 0.881 | 5.08 |
| 15 | East 91 Street | Left | 0.877 | 5.49 |
| 16 | East 78 Street | Left | 0.877 | 6.08 |
| 17 | East 97 Street | Right | 0.876 | 6.27 |
| 18 | West 89 Street | Right | 0.871 | 6.30 |
| 19 | West 88 Street | Right | 0.869 | 5.87 |
| 20 | East 13 Street | Left | 0.867 | 6.12 |

## Documentation

- **[CLAUDE.md](CLAUDE.md)** — Full project spec: stages, data sources, acceptance criteria, scope.
- **[modern-gis/SKILL.md](modern-gis/SKILL.md)** — Authoritative tech decisions (libraries, CRS, data formats).
- **[docs/METHODOLOGY.md](docs/METHODOLOGY.md)** — Every assumption: allometry, solar geometry, shadow model.
- **[docs/DECISIONS.md](docs/DECISIONS.md)** — Deviations from spec and SKILL.md, recorded during implementation.
- **[docs/VALIDATION.md](docs/VALIDATION.md)** — Spot-checks and validation results.

## Pipeline stages

Each stage is a standalone Python script runnable from the command line:

| Stage | Module | Input | Output | Accepts when |
|-------|--------|-------|--------|---|
| S0 | `src/s0_resolve_sources.ipynb` | config.yaml | `data/SOURCES.md` | URLs verified, columns confirmed |
| S1 | `src/s1_ingest.ipynb` | `data/SOURCES.md` + raw downloads | `data/interim/{trees,sidewalks,lion}.parquet` | Tree count plausible, all layers in EPSG:32618 |
| S2 | `src/s2_analysis_units.ipynb` | `data/interim/*.parquet` | `data/interim/analysis_units.parquet` | Units tile surface, ~1% area retained, every unit has street_name + side |
| S3 | `src/s3_crown_geometry.ipynb` | `data/interim/*.parquet` + allometry | `data/interim/units_with_crowns.parquet` | Crown radii 0.5–12 m, heights 2–30 m, fallback % < 20% |
| S4 | `src/s4_shadows.ipynb` | `data/interim/units_with_crowns.parquet` | `data/interim/shadows_*.parquet` | Shadows point away from sun, area peaks near noon |
| S5 | `src/s5_shade_index.ipynb` | `data/interim/shadows_*.parquet` | `data/processed/shade_index_units.parquet` | Indices ∈ [0,1], top streets plausible, 5-unit spot-check done |
| S6 | `src/s6_tiles.ipynb` | `data/processed/shade_index_units.parquet` | `web/tiles/shade_index.pmtiles` + map | Map loads <3s, slider works, tiles reasonable size |

## Not in scope for v1

- Building shadows (see [CLAUDE.md § 9](CLAUDE.md#9-explicitly-out-of-scope-for-v1))
- Canopy transmittance (all crowns opaque)
- LiDAR validation
- Pedestrian routing
- Seasonality / deciduous phenology
- Terrain (flat ground plane assumed)
- Tree data beyond 2015 census

## Project structure

```
.
├── CLAUDE.md                    # Project spec (detailed)
├── README.md                    # This file
├── config.yaml                  # Every tunable parameter
├── environment.yml              # Conda dependencies
├── Makefile                     # Pipeline orchestration
├── modern-gis/
│   └── SKILL.md                 # Authoritative tech guidance
├── data/
│   ├── SOURCES.md               # Resolved data endpoints (committed)
│   ├── raw/                     # Downloaded raw data (gitignored)
│   ├── interim/                 # Working files: GeoParquet (gitignored)
│   └── processed/               # Final outputs: GeoParquet, GeoJSON (gitignored)
├── src/
│   ├── s0_resolve_sources.ipynb
│   ├── s1_ingest.ipynb
│   ├── s2_analysis_units.ipynb
│   ├── s3_crown_geometry.ipynb
│   ├── s4_shadows.ipynb
│   ├── s5_shade_index.ipynb
│   └── s6_tiles.ipynb
├── notebooks/                   # Exploration only, not pipeline dependencies
├── docs/
│   ├── METHODOLOGY.md
│   ├── DECISIONS.md
│   └── VALIDATION.md
└── web/
    ├── index.html               # Interactive map (MapLibre)
    ├── README.md                # Deployment guide
    └── tiles/                   # PMTiles (gitignored)
```

## Style and reproducibility

- **One tool, one way**: Python + conda for environment, geopandas for geo, pvlib for solar, MapLibre for web.
- **No magic numbers**: Every parameter lives in `config.yaml`.
- **Deterministic**: Same inputs → byte-identical results. No randomness.
- **Staged validation**: Each stage prints a QA summary and stops if acceptance criteria fail.
- **Configuration-driven**: Changing the reference date to 21 September requires only a `config.yaml` edit, not code changes.

## License

MIT. See [LICENSE](LICENSE).

---

*Project: Manhattan Sidewalk Shade Index. Version: v1.0. Last updated: 2025.*
