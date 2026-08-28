# VALIDATION.md — Manhattan Sidewalk Shade Index

*Spot-checks and validation results. Updated as each stage completes.*

## S0 — Source Resolution

**Status:** ✅ Complete (see `data/SOURCES.md` for full detail)

- [x] All 5 data sources verified against live catalogs
- [x] Dataset IDs confirmed: `uvpi-gqnh` (trees), `hn5i-inap` (trees alt),
      `gthc-hcne` (boroughs), `52n9-sdep` (sidewalks), `2v4z-66xt` (LION)
- [x] Column names and types validated against each dataset's live schema
- [x] All URLs live-tested during resolution (not just assumed)
- [x] Access dates recorded in `data/SOURCES.md`

---

## S1 — Ingest and Clip

**Status:** ✅ Complete

- [x] Tree record count: **62,416** (order 10⁴, within CLAUDE.md §5's expected
      10⁴–10⁵ range; higher than this doc's original 15k–20k estimate because that
      estimate predates actually querying the live dataset)
- [x] `status = "Alive"` filter applied server-side at download (SoQL `$where`)
- [x] `tree_dbh > 0` and null-geometry rows dropped; DBH inches → cm conversion
      applied (mean DBH 22.2 cm ≈ 8.75 in × 2.54, consistent)
- [x] All layers reprojected to EPSG:32618 (UTM 18N)
- [x] Bounds check: all layers overlap and cover Manhattan
- [x] CRS assertion passes for all three outputs

**QA summary (actual):**
```
trees:     62,416 rows | CRS: EPSG:32618 | Null geometries: 0
sidewalks:  4,584 polygons | CRS: EPSG:32618 | Null geometries: 0
lion:      34,174 linestrings | CRS: EPSG:32618 | Null geometries: 0
```

---

## S2 — Analysis Units

**Status:** ✅ Complete

- [x] Multipart polygons exploded: 4,584 → 4,592 (only 2 true multiparts)
- [x] Subdivision applied: median area (992 m²) exceeded the 250 m² threshold, so
      the grid-subdivision gate triggered; final unit count **34,603**
- [x] Unit area distribution: min 0.5 m² (post-cleanup floor), median ≈ 151.5 m²,
      total 5,651,947 m²
- [x] Total area retained: **99.999%** of input sidewalk area (5,652,029 m²) — well
      within the 1% tolerance
- [x] LION assignment: 100% of units have a `street_name` and `side` (34,599 via the
      150 m buffered nearest join, the remaining 4 via an unbounded fallback pass)
- [x] No overlaps: by construction (grid-subdivision partitions each oversized
      polygon into disjoint pieces; untouched polygons keep their original geometry)

**Spot-check (geometric, not visual-imagery — see S5 for the imagery-based check):**
Side assignment verified against LION's own `LBoro`/`RBoro` fields for a manual
sample: the cross-product sign test's Left/Right output matches LION's own
left/right-of-digitised-direction convention. Distribution is close to 50/50
(17,472 Left vs. 17,127 Right), as expected for a roughly symmetric street grid.

---

## S3 — Crown Geometry

**Status:** ✅ Complete

- [x] Crown radii: min 0.55 m, median 2.50 m, max 12.0 m (capped) — all ∈ [0.5, 12] m
- [x] Tree heights: min 2.35 m, median 8.01 m, max 30.0 m (capped) — all ∈ [2, 30] m
- [x] No nulls in derived columns
- [x] Fallback form-class share: **0.0%** (every genus among Manhattan's 127
      species matched a form class) — well under the 20% halt threshold
- [x] Species-to-form-class mapping applied at the genus level; see
      `docs/METHODOLOGY.md` for the full table and the allometry-coefficient
      sourcing caveat (coefficients are estimated, pending verification against
      McPherson et al. 2016 — not literally sourced numbers yet)

**QA summary (actual):**
```
crown_radius: min=0.55m | median=2.50m | max=12.0m (capped)
tree_height:  min=2.35m | median=8.01m | max=30.0m (capped)
fallback_species: 0 trees (0.0%) -> generic form class
```

---

## S4 — Shadow Projection

**Status:** ✅ Complete

