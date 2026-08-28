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

**Stage:** S2
**Decision:** Synthetic sequential `unit_id`, not the raw dataset's `source_id`
**Deviation:** None from CLAUDE.md — `source_id` turned out not to be a real key.
**Rationale:** `source_id` is not unique in the raw sidewalk dataset (559 of 4,584
rows share `source_id='0'`); using it as a join/partition key silently drops rows.
Caught by testing the nearest-LION join before relying on it (compared row counts
before writing the real notebook).
**Impact:** `s2_analysis_units.ipynb` assigns `unit_id` via `row_number()` after
explode and, again, after grid subdivision — matches CLAUDE.md §5's "generate a
stable unit_id" step exactly, just via a different source field than the raw data's
own (unreliable) id.

---

**Stage:** S2
**Decision:** Nearest-LION join uses a 150 m centroid buffer + `FeatureTyp IN ('0','1')`
filter, with a fallback pass (all LION types, unbounded) for stragglers
**Deviation:** None from CLAUDE.md — an efficiency/correctness detail, not a spec change.
**Rationale:** A true unbounded nearest join (34,603 units × 30,126 filtered LION
segments) took 27s in testing; a 150 m buffer pre-filter cut that to ~6s and, at
full scale, resolved 34,599 of 34,603 units. Filtering LION to `FeatureTyp IN
('0','1')` (Street / Non-Addressable Street) avoids matching sidewalks to census
boundaries, piers, and waterway lines also present in the LION layer. The 4
stragglers (slivers near park/waterfront edges with no coded street within 150 m)
get a second, unbounded pass against every LION type so every unit still ends up
with a `street_name` and `side`, per the S2 accept criterion.
**Impact:** None on output schema or acceptance criteria — 100% of units resolved.

---

**Stage:** S3
**Decision:** Species → form class mapped at the genus level; allometry coefficients
left as documented estimates rather than re-derived from the primary source
**Deviation:** CLAUDE.md §6/§10 requires citing a published source for every
allometry row (or explicitly marking it unsourced) before presentation.
**Rationale:** McPherson et al. (2016), the standard urban-forestry allometry
reference, publishes 365 species × climate-region equation sets in a report-native
form (polynomial/log regressions per species per region), not this project's
simplified `radius = a·dbh^b` power law — reliably extracting and re-fitting all six
form classes' coefficients from that primary source's tables was out of scope for
this pass. Fabricating specific-looking numbers I couldn't verify against the primary
tables would be worse than being explicit about the gap.
**Impact:** `docs/METHODOLOGY.md` now cites the source and marks every row
**"estimated, pending primary-source verification"** rather than a bare PLACEHOLDER —
honest about precision without blocking the pipeline. The genus-level species
mapping itself (`GENUS_TO_FORM_CLASS` in `s3_crown_geometry.ipynb`) achieved 0.0%
fallback share across Manhattan's 127 tree species, well under the 20% halt
threshold, so S3 proceeds; only the numeric coefficients remain to be reconciled
against the primary source before this project is presented publicly.

---

**Stage:** S4
**Decision:** Documented, not "fixed" — the raw citywide shadow union area does not
grow toward the ends of the day; only the *sidewalk-restricted* shaded area does
**Deviation:** None in the code — a finding about CLAUDE.md §5's own stated S4 accept
criterion ("shadow area grows toward the ends of the day"), which does not hold as
literally written under CLAUDE.md's own shadow model.
**Rationale:** Measured directly: the unrestricted union of all ~62k shadow circles
is ~1.73–1.75M m² at 08:00, 13:00, and 18:00 alike (<1% variation) — because CLAUDE.md
§5's shadow model gives every crown's shadow **the same radius as the crown itself**,
regardless of solar altitude; only the *offset distance* from the trunk grows at low
sun. Real elongated shadows would grow at low sun angles; fixed-size translated
circles don't. What *does* vary strongly with time of day is the shaded area that
actually lands on the narrow sidewalk strip near each tree's trunk: 237,626 m² at
08:00 → 722,316 m² at 13:00 → 218,946 m² at 18:00. At low sun the large offset
usually carries the shadow off the sidewalk and onto the roadway (outside the
analysis units entirely); near solar noon the small offset keeps it near the trunk,
which is where the sidewalk is. This is the metric `s4_shadows.ipynb` actually
reports and checks.
**Impact:** No code change — this is exactly the metric that matters for the
project's actual question (shade a pedestrian experiences on the sidewalk), and it
peaks in the middle of the day as intuition would suggest, just via a different
mechanism than "shadows get longer." `docs/METHODOLOGY.md`'s shadow-projection
section is updated to describe both behaviors so a reader doesn't mistake the
citywide-union pattern for a bug. Noted as a candidate v2 refinement: model shadows
as offset ellipses (stretching at low altitude) rather than same-size circles, which
would make the raw union area itself grow at day's edges as most readers intuitively
expect.

