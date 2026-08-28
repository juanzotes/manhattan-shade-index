.PHONY: all clean env s0 s1 s2 s3 s4 s5 s6 help

NBCONVERT = jupyter nbconvert --to notebook --execute --inplace

help:
	@echo "Manhattan Sidewalk Shade Index — pipeline targets"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  env            Show how to add the missing package to the shared gis env"
	@echo "  s0             Stage 0: resolve data sources"
	@echo "  s1             Stage 1: ingest and clip"
	@echo "  s2             Stage 2: build analysis units"
	@echo "  s3             Stage 3: derive crown geometry"
	@echo "  s4             Stage 4: project shadows"
	@echo "  s5             Stage 5: compute shade index"
	@echo "  s6             Stage 6: build tiles and web map"
	@echo "  all            Run all stages s0–s6 from raw"
	@echo "  clean          Remove all intermediate and processed data"
	@echo ""
	@echo "Stages are Jupyter notebooks, executed headlessly in-place via nbconvert."
	@echo "Activate the shared 'gis' conda environment before running any target."

env:
	@echo "This project runs in the shared 'gis' conda env (see environment.yml)."
	@echo "conda activate gis"
	@echo "conda install -n gis -c conda-forge pvlib   # only package missing from gis"

s0:
	$(NBCONVERT) src/s0_resolve_sources.ipynb

s1:
	$(NBCONVERT) src/s1_ingest.ipynb

s2:
	$(NBCONVERT) src/s2_analysis_units.ipynb

s3:
	$(NBCONVERT) src/s3_crown_geometry.ipynb

s4:
	$(NBCONVERT) src/s4_shadows.ipynb

s5:
	$(NBCONVERT) src/s5_shade_index.ipynb

s6:
	$(NBCONVERT) src/s6_tiles.ipynb

all: s0 s1 s2 s3 s4 s5 s6
	@echo "Pipeline complete."

clean:
	rm -rf data/raw data/interim data/processed web/tiles
	@echo "Data cleaned."
