# SKILL.md — Modern GIS Accelerator Stack

This file is the authoritative technology guide for all projects in this repo.
Read it before making any tool, library, or format decision. Where it conflicts
with anything in CLAUDE.md or elsewhere, this file wins.

---

## 0. The Mental Model

The modern GIS stack has five layers. Every tool fits into one of them.
Always route work to the right layer — do not mix concerns.

| Layer | Purpose | Primary tools |
|---|---|---|
| **Desktop** | View, inspect, connect, style | QGIS |
| **Database** | Store, query, analyse at scale | PostGIS, DuckDB |
| **Languages** | Orchestrate, transform, automate | SQL, Python |
| **Web** | Render maps in the browser | MapLibre GL JS, PMTiles |
| **Cloud** | Store and query remote data | S3, GeoParquet, Overture Maps |

**Core rule:** do data logic in SQL, orchestrate in Python, render in MapLibre.
Never do heavy processing in the desktop. Never do in Python what SQL can do
in one query.

---

## 1. Languages

### SQL — use for all data logic
- Spatial joins, aggregations, filters, area calculations, density normalisation
- One query can hold what would take 20 lines of Python
- Portable across PostGIS, DuckDB, BigQuery, Sedona — learn it once
- **Default predicate for point-in-polygon:** `ST_Contains(polygon.geom, point.geom)`
- **Always reproject before measuring:** `ST_Area`, `ST_Distance`, `ST_Buffer` on
  EPSG:4326 return degrees, not metres — meaningless for real-world analysis

### Python — use for orchestration, not data logic
- Load data, call SQL, visualise, export, automate pipelines
- Keep Python logic small and readable; push complexity into SQL
- Import pattern: `import geopandas as gpd`
- Always use a conda environment; never install globally

---

## 2. Database layer

### PostGIS (primary spatial database)
- Runs in Docker — start with `docker compose up -d`, stop with `docker compose down`
- Default connection: `host=localhost port=5432 dbname=gis user=gis password=gis`
- Geometry column name convention: `wkb_geometry`
- Load data: `ogr2ogr -f "PostgreSQL" "PG:host=localhost dbname=gis user=gis password=gis" input.geojson -nln table_name -overwrite -lco GEOMETRY_NAME=wkb_geometry`
- Export from PostGIS: `ogr2ogr -f "GeoJSON" out.geojson "PG:..." -sql "SELECT ... FROM table" -nln results -lco RFC7946=YES`
- Connect from Python via SQLAlchemy + psycopg2: `gpd.read_postgis(query, engine, geom_col="wkb_geometry")`

**Key PostGIS functions (ST_ prefix always):**

| Function | Use |
|---|---|
| `ST_Contains(a, b)` | Is point b inside polygon a? |
| `ST_Intersects(a, b)` | Do geometries touch or overlap? |
| `ST_Within(a, b)` | Is a inside b? (inverse of Contains) |
| `ST_DWithin(a::geography, b::geography, metres)` | Within N metres? Uses spatial index |
| `ST_Area(geom::geography)` | Area in m² (cast to geography for metres) |
| `ST_Distance(a::geography, b::geography)` | Distance in metres |
| `ST_Buffer(geom::geography, metres)` | Buffer in metres |
| `ST_Transform(geom, epsg)` | Reproject |
| `ST_Centroid(geom)` | Centre point |
| `ST_Union(geom)` | Dissolve/merge geometries |
| `ST_MakePoint(lon, lat)` | Build a point — lon first |
| `ST_SetSRID(geom, 4326)` | Assign CRS |
| `ST_AsGeoJSON(geom)` | Serialise to GeoJSON text |

**CRS rule:** cast to `::geography` for metre-based measurements in PostGIS,
or `ST_Transform(geom, 2263)` for NY State Plane (feet) or `ST_Transform(geom, 3857)`
for Web Mercator (metres). Never measure in EPSG:4326.

**Round numeric results:** `ROUND((ST_Area(g::geography)/1000000)::numeric, 2)`
— the double-colon cast to `numeric` is required before `ROUND` in PostGIS.

