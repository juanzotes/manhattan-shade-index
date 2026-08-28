# METHODOLOGY.md — Manhattan Sidewalk Shade Index

*Every assumption goes here with its source or its status as a placeholder.*

## Solar Geometry

### NOAA/SPA algorithm

**Source:** NOAA/SPA solar position algorithm, implemented in `pvlib-python` (Holmgren et al.)

**Implementation:** `pvlib.location.Location.get_solarposition()` with:
- Reference day: config `reference_date` (default: 2025-07-15)
- Location: Manhattan centroid (40.7831° N, 73.9712° W, z=0 m)
- Timezone: `America/New_York`
- Timesteps: hourly 08:00–18:00 local time

**Simplification:** One location for all of Manhattan (~20 km wide). Azimuth and altitude vary <1° across the borough at a given hour; neglected.

**Output:** Solar azimuth (0–360°, 0=N, 90=E) and altitude (degrees, negative below horizon) per timestep.

**Reference:** Holmgren, W. F., Hansen, C. W., & Mikofski, M. A. (2018). pvlib python: A python package for solar photovoltaic modeling and analysis. *Journal of Open Source Software*, 3(29), 884.

---

## Crown Geometry

### Allometry (DBH → crown radius and height)

**Allometry model:**
```
crown_radius_m     = a_r * (dbh_cm ** b_r)
tree_height_m      = a_h * (dbh_cm ** b_h)
crown_base_height  = base_ratio * tree_height_m
crown_centre_height = crown_base_height + crown_radius_m
```

**Status:** **estimated, pending primary-source verification** — see below. Not
PLACEHOLDER in the sense of "arbitrary"; each row is a deliberate order-of-magnitude
estimate consistent with its form class's known crown habit, but none has been
individually checked against a primary regression table.