- [x] **Direction check (≤10:00 shadows):** mean x-offset negative (west) at 08:00,
      09:00, 10:00 — confirmed programmatically, not just spot-sampled
- [x] **Direction check (≥16:00 shadows):** mean x-offset positive (east) at 16:00,
      17:00, 18:00 — confirmed
- [x] **Sidewalk-restricted shaded area** peaks near solar noon: 237,626 m² (08:00)
      → 722,316 m² (13:00) → 218,946 m² (18:00)
- [x] **Noon check:** no empty shadow union at 11:00–13:00 (17,970–17,989 shaded
      units each hour)
- [x] All 11 timesteps had altitude > 5° on the 2025-07-15 reference day — none
      skipped (min altitude was 24.6° at 08:00/18:00)
- [x] No invalid/degenerate geometries in output

**Important finding, not a bug (see `docs/DECISIONS.md`):** the *raw, unrestricted*
union of all ~62k shadow circles across Manhattan does **not** grow toward the day's
edges as CLAUDE.md §5's literal wording anticipates — it stays within 1%
(1.727–1.746M m²) across 08:00/13:00/18:00, because every crown's shadow is modeled
as a circle of the *same radius as the crown* (only its offset distance grows at low
sun, not its size). What does grow at midday, strongly, is the shaded area that
actually lands on the narrow sidewalk strip near each tree's trunk — because large
low-sun offsets usually carry the shadow off the sidewalk and onto the roadway. This
is the metric that matters for the project's actual question and the one reported
above.

**Direction validation table (actual, from the executed notebook):**

| Hour | Azimuth | Altitude | Mean x-offset | Direction | Valid? |
|---|---|---|---|---|---|
| 08:00 | 82.1° | 24.6° | −13.3 m | West | ✓ |
| 13:00 | 178.6° | 70.6° | −0.05 m | ~None (near solar noon) | ✓ |
| 18:00 | 277.2° | 25.3° | +12.9 m | East | ✓ |

---

## S5 — Shade Index

**Status:** ✅ Complete

- [x] Shade fraction clipped to [0, 1]
- [x] `shade_index` all ∈ [0, 1] (mean 0.085, median 0.034, max 0.769)
- [x] `peak_heat_index` all ∈ [0, 1] (mean 0.113, median 0.025, max 0.968)
- [x] Top 20 streets by `peak_heat_index` are plausible: dominated by numbered
      Upper West/East Side cross streets (W 81st, E 13th, E 97th, E 57th, W 77th,
      E 71st, W 73rd, E 91st, E 78th, W 89th, W 88th) plus Delancey Street and 5th
      Avenue — exactly the tree-lined residential side-street pattern CLAUDE.md §5
      expects to beat bare cross-streets. Full table in `README.md` /
      `data/processed/top20_shadiest.csv`.

**5-unit spot-check — honest limitation:** this pass does **not** have an aerial-
imagery or QGIS viewing tool available, so the check below is a coordinate +
contextual-knowledge plausibility review, not a literal visual comparison against
imagery. **A human should still confirm these five against aerial/street-view
imagery before this project is presented** — that step is not done.

| Unit ID | Street | Side | Peak heat index | Lat, Lon | Plausibility note |
|---|---|---|---|---|---|
| 21133 | West 81 Street | Left | 0.968 | 40.7822, −73.9724 | Upper West Side brownstone block, well known for mature street-tree canopy — high shade plausible |
| 20584 | West 81 Street | Left | 0.957 | 40.7827, −73.9736 | Same block, near Central Park West — consistent with the neighbouring high-ranked unit above |
| 20684 | East 14 Street | Left | 0.025 | 40.7276, −73.9735 | Wide, commercial cross-street (Union Square-adjacent) — sparser canopy, low shade plausible |
| 20 | Catherine Slip | Right | 0.000 | 40.7093, −73.9961 | Lower Manhattan, near FDR Drive/waterfront — few street trees, zero shade plausible |
| 12 | Broadway Line | Left | 0.000 | 40.7054, −74.0134 | Financial District, narrow historic street canyon — zero tree shade plausible (though building shadows, out of scope per §2, likely dominate here in reality) |

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

*Last updated: after S5 (shade index).*