### DuckDB (in-process analytics, cloud queries)
Three modes — same SQL dialect in all three:

1. **Local files** — query Parquet/GeoJSON/CSV directly, no server:
   `duckdb.sql("SELECT * FROM read_parquet('file.parquet')")`
2. **S3/cloud** — query remote Parquet without downloading:
   ```sql
   INSTALL spatial; INSTALL httpfs;
   LOAD spatial; LOAD httpfs;
   SET s3_region = 'us-west-2';
   ```
3. **MotherDuck** — managed DuckDB for team access

Always load extensions at the start of each session (`LOAD spatial; LOAD httpfs;`).
Install once per DuckDB installation (`INSTALL spatial;`).

---

## 3. Python spatial stack

### GeoPandas (primary Python spatial library)
```python
import geopandas as gpd

# Read
gdf = gpd.read_file("data.geojson")        # GeoJSON, Shapefile, GPKG, FlatGeobuf
gdf = gpd.read_parquet("data.parquet")     # GeoParquet — preferred for large files
gdf = gpd.read_postgis(sql, engine, geom_col="wkb_geometry")  # from PostGIS

# Inspect first — always
print(gdf.crs)
print(gdf.shape)
gdf.head()

# CRS — check before every spatial operation
gdf = gdf.set_crs("EPSG:4326")            # assign if missing
gdf_m = gdf.to_crs("EPSG:3857")           # reproject for measurements

# Spatial join
joined = gpd.sjoin(points, polygons, predicate="within", how="left")

# Aggregate
counts = joined.groupby("name").size().rename("count").to_frame()

# Area (always reproject first)
gdf["area_km2"] = gdf.to_crs(3857).area / 1_000_000

# Write
gdf.to_parquet("out.parquet")              # GeoParquet — default output format
gdf.to_file("out.geojson", driver="GeoJSON")
```

**SQL vs Python decision rule:**
- Data joins, aggregations, filters, area calcs → **SQL**
- Loading, plotting, exporting, pipeline glue → **Python**
- Both together: SQL does the heavy transform, Python reads the result with
  `gpd.read_postgis()` and exports to GeoParquet

### conda environment
- Environment name: `gis` (course work) / `carbon-gis` (Burgos project)
- Activate: `conda activate gis`
- Never install packages globally; always activate the environment first

---

## 4. CLI and GDAL

**Inspect:**
```bash
ogrinfo -so data.geojson layername        # vector summary: CRS, columns, count
gdalinfo raster.tif                        # raster info
head -n 1 data.csv | tr ',' '\n' | cat -n # CSV columns
```

**Convert:**
```bash
ogr2ogr -f "GeoJSON" out.geojson in.gpkg
ogr2ogr -f "Parquet" out.parquet in.geojson
ogr2ogr -f "GeoJSON" out.geojson in.parquet
```

**CSV with lat/lon → spatial:**
```bash
ogr2ogr -f "Parquet" out.parquet in.csv \
    -oo X_POSSIBLE_NAMES=longitude -oo Y_POSSIBLE_NAMES=latitude \
    -oo AUTODETECT_TYPE=YES -a_srs EPSG:4326
```
GDAL auto-detects columns named `latitude`/`longitude` — always use those names.

**Reproject:**
```bash
ogr2ogr -f "GeoJSON" out_3857.geojson in.geojson -s_srs EPSG:4326 -t_srs EPSG:3857
```

**Filter and clip:**
```bash
ogr2ogr -f "GeoJSON" out.geojson in.geojson -where "borough = 'Manhattan'"
ogr2ogr -f "GeoJSON" out.geojson in.geojson -clipdst -74 40.5 -73.7 40.9
```

**Key flags reference:**

| Flag | Meaning |
|---|---|
| `-f "Format"` | Output format |
| `-nln name` | Output layer/table name |
| `-overwrite` | Replace existing output |
| `-s_srs` / `-t_srs` | Source / target CRS |
| `-a_srs` | Assign CRS without reprojecting |
| `-where "expr"` | SQL WHERE filter |
| `-sql "query"` | Full SQL as source |
| `-oo KEY=VAL` | Open option |
| `-lco KEY=VAL` | Layer creation option |

