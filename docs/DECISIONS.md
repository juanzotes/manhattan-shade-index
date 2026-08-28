# DECISIONS.md — Manhattan Sidewalk Shade Index

*Record of deviations from CLAUDE.md and SKILL.md. Updated as implementation proceeds.*

## Decisions recorded

**Stage:** Setup
**Decision:** Pipeline stages are Jupyter notebooks (`src/sN_*.ipynb`), not `.py` scripts
**Deviation:** CLAUDE.md §4/§8 states every stage is a standalone script and that
`notebooks/` is exploration-only, never a pipeline dependency.
**Rationale:** User-requested for readability — markdown cells carry the methodology
narrative alongside the code, rather than splitting it into docstrings/comments.
**Impact:** Each notebook is still standalone and idempotent. `make sN` / `make all`
invoke `jupyter nbconvert --to notebook --execute --inplace src/sN_*.ipynb` instead of
`python src/sN_*.py` — automation and rerun-from-raw behaviour is unchanged, only the
file format and invocation command differ.

---

**Stage:** Setup
**Decision:** Use the shared `gis` conda environment instead of a dedicated
`manhattan-shade-index` environment
**Deviation:** The scaffold's original `environment.yml` created a new per-project
conda environment. `modern-gis/SKILL.md` §10 (the real, authoritative skill file —
see next entry) says to use the shared `gis` environment for all GIS/data processing
on Windows.
**Rationale:** `gis` already has geopandas, pandas, shapely, pyarrow, rasterio, rtree,
fiona, gdal, duckdb, jupyterlab, nbconvert, nbclient, requests, pyyaml, matplotlib —
everything this project needs except `pvlib`. Avoids a second environment to maintain.
**Impact:** `environment.yml` now documents the relevant subset of `gis`'s packages
for reproducibility rather than defining an installable environment of its own. Only
`pvlib` needs installing into `gis` before Stage S4.

---

**Stage:** Setup
**Decision:** Replaced `modern-gis/SKILL.md` with the accelerator's real, authoritative
`references/SKILL.md`
**Deviation:** The file that shipped in the original scaffold at this path was a
shorter, independently-written stand-in — not a copy of the repo's actual skill file.
It omitted the core SQL-vs-Python rule, DuckDB/PostGIS guidance, and gave an incorrect
tippecanoe install path (conda instead of WSL/pipx).
**Rationale:** CLAUDE.md §0 states `modern-gis/SKILL.md` is authoritative and silently
overrides CLAUDE.md on tech choices; it must actually be the real one.
**Impact:** See the next decision (SQL vs Python split) — this is a direct consequence
of restoring the real skill file's core rule.

---

**Stage:** Setup
**Decision:** Data-logic steps (joins, aggregations, overlays, area calcs) run in
DuckDB (spatial extension); Python/geopandas handles orchestration, I/O, and geometry
construction (crown-offset trig, solar position via `pvlib`)
**Deviation:** CLAUDE.md §5 describes S2/S4/S5 in Python/geopandas pseudocode
(`sjoin`, buffer-and-union, groupby aggregation).
**Rationale:** `modern-gis/SKILL.md`'s core rule: "do data logic in SQL, orchestrate
in Python... never do in Python what SQL can do in one query." CLAUDE.md §0
pre-authorizes substituting the skill file's sanctioned tool when it names one
CLAUDE.md doesn't.
**Impact:** S2's nearest-LION join + side assignment, and S4/S5's shadow-union ∩
analysis-unit overlay + aggregation, are SQL queries against the GeoParquet outputs
via DuckDB, not `geopandas.sjoin`/`groupby` calls. Output schemas and acceptance
criteria are unaffected — same GeoParquet layers with the same required columns.

This file tracks all tech and methodology choices that diverge from the specification or that required trade-offs. As each stage completes, note:

1. **Stage:** e.g. "S1"
2. **Decision:** Brief title
3. **Deviation:** What this changes in the spec
4. **Rationale:** Why (performance, data quality, availability, etc.)
5. **Impact:** What downstream stages must account for

---

## Example entry (template)

**Stage:** S4  
**Decision:** Rasterise shadows instead of vector overlay  
**Deviation:** CLAUDE.md §5 calls for vectorised buffer + spatial index overlay. Switched to rasterisation.  
**Rationale:** Vector overlay exceeded 10 min per timestep. Rasterisation at 1 m grid reduced to 2 min.  
**Impact:** S5 receives raster-to-vector conversion output; slight boundary smoothing expected.

---

## Process

Before approving a decision:
1. Document in this file with date and stage
2. Update any affected docstrings in `src/`
3. If it affects output, record validation in VALIDATION.md
4. Never suppress the decision silently

*Last updated: [Project start]*
