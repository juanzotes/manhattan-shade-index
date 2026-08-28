# CLAUDE.md — Manhattan Sidewalk Shade Index

## 0. Read this first

Before making **any** technology or library decision, read `modern-gis/SKILL.md` in this
repo. That file is authoritative. Where it conflicts with anything suggested below, the
skill file wins — silently follow it, do not ask.

If a stage below names a tool that the skill file does not sanction, substitute the
sanctioned equivalent and note the substitution in `docs/DECISIONS.md`.

---

## 1. Goal

Rank Manhattan sidewalk segments by how much **tree shade** they receive over a summer
day, so a pedestrian can answer: *which side of which street should I walk on to stay in
the shade?*

Deliverables:
1. A reproducible pipeline (raw data → analysis-ready → shade index).
2. A sidewalk-segment layer carrying a `shade_index` and per-hour shade fractions.
3. A web map with an hour slider showing shade shifting across the day.

This is a portfolio project. **Methodological honesty ranks above impressive numbers.**
Every assumption goes in `docs/METHODOLOGY.md` with its source or its status as a
placeholder.

---

## 2. Scope — locked, do not expand without asking

| Dimension | Decision |
|---|---|
| Geography | Manhattan only (`borocode = 1`). Clip everything at ingestion. |
| Shade source | **Street trees only** in v1. Buildings excluded — see caveat below. |
| Date | One reference day, summer: `2025-07-15`. Config-driven. |
| Time window | 08:00–18:00 local (America/New_York), hourly → 11 timesteps. |
| Terrain | Flat. Ground plane at z=0. Manhattan is flat enough; document it. |
| Output CRS | EPSG:4326 for web; EPSG:32618 (UTM 18N, metres) for all analysis. |

### The caveat you must not bury

In Manhattan, **building shadows dominate tree shadows**. A north–south avenue between
tall buildings is deeply shaded at 09:00 regardless of trees. A v1 "shadiest sidewalk"
ranking based on trees alone is therefore a *tree canopy shade* ranking, not a *total
shade* ranking.

State this prominently in the README and on the map. Do not quietly present tree-only
results as answering "where is it shadiest." Framing it as **"where does the urban forest
do the work"** is both accurate and more interesting. Building shadows are the headline v2
extension (§9).

---

## 3. Data sources

Do **not** hardcode dataset IDs from memory. At Stage 0, resolve each dataset against the
live catalog and write the resolved endpoints into `data/SOURCES.md` with the access date.

| Layer | Source | Notes |
|---|---|---|
| Street trees | NYC Open Data — *2015 Street Tree Census (Tree Data)* | Primary. ~65k Manhattan records. Stable, documented, has `tree_dbh` + `spc_latin`. |
| Street trees (alt) | NYC Open Data — *Forestry Tree Points* | Live NYC Parks feed. Fresher but a moving target. Use only if the 2015 census proves unusable; document the switch. |
| Sidewalks | NYC Planimetric Database — *Sidewalk* (polygons) | The analysis surface. Polygons, not lines. |
| Street centerlines | NYC DCP — *LION* | Used to name segments and assign side-of-street. Ships via DCP "Bytes of the Big Apple", not Socrata. |
| Borough boundary | NYC Open Data — *Borough Boundaries* | Clip mask. |

Resolution method for Socrata layers: query the catalog API for the dataset by title,
confirm the returned ID and column names against the data dictionary, then pin the ID in
`config.yaml`. If a resolution fails, stop and report — do not guess an ID.

Downloads go to `data/raw/`. **`data/` is gitignored except for `SOURCES.md`.**

---

## 4. Repository layout

```
.
├── CLAUDE.md
├── README.md
├── config.yaml                  # every tunable parameter lives here
├── environment.yml
├── modern-gis/SKILL.md          # authoritative tech guidance
├── data/
│   ├── SOURCES.md               # resolved endpoints + access dates (committed)
│   ├── raw/                     # gitignored
│   ├── interim/                 # gitignored
│   └── processed/               # gitignored
├── src/
│   ├── s0_resolve_sources.py
│   ├── s1_ingest.py
│   ├── s2_analysis_units.py
│   ├── s3_crown_geometry.py
│   ├── s4_shadows.py
│   ├── s5_shade_index.py
│   └── s6_tiles.py
├── notebooks/                   # exploration only; never the pipeline
├── docs/
│   ├── METHODOLOGY.md
│   ├── DECISIONS.md
│   └── VALIDATION.md
├── web/                         # MapLibre app, deployed to GitHub Pages
└── Makefile                     # `make all` reruns everything from raw
```