---

## 5. File formats

Always use the right format for the right purpose. Never use shapefiles past ingestion.

| Format | Use | Notes |
|---|---|---|
| **GeoParquet** | Analysis storage, pipeline hub | Default for all intermediate and output data |
| **GeoJSON** | Exchange, tippecanoe input, API output | Not for large files |
| **PMTiles** | Web rendering | Single file, no server, HTTP range requests |
| **GeoPackage** | Share with GIS users | Universal transfer format |
| **FlatGeobuf** | Lightweight browser vector | Supports spatial filtering on read |
| **COG** | Raster hosting | Cloud Optimized GeoTIFF |
| **Shapefile** | Legacy ingestion only | Never output; multiple sidecar files, 2 GB cap |

**Decision tree:**
- Display in browser → **PMTiles**
- Analytical queries → **GeoParquet**
- Share with GIS users → **GeoPackage** or **GeoParquet**
- Imagery → **COG**

---

## 6. CRS reference

| Code | Name | Units | Use |
|---|---|---|---|
| **EPSG:4326** | WGS 84 | Degrees | Storage, exchange, raw data, web maps |
| **EPSG:3857** | Web Mercator | Metres | Web tile rendering, area/distance calculations |
| **EPSG:2263** | NY State Plane Long Island | Feet | NYC-specific precision measurements |
| **OGC:CRS84** | WGS 84 lon/lat | Degrees | GeoParquet default (equivalent to 4326) |

**Rule:** check `gdf.crs` after every read. Assert CRS at the top of every
pipeline stage. A silent CRS mismatch is the most likely way a project produces
confident nonsense.

---

## 7. Web mapping

### PMTiles (tile format)
- Single-file archive of vector tiles — no server required
- Generated with **tippecanoe** (install via pipx in WSL/Ubuntu on Windows)
- Served from GitHub Pages, S3, Cloudflare R2, or any static host
- **Local dev:** requires HTTP range requests — use `python3 -m RangeHTTPServer 8080`
  NOT `python3 -m http.server` (standard server does not support range requests
  and will fail silently)

**tippecanoe recipes:**

```bash
# Polygons (neighbourhoods, boundaries)
tippecanoe -o output.pmtiles -l layer_name \
  -Z8 -z14 \
  --detect-shared-borders \
  --coalesce-densest-as-needed \
  --simplification=2 \
  --force input.geojson

# Points — large dataset (>100k)
tippecanoe -o output.pmtiles -l layer_name \
  -Z6 -z14 \
  --drop-densest-as-needed \
  --force input.geojson

# Lines (roads, routes)
tippecanoe -o output.pmtiles -l layer_name \
  -Z6 -z14 \
  --simplification=4 \
  --coalesce-smallest-as-needed \
  --force input.geojson
```

**Always set `-l` explicitly.** The `source-layer` in MapLibre must match this
exactly. Run `pmtiles show output.pmtiles` after every build to verify.

**Zoom range guide:**

| Zoom | Scale | Good for |
|---|---|---|
| 0–5 | Continent | Not useful for city data |
| 6–8 | Metro area | City overview, borough boundaries |
| 9–11 | Neighbourhood | Neighbourhoods, major roads |
| 12–14 | Block level | Individual buildings, POIs |

### MapLibre GL JS (web renderer)
Mental model — three concepts only:
1. **Source** — where the data lives (`pmtiles://https://...`)
2. **Layer** — how to draw it (type: `fill`, `line`, `circle`, `symbol`)
3. **Style (paint)** — visual properties via expressions

```javascript
// Register PMTiles protocol
maplibregl.addProtocol("pmtiles", new pmtiles.Protocol().tile);

// Add source
map.addSource("my-data", {
  type: "vector",
  url: "pmtiles://https://example.com/data.pmtiles"
});

// Add layer
map.addLayer({
  id: "my-layer",
  type: "fill",
  source: "my-data",
  "source-layer": "layer_name",   // must match tippecanoe -l value
  paint: {
    "fill-color": [
      "step", ["get", "density"],
      "#ffffcc", 50,
      "#feb24c", 150,
      "#f03b20"
    ],
    "fill-opacity": 0.8
  }
});
```