**Authoritative source (not yet reconciled row-by-row):** McPherson, E.G., van Doorn,
N.S., & Peper, P.J. (2016). *Urban Tree Database and Allometric Equations.* USDA
Forest Service Gen. Tech. Rep. PSW-GTR-253.
[research.fs.usda.gov/treesearch/52933](https://research.fs.usda.gov/treesearch/52933).
365 species × climate-region equation sets (crown diameter, height, and more, vs.
DBH), collected 1998–2012 across 17 US cities. This is the standard citation for
urban street-tree allometry and is where the Northeast-region, per-species
coefficients for the table below should ultimately come from — extracting and
re-fitting all six form classes' equations into this project's simplified
`radius = a·dbh^b` power-law form from the primary report was out of scope for this
pass (see `docs/DECISIONS.md`). Before this project is presented, replace the table
below with values actually read from that source (or an equivalent i-Tree Eco species
table) and update this row's status to **sourced**.

### Crown coefficients by form class

| Form class | Representative species | a_r | b_r | a_h | b_h | base_ratio | Status |
|---|---|---|---|---|---|---|---|
| broad_spreading | *Platanus × acerifolia* (sycamore) | 0.50 | 0.62 | 1.90 | 0.50 | 0.40 | estimated |
| open_fine | *Gleditsia triacanthos* (honeylocust) | 0.48 | 0.60 | 1.85 | 0.50 | 0.45 | estimated |
| medium_dense | *Tilia cordata* (linden) | 0.45 | 0.60 | 1.80 | 0.50 | 0.40 | estimated |
| narrow_upright | *Ginkgo biloba* (ginkgo) | 0.32 | 0.58 | 2.10 | 0.50 | 0.45 | estimated |
| small_ornamental | *Pyrus calleryana* (callery pear) | 0.40 | 0.55 | 1.50 | 0.48 | 0.35 | estimated |
| generic (fallback) | Unmatched or null species | 0.45 | 0.60 | 1.80 | 0.50 | 0.40 | estimated |

**Caps:** `crown_radius` ≤ 12 m, `tree_height` ≤ 30 m (to absorb DBH outliers).

### Species → form class mapping

Manhattan's 62,416 filtered trees span 127 distinct `spc_latin` values. Matched at
the **genus** level (e.g. every `Quercus` species → `broad_spreading`) against
general urban-forestry crown-habit classification: broadleaf spreading canopy vs.
fine/open vs. dense-rounded vs. conical/columnar (conifers, poplars) vs. small
ornamental. This is a categorical *shape* judgment, independent of the allometry
coefficients above, implemented in `src/s3_crown_geometry.ipynb`
(`GENUS_TO_FORM_CLASS`). **Result: 0.0% fallback share** (every genus present in the
Manhattan census matched) — well under the 20% halt threshold in CLAUDE.md §5.

---

## Crown Opacity

**Assumption:** v1 treats all crowns as **opaque** (100% light blocking).

**Reality:** Real canopies transmit light; *Gleditsia* (honeylocust) is notably open-canopy.

**Implementation:** Placeholder `opacity` column in allometry table, set to 1.0 for all classes. v2 refinement is a config change, not a rewrite.

---

## Shadow Projection

### Shadow model

**Assumption:** The crown is modeled as a **sphere** of radius `crown_radius_m` centred at height `crown_centre_height_m` above ground (z=0).

**Shadow:** Under parallel illumination (sun far away), a sphere's shadow is a circle of the same radius. The shadow circle is offset from the trunk by:

$$d = \frac{h}{\tan(\alpha)}$$

where $h$ is `crown_centre_height_m` and $\alpha$ is solar altitude (radians). The offset direction is azimuth + 180° (opposite the sun).

**Vectorisation:** 
1. Compute offset (x, y) for each tree using numpy: `offset = crown_centre_height / np.tan(altitude_rad)`
2. Use `geopandas.GeoSeries.buffer()` with `cap_style=1` (round caps) to create shadow circles
3. Translate to offset (x, y) using `.apply(lambda geom: affine_transform(geom, ...))`
4. Union all shadows per timestep: `GeoSeries(shadows).unary_union`
5. Intersect union with sidewalk analysis units using `geopandas.clip()` or `overlay()`

**Minimum altitude filter:** Skip timesteps where altitude ≤ 5° (config `min_altitude_deg`). Grazing-sun shadows extend far and become meaningless.

**Diagram:**
```
        Sun at azimuth=90°, altitude=30°
        ↓ (from east)
        
        | crown centre (height h)
        ●━━━ shadow offset
        ║     d = h / tan(30°)
        │     ≈ 1.73h
    ━━━┷━━━━━ ground (z=0)
    trunk  shadow circle
```

### Spot-check validation

After S4, visual checks:
1. **Morning shadows (08:00–10:00)** should point **west** (away from rising sun)
2. **Afternoon shadows (16:00–18:00)** should point **east** (away from setting sun)
3. **Shadow area** should peak near solar noon (12:00–13:00)
4. At minimum altitude filter, shadow should disappear gracefully

---

## Shade Index Calculation

### Per-unit, per-timestep shade fraction

$$\text{shade\_fraction}_t = \frac{\text{shaded\_area}_t}{\text{unit\_area}}$$

where shaded_area is clipped to unit_area (no double-counting from overlapping crowns).

### Integrated shade index

$$\text{shade\_hours} = \sum_t \left( \text{shade\_fraction}_t \times \Delta t \right)$$

$$\text{shade\_index} = \frac{\text{shade\_hours}}{\text{window\_length}} = \frac{\text{shade\_hours}}{10 \text{ hours}}$$

(Window is 08:00–18:00 = 10 hours at 1-hour intervals.)

**Range:** [0, 1], where 1 = fully shaded for the entire window.

### Peak heat index

$$\text{peak\_heat\_index} = \text{mean}\left(\text{shade\_fraction}_t\right) \text{ for } t \in [11:00, 16:00)$$

This is the average shade during peak solar hours, when surface temperature matters most. Rank sidewalks on this metric in the "best walks" table.

---

## Units of measurement

- **DBH (input):** inches (NYC census convention). Converted to cm at S1.
- **DBH (internal):** centimetres
- **Distance, radius, height:** metres
- **Area:** square metres
- **CRS (analysis):** EPSG:32618 (UTM 18N). All coordinates in metres.
- **CRS (output web):** EPSG:4326 (WGS84, degrees)

---

## Reproducibility

All timestamps are **timezone-aware** in `America/New_York`. No naive datetimes.

All random seeds are **fixed** or absent. Pipeline is deterministic: same config + same raw data → byte-identical GeoParquet.

---

## Known limitations and v2 extensions

1. **Building shadows:** The dominant source of Manhattan shade. v2: project building footprints + report tree marginal contribution.
2. **Canopy transmittance:** Real canopies leak light. v2: per-species opacity factor.
3. **Terrain:** Assumed flat (z=0). v1 is valid; Manhattan is flat enough.
4. **Crown shape:** Spherical is a simplification. Real crowns are ellipsoids or irregular. v2: ellipsoid fit per species.
5. **Tree data age:** 2015 census is ~10 years old. v2: temporal sensitivity analysis with live Forestry feed.

---

*Last updated: S0 (sources not yet resolved)*
