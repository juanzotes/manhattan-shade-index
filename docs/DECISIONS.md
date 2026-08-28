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
invoke a headless notebook runner instead of `python src/sN_*.py` — automation and
rerun-from-raw behaviour is unchanged, only the file format and invocation command
differ. (See the next entry for exactly which runner and why.)

---

**Stage:** Setup
**Decision:** Headless notebook execution uses `src/_run_notebook.py` (nbclient
directly), not the `jupyter nbconvert` CLI
**Deviation:** None from CLAUDE.md/SKILL.md — this is a local tooling workaround, not
a methodology or tech-stack choice.
**Rationale:** `jupyter nbconvert --execute` unconditionally imports nbconvert's
`ServePostProcessor`, which imports `tornado`, which calls
`ssl.create_default_context().load_default_certs()` at import time — and on this
machine that trips `ssl.SSLError: [ASN1: NOT_ENOUGH_DATA]` reading a malformed entry
in the Windows certificate store, unrelated to anything this project does. `nbclient`
(already a `gis` dependency) executes and saves a notebook in place without that
import chain.
**Impact:** `Makefile` targets and this project's docs call
`python src/_run_notebook.py src/sN_*.ipynb` rather than
`jupyter nbconvert --to notebook --execute --inplace`. Behaviour is identical
(run every cell, save the result back to the same file); only the invocation differs.

---

**Stage:** S0
**Decision:** Resolve all five CLAUDE.md §3 sources through the Socrata catalog API,
including sidewalks and LION
**Deviation:** CLAUDE.md §3 states sidewalks and LION "ship via DCP 'Bytes of the Big
Apple', not Socrata." Live investigation found both *are* also registered on NYC Open
Data (Socrata) — this is the §11 case of "a data reality contradicts this file."
**Rationale:** The DCP nyc.gov distribution pages (`dwn-lion.page` etc.) turned out to
be JS-rendered shells — a plain HTTP fetch returns ~7.5 KB of template markup with no
dataset links in it, so the DCP-page resolution path in the spec cannot work as
described regardless of which exact URL is used. The Socrata catalog API is directly
queryable and returns real datasets for both.
**Impact:** S0 resolves all five sources with one function, handling three asset
shapes Socrata returns: **tabular** (query directly), **map** (a visualization
wrapper — "Sidewalk"'s top catalog hit — whose `modifyingViewUid` points at the real
backing tabular dataset, `52n9-sdep`), and **blobby** (a downloadable file; LION
resolves to `2v4z-66xt`, a zipped shapefile with no queryable columns). S1 must
therefore download-and-unzip LION rather than query it as GeoJSON, and convert it to
GeoParquet immediately per `modern-gis/SKILL.md` §5 ("Shapefile: Legacy ingestion
only").

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

**Stage:** S1
**Decision:** Build tree point geometry from `latitude`/`longitude` columns instead of
using the Socrata `.geojson` export's geometry
**Deviation:** None from CLAUDE.md/SKILL.md — a live-data quirk, not a methodology
choice.
**Rationale:** The 2015 Street Tree Census dataset's `.geojson` export returns
`"geometry": null` on every feature — `latitude`/`longitude` are plain number columns
on this dataset, not a Socrata Point-typed column, so the automatic GeoJSON geometry
serialization has nothing to attach. Downloading `.json` instead and building points
via `geopandas.points_from_xy(longitude, latitude)` (EPSG:4326) works correctly.
**Impact:** `s1_ingest.ipynb` downloads trees as `.json`, not `.geojson`; every other
tabular source (sidewalks, borough boundary) uses `.geojson` normally since their
geometry columns serialize correctly.

---

**Stage:** S1
**Decision:** LION is an Esri File Geodatabase inside the zip, not a shapefile
**Deviation:** CLAUDE.md §4 lists LION under "Shapefile" expectations implicitly (via
the general shapefile-ingestion convention in `modern-gis/SKILL.md` §5); the actual
blob is a `.gdb` directory (layers: `lion`, `node`, `node_stname`, `altnames`), native
CRS EPSG:2263.
**Rationale:** Discovered by extracting the real downloaded blob — not something to
guess in advance.
**Impact:** `s1_ingest.ipynb` reads the `lion` layer directly via
`geopandas.read_file(gdb_path, layer="lion")` (fiona's OpenFileGDB driver) rather than
globbing for `.shp`. It's converted to GeoParquet immediately after reprojection, so
downstream stages never touch the `.gdb` — satisfies SKILL.md §5's "never past
ingestion" rule for legacy formats. `Street` is the name column; `LBoro`/`RBoro`
(left/right-side borough) will help S2's side-of-street assignment.

---

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