**Click popup pattern:**
```javascript
map.on("click", "my-layer", (e) => {
  const props = e.features[0].properties;
  new maplibregl.Popup()
    .setLngLat(e.lngLat)
    .setHTML(`<strong>${props.name}</strong><br>${props.value}`)
    .addTo(map);
});
```

### GitHub Pages deployment
1. `git push` repo to GitHub
2. Settings → Pages → Deploy from branch → main / root
3. URL: `https://{username}.github.io/{repo-name}/`
4. Verify in incognito — check browser console for errors
5. File size limit: 100 MB per file (target <50 MB for .pmtiles)

---

## 8. Cloud and Overture Maps

### Overture Maps (S3 public bucket)
```sql
-- DuckDB setup (once per session)
LOAD spatial; LOAD httpfs;
SET s3_region = 'us-west-2';

-- Always check current release date first:
-- aws s3 ls s3://overturemaps-us-west-2/release/ --no-sign-request

-- S3 path pattern:
-- s3://overturemaps-us-west-2/release/{YYYY-MM-DD}/theme={theme}/type={type}/*

-- Bounding box filter — ALWAYS include this (never scan without it)
WHERE bbox.xmin BETWEEN <lon_min> AND <lon_max>
  AND bbox.ymin BETWEEN <lat_min> AND <lat_max>
```

**Themes:**

| Theme | Type | Contains |
|---|---|---|
| buildings | building | Footprints, height, floors |
| places | place | POIs, businesses |
| transportation | segment | Roads, paths |
| addresses | address | Street addresses |
| base | water, land_use | Water bodies, land cover |
| divisions | division_area | Admin boundaries |

**NYC Manhattan bounding box:** `xmin > -74.02, xmax < -73.93, ymin > 40.70, ymax < 40.82`

### NYC Open Data (Socrata API)
Download pattern: `https://data.cityofnewyork.us/resource/{ID}.geojson?$limit={N}`

| Dataset | ID |
|---|---|
| 2020 Neighbourhood Tabulation Areas | `9nt8-h7nd` |
| Hydrants (NYCDEP) | `5bgh-vtsn` |

### Pipeline pattern (bronze → silver → gold)
```
Bronze: raw download, untouched GeoParquet
Silver: cleaned, filtered, CRS standardised, validated GeoParquet
Gold:   joined, aggregated, analysis-ready → GeoParquet (data) or PMTiles (map)
```
All spatial logic in silver. Gold is final prep only.

---

## 9. AI-assisted development

Follow the four-step loop on every task:
1. **Describe** — plain English with full context: tools, CRS, column names, expected output
2. **Generate** — let AI write the code/command/query
3. **Verify** — run it, check results visually, validate CRS, check counts
4. **Modify** — paste errors back with context; do not start over

**Always verify spatially:** plot the map, check that shadows/buffers/joins
fall where expected. AI cannot see your data — visual inspection is on you.

**Always specify CRS in prompts.** AI may forget to transform if not told.

**Common AI failure modes:**
- Forgetting CRS transformation before measurement
- Outdated library syntax (include version numbers in prompts)
- Hallucinated PostGIS functions (verify against postgis.net/docs)

---

## 10. Windows-specific environment notes

- **Git Bash** for course shell work (Unix command compatibility)
- **conda `gis` environment** for all GIS/data processing (Windows)
- **WSL/Ubuntu** only for tippecanoe and PMTiles build steps
- All data processing stays in Windows conda — do not mix environments
- Local web server for PMTiles: `python3 -m RangeHTTPServer 8080` (in WSL or
  any Python env with `rangehttpserver` installed via pipx)

---

## 11. What to skip

Do not reach for these unless a stage explicitly requires it:

- Streamlit — not needed for portfolio web maps
- Leaflet — MapLibre replaces it; do not mix
- Kubernetes / advanced Docker — beyond course scope
- R for spatial — only if specialising in statistics later
- GeoServer / TileServer GL — PMTiles replaces both
- Shapefiles as output — always output GeoParquet or GeoJSON instead
