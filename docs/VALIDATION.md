# VALIDATION.md — Manhattan Sidewalk Shade Index

*Spot-checks and validation results. Updated as each stage completes.*

## S0 — Source Resolution

**Status:** Pending (not yet run)

- [ ] All 5 data sources verified against live catalogs
- [ ] Dataset IDs confirmed in data dictionaries
- [ ] Column names and types validated
- [ ] All URLs tested with HEAD request
- [ ] Access dates recorded

---

## S1 — Ingest and Clip

**Status:** Pending (not yet run)

- [ ] Tree record count in plausible range (15k–20k expected for Manhattan after filtering)
- [ ] Tree `status = "Alive"` filter applied; dead/stump count noted
- [ ] DBH null/≤0 records dropped; count reported
- [ ] All layers reprojected to EPSG:32618
- [ ] Bounds check: all layers overlap and cover Manhattan
- [ ] CRS assertion: `gdf.crs.to_epsg() == 32618` passes

**QA summary** (printed to stdout):
```
s1: Ingest and clip
  trees: 15,234 rows | CRS: EPSG:32618 | Bounds: [x_min, y_min, x_max, y_max] | Nulls: 0
  sidewalks: 8,945 polygons | Area: X.XX km² | Nulls: 0
  lion: 15,432 linestrings | CRS: EPSG:32618 | Nulls: 0
```

---

## S2 — Analysis Units

**Status:** Pending (not yet run)

- [ ] Multipart polygons exploded; count before/after recorded
- [ ] Subdivision applied to units > `max_unit_area_m2` (config: 250 m²); count of subdivided units
- [ ] Unit area distribution: min, median, max, and count of outliers (>1000 m²)
- [ ] Total area retained within 1% of input sidewalk area
- [ ] LION assignment: every unit has a `street_name` and `side` label
- [ ] No overlaps in final unit layer

**Spot-check:** 5 random units inspected in QGIS:
1. Unit boundary aligns with input sidewalk
2. Centroid is in the expected Manhattan location
3. Street name is recognizable (real NYC street)
4. Side assignment (L/R) is geometrically plausible (centroid is actually on that side of the centerline)

---

## S3 — Crown Geometry

**Status:** Pending (not yet run)

- [ ] Crown radii: min, max, median; all ∈ [0.5 m, 12 m]
- [ ] Tree heights: min, max, median; all ∈ [2 m, 30 m]
- [ ] No nulls in derived columns
- [ ] Fallback form-class count and share: `n_fallback / n_trees`. **Stop if > 20%.**
- [ ] Species-to-form-class mapping applied; any unmapped species listed

**QA summary:**
```
s3: Crown geometry
  crown_radius: min=0.51m | median=2.84m | max=12.0m (capped)
  tree_height: min=2.0m | median=7.2m | max=30.0m (capped)
  fallback_species: 1,245 trees (8.2%) → generic form class
```

---

## S4 — Shadow Projection

**Status:** Pending (not yet run)

- [ ] **Direction check (08:00 shadows):** sample 5 trees, verify shadow points west (azimuth + 180° = ~270°)
- [ ] **Direction check (16:00 shadows):** sample 5 trees, verify shadow points east (azimuth + 180° = ~90°)
- [ ] **Area check:** shadow union area by hour, peaks near noon (12:00–13:00)
- [ ] **Noon check:** at 12:00, no shadow union is empty (tree count > 0)
- [ ] Timesteps with altitude ≤ 5° successfully skipped and logged
- [ ] No invalid/degenerate geometries in output

**Direction validation table (example):**

| Hour | Expected azimuth | Expected shadow direction | Spot-check tree (dbh) | Observed direction | Valid? |
|---|---|---|---|---|---|
| 08:00 | 87° (rising sun, E) | W (270°) | Oak (25 cm) | 271° | ✓ |
| 12:00 | 180° (due S) | N (0°) | Maple (30 cm) | 1° | ✓ |
| 16:00 | 272° (setting sun, W) | E (90°) | Sycamore (40 cm) | 89° | ✓ |

**Shadow area by hour (m²):** [To be populated post-run]

---

## S5 — Shade Index

**Status:** Pending (not yet run)

- [ ] Shade fraction clipped to [0, 1]; all ∈ [0, 1]
- [ ] Shade index (integrated) all ∈ [0, 1]
- [ ] Peak heat index all ∈ [0, 1]
- [ ] Top 20 streets by peak_heat_index are plausible (tree-lined side streets beat bare avenues)
- [ ] **5-unit visual spot-check in QGIS:**
  - Unit centroid marked and named
  - Shade fractions per hour plotted or listed
  - Aerial imagery (Google Street View or NYC orthophoto) examined: shade pattern at 10:00 and 14:00 matches prediction
  - Notes and screenshot recorded below

**Spot-check results (to be populated post-S5):**

| Unit ID | Street | Side | Peak heat index | Observed shade (10:00) | Predicted shade (10:00) | Match? | Notes |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

**Top 20 shadiest streets by peak_heat_index:**

| Rank | Street | Side | Peak heat index | Shade hours |
|---|---|---|---|---|
| 1 | — | — | — | — |

---

## S6 — Web Map and Tiles

**Status:** Pending (not yet run)

- [ ] PMTiles file created and valid (`file size > 100 KB`)
- [ ] GeoJSON export produced; valid GeoJSON, all features have properties
- [ ] Web map loads from file path or local server
- [ ] Hour slider present and functional (drag or input)
- [ ] Clicking a unit shows street name, side, shade hours, tree count
- [ ] Shade index legend present with sequential color ramp
- [ ] Page load time < 3 s
- [ ] Building shadow caveat visible on map (methodology panel)
- [ ] GitHub Pages deployment successful (if applicable)

**Map QA:**
```
Web map load time: —
Tile file size: — MB
Feature count in GeoJSON: —
PM Tiles zoom levels: —
```

---

*Last updated: [Project start]*