Rule: **notebooks explore, `src/` decides.** Nothing in `notebooks/` is a pipeline
dependency. Every stage is a script runnable standalone and idempotent.

---

## 5. Pipeline stages

Each stage reads from the previous stage's output directory and writes GeoParquet. Do not
proceed to the next stage until the acceptance criteria pass. After each stage, print a
short QA summary (row counts, CRS, bounds, null counts) to stdout.

### S0 — Resolve sources
Resolve every dataset endpoint, verify column names against the published data dictionary,
write `data/SOURCES.md`.

**Accept when:** every layer in §3 has a pinned, tested URL and a confirmed column list.

### S1 — Ingest and clip
Download raw. Clip all layers to the Manhattan boundary. Reproject to EPSG:32618. Write
`data/interim/{trees,sidewalks,lion}.parquet`.

Tree filtering:
- Keep `status = 'Alive'` only. Drop dead trees and stumps — they cast no summer shade.
- Drop `tree_dbh <= 0` and null geometry.
- Convert `tree_dbh` from **inches** to cm. The source field is inches; getting this wrong
  silently inflates every crown by 2.5×.

**Accept when:** Manhattan tree count is in a plausible range (order 10⁴–10⁵), sidewalk
polygons have positive area, all layers share EPSG:32618, bounds overlap.

### S2 — Build analysis units
Sidewalk polygons ship as large, irregular multipart features. Convert them into
comparable analysis units:

1. Explode multipart → single-part.
2. Compute area distribution. **Decision gate:** if the median unit area exceeds the
   `max_unit_area_m2` threshold in config, subdivide the oversized polygons by intersecting
   with a regular grid (`grid_size_m`, default 50 m) so units are size-comparable.
3. Assign each unit to its nearest LION centerline segment → carry `street_name` and a
   `side` label (derived from which side of the centerline the unit's centroid falls on,
   using the centerline bearing and a cross-product sign test).
4. Assign a stable `unit_id`.

**Accept when:** units tile the sidewalk surface without overlap, total unit area ≈ total
input sidewalk area (within 1%), every unit has a `street_name` and a `side`.

### S3 — Crown geometry
For each tree, derive from DBH:
- `crown_radius_m`
- `tree_height_m`
- `crown_centre_height_m` — the vertical centre of the crown volume, i.e. the height whose
  shadow offset represents the crown. Use `crown_base_height + crown_radius`.

Use the species-group allometry in §6. Join `spc_latin` to a form class; fall back to a
generic class for unmatched or null species and **count the fallbacks** — report the share
in the QA summary. If fallback share exceeds 20%, stop and expand the lookup table.

**Accept when:** crown radii and heights are within sane bounds (radius 0.5–12 m, height
2–30 m), no nulls, fallback share reported.

### S4 — Shadow projection
For each timestep:
1. Compute solar azimuth and altitude for the Manhattan centroid using a library
   implementation of the NOAA/SPA algorithm. One position for all of Manhattan is fine at
   this scale — document the simplification.
2. Skip timesteps where altitude ≤ `min_altitude_deg` (default 5°); grazing-sun shadows
   are enormous and meaningless.
3. Project each crown: model the crown as a sphere of radius `crown_radius_m` centred at
   `crown_centre_height_m`. Its shadow is a circle of the **same radius**, with its centre
   offset from the trunk by
   `d = crown_centre_height_m / tan(altitude)` in the direction `azimuth + 180°`.
4. Build shadow polygons vectorised (buffer the offset points), then union per timestep.
5. Intersect the timestep shadow union with the analysis units.