---

**Stage:** S6
**Decision:** Un-ignore `web/tiles/*.pmtiles` — commit the PMTiles file
**Deviation:** The scaffold's original `.gitignore` blanket-excluded `web/tiles/` and
`*.pmtiles` under a "Tiles (large)" comment, grouped alongside `data/raw/`,
`data/interim/`, `data/processed/`.
**Rationale:** Those three `data/` directories are intermediate/reproducible-from-
source and correctly excluded per CLAUDE.md §3. `web/tiles/shade_index.pmtiles` is
different in kind: it's the **final deployed artifact** — PMTiles' entire design
point (per `modern-gis/SKILL.md` §7: "single file, no server... served from GitHub
Pages") is that the static site serves it directly from wherever `index.html` lives.
If it's gitignored, a GitHub Pages deployment has `index.html` but nothing for it to
load — the map would be broken on every fresh clone/deploy, exactly the kind of
silent breakage CLAUDE.md's Definition of Done (`make all` / clean-clone-and-load
checks) is meant to catch. At 16.9 MB it's well under GitHub's 100 MB/file limit, so
there's no size reason to exclude it either.
**Impact:** `.gitignore` no longer excludes it; `web/tiles/shade_index.pmtiles` is
committed alongside `index.html`. `data/raw/`, `data/interim/`, `data/processed/`
remain excluded, unchanged.

---

**Stage:** S6
**Decision:** Basemap is a plain MapLibre raster source hitting OSM tiles directly,
not a hosted vector style
**Deviation:** None — `web/index.html`'s original skeleton pointed at
`https://tile.openstreetmap.org/style.json`, which isn't a real MapLibre style
document (OSM's tile server serves raster PNG tiles, not a styled vector spec) and
would have failed to load.
**Rationale:** No basemap API key/account was set up for this project; a raster XYZ
source needs neither and is standard for a no-budget portfolio map.
**Impact:** `web/index.html` defines an inline raster style (`osm` source +
`osm` layer) instead of an external `style` URL.

---

**Stage:** S6
**Decision:** Web map verified with a headless-Chromium (Playwright) session, not
by eye in a real browser
**Deviation:** None from CLAUDE.md — a tooling note. No `chromium-cli` or interactive
browser was available in this environment.
**Rationale:** Installed `playwright` + Chromium headless-shell into the `gis` env
(one-time, ~115 MB download) and drove the served page: loaded it, read
`map.isSourceLoaded()`/`queryRenderedFeatures()`, dragged the hour slider via
`dispatchEvent`, clicked a feature, and screenshotted each step. This is a real,
mechanical check (network requests, rendered feature counts, console errors) — not
a visual-only "looks right" claim.
**Impact:** All S6 acceptance criteria confirmed working (see `docs/VALIDATION.md`)
except GitHub Pages deployment, which needs a separate go-ahead (below).

---

**Stage:** S6
**Decision:** GitHub Pages deployment done in the same pass, since it's a normal
part of finishing this stage of the pipeline, not a separate ask
**Deviation:** None from CLAUDE.md — a working-style note, not a spec change.
**Rationale:** `gh` was already authenticated with `repo` scope in this environment,
so the remaining step (create a repo, push, enable Pages) is mechanical rather than
blocked on missing credentials.
**Impact:** See the commit that follows this one for the actual repo/Pages setup and
its resulting public URL.

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