Performance note: ~65k trees × 11 timesteps ≈ 700k circles. Use a vectorised buffer plus a
spatial index for the overlay; do not loop per tree in Python. If the vector overlay is too
slow, the sanctioned fallback is to rasterise sidewalks and shadows at 1–2 m and do the
overlay in array space — record the switch in `DECISIONS.md`.

**Accept when:** shadows fall *away* from the sun (spot-check: morning shadows point west,
afternoon east), shadow area grows toward the ends of the day, no shadow union is empty at
midday.

### S5 — Shade index
Per unit, per timestep:
```
shade_fraction_t = shaded_area_t / unit_area
```
Then:
```
shade_hours       = Σ_t (shade_fraction_t × Δt_hours)
shade_index       = shade_hours / window_length_hours          # 0–1
peak_heat_index   = mean(shade_fraction_t) for t in 11:00–16:00 # 0–1
```

`shade_index` is the headline metric. `peak_heat_index` is the one that actually matters
for a walker — surface it too, and rank on it in the "best sidewalks" table.

Clip `shade_fraction_t` at 1.0 (overlapping crowns must not double-count — this is why S4
unions before intersecting).

**Accept when:** all indices ∈ [0, 1]; the top-ranked streets are plausible on inspection
(tree-lined side streets and avenue medians should beat bare cross-streets); a spot-check
of 5 units against aerial imagery is written up in `docs/VALIDATION.md`.

### S6 — Tiles and web map
Write the unit layer with `shade_index`, `peak_heat_index`, and the 11 hourly fractions to
GeoJSON, build vector tiles, and serve as PMTiles.

Web map requirements:
- Sidewalk units coloured by `shade_index`, sequential ramp, legend with real units.
- Hour slider (08:00–18:00) recolouring by `shade_fraction_t`.
- Click a unit → street name, side, shade hours, tree count contributing.
- A visible methodology/caveat panel carrying the §2 building-shadow caveat.
- Deploy to GitHub Pages.

**Local dev:** PMTiles requires HTTP range requests. Serve with a range-capable server —
the standard Python `http.server` module will **not** work and will fail in confusing ways.

**Accept when:** the map loads from a clean clone following README steps only, the slider
visibly rotates the shade pattern east→west across the day, and tile size is reasonable.

---

## 6. Methodology specification

### Allometry

Crown radius and height from DBH, by species form class:

```
crown_radius_m = a_r * (dbh_cm ** b_r)
tree_height_m  = a_h * (dbh_cm ** b_h)
crown_base_height_m = base_ratio * tree_height_m
```

Starting coefficients — **PLACEHOLDERS**. Replace with values sourced from published urban
tree growth equations (e.g. the McPherson et al. urban tree growth/allometry work, or
i-Tree species records) before the project is presented anywhere. Record the source per row
in `docs/METHODOLOGY.md` and mark any row still unsourced.

| Form class | Representative species | a_r | b_r | a_h | b_h | base_ratio |
|---|---|---|---|---|---|---|
| broad_spreading | *Platanus × acerifolia*, *Quercus palustris*, *Ulmus americana*, *Acer platanoides* | 0.50 | 0.62 | 1.90 | 0.50 | 0.40 |
| open_fine | *Gleditsia triacanthos* | 0.48 | 0.60 | 1.85 | 0.50 | 0.45 |
| medium_dense | *Tilia cordata*, *Zelkova serrata*, *Styphnolobium japonicum* | 0.45 | 0.60 | 1.80 | 0.50 | 0.40 |
| narrow_upright | *Ginkgo biloba* | 0.32 | 0.58 | 2.10 | 0.50 | 0.45 |
| small_ornamental | *Pyrus calleryana*, *Prunus* spp., *Malus* spp. | 0.40 | 0.55 | 1.50 | 0.48 | 0.35 |
| generic (fallback) | unmatched / null | 0.45 | 0.60 | 1.80 | 0.50 | 0.40 |

Cap `crown_radius_m` at 12 m and `tree_height_m` at 30 m to absorb DBH outliers.

### Crown opacity

v1 treats crowns as **opaque**. Real canopies transmit light; *Gleditsia* in particular is
notably open. Add a per-class `opacity` column to the table now, set to 1.0 everywhere, so
the v2 refinement is a config change and not a rewrite. Note the assumption in the README.

### Solar geometry

Solar position from a library implementation of NOAA/SPA. Timezone-aware timestamps in
America/New_York; never naive datetimes. Log the computed azimuth/altitude for each
timestep to the QA output so the shadow directions can be checked by eye.

Shadow offset derivation, for the record:
> A point at height *h* casts its shadow at horizontal distance *h / tan(α)* from its base,
> in the direction opposite the sun's azimuth, where α is solar altitude. Because a sphere's
> shadow under (effectively) parallel light is a circle of the same radius, the crown's
> shadow is the crown circle translated by that offset.

Document this in `docs/METHODOLOGY.md` with a small diagram.

---

## 7. Configuration

Every number above lives in `config.yaml`. No magic numbers in `src/`. Minimum contents:
dataset IDs, analysis CRS, reference date, time window and step, `min_altitude_deg`,
`grid_size_m`, `max_unit_area_m2`, radius/height caps, allometry table path, peak-heat
window, output paths.

Changing the reference date to a shoulder-season day (e.g. 21 September) and rerunning must
require **no code edits**. Treat that as a test.

---

## 8. Conventions

- Python, conda environment pinned in `environment.yml`.
- Intermediate and final data as **GeoParquet**. No shapefiles past ingestion.
- All analysis in EPSG:32618. Reproject once, at S1. Assert the CRS at the top of every
  stage; a silent CRS mismatch is the most likely way this project produces confident
  nonsense.
- Areas in m², distances in m, DBH in cm internally (inches only in raw).
- Deterministic outputs: same inputs → byte-identical results. No random sampling in the
  pipeline.
- `make all` rebuilds everything from `data/raw/`. Keep it working.
- Commit messages reference the stage: `s4: vectorise shadow buffer`.
- **Never commit data.** Check `.gitignore` before the first commit, not after.

---

## 9. Explicitly out of scope for v1

Listed so they read as deliberate choices, not oversights. Put this list in the README.

1. **Building shadows.** The big one. v2: join NYC Building Footprints (`heightroof`),
   project footprint shadows with the same solar geometry, union with tree shadows, and
   report tree shade both alone and as a marginal contribution on top of buildings.
2. **Canopy transmittance.** Crowns are opaque in v1 (§6).
3. **LiDAR validation.** NYC has a derived canopy height model. Comparing allometric crown
   estimates against it would be the strongest validation available — a good v2 section in
   `docs/VALIDATION.md`.
4. **Routing.** Shade-optimal pedestrian routing over the network. Natural v3.
5. **Seasonality.** Leaf-on only; no deciduous phenology.
6. **Terrain.** Flat ground plane.
7. **Tree data currency.** The 2015 census is a decade old; trees have grown, died, and been
   planted. Quantify the exposure by comparing Manhattan counts against the live Forestry
   feed and state it.

---

## 10. Definition of done

- [ ] `make all` runs clean from a fresh clone + raw download, no manual steps.
- [ ] Every stage prints a QA summary and passes its acceptance criteria.
- [ ] `docs/METHODOLOGY.md` documents every assumption; no allometry row is still marked
      PLACEHOLDER.
- [ ] `docs/VALIDATION.md` contains the 5-unit visual spot-check and the direction check.
- [ ] `docs/DECISIONS.md` records every deviation from this file and from `SKILL.md`.
- [ ] Web map deployed to GitHub Pages, loads under 3 s, slider works.
- [ ] README states the goal, the method in one paragraph, the building-shadow caveat, and
      the out-of-scope list.
- [ ] A ranked table of the top 20 shadiest Manhattan sidewalk segments by
      `peak_heat_index`, with street name and side.

---

## 11. Working style for this repo

- Work stage by stage. Finish and validate a stage before starting the next.
- When an acceptance criterion fails, **stop and report** — do not loosen the criterion to
  get past it.
- When a data reality contradicts this file (a column is missing, geometry is dirtier than
  assumed), say so and propose the amendment rather than silently working around it.
- Prefer the simplest thing that satisfies the criterion. This is a demonstration of clear
  method, not of clever code.
