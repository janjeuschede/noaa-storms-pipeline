# NOAA Storms Pipeline

A one-command pipeline that downloads a year of NOAA Storm Events data, converts it to GeoParquet, and lands it ready for analysis in DuckDB, GeoPandas, or QGIS.

## What it does

`pipeline.sh` takes a year (default: 2025), finds the newest matching `details`
file in NOAA's public archive, downloads and decompresses it, and converts its
longitude and latitude columns into point geometry using WGS 84 (EPSG:4326).

The pipeline creates two outputs:

- `data/processed/storms_events_{YEAR}.parquet` for analysis in DuckDB,
  GeoPandas, or other tools that support GeoParquet
- `data/processed/storms_events_{YEAR}.gpkg` for visual exploration in QGIS

Total runtime: about 90 seconds for a typical year on a home internet connection.

## The data

- **Source:** [NOAA Storm Events Database](https://www.ncei.noaa.gov/data/storm-events/)
- **License:** Public domain (US federal data)
- **What's in it:** every recorded storm event in the United States for the given year, including type, location, and damages

## How to run it

Requires Bash, GDAL 3.5 or newer (for `ogr2ogr` and `ogrinfo`), and the standard
Unix utilities `curl` and `gunzip`.

```bash
git clone https://github.com/{your-username}/noaa-storms-pipeline.git
cd noaa-storms-pipeline
chmod +x pipeline.sh
./pipeline.sh
```

To run for a specific year:

```bash
./pipeline.sh 2023
```

## What I learned

I learned how to build a repeatable command-line data pipeline with strict Bash
error handling and cached intermediate files. One challenge was that NOAA's
filenames contain a creation date that changes whenever data is republished, so
the script discovers and selects the newest matching file instead of hardcoding
the name. I also learned how GDAL turns longitude and latitude columns into
spatial point geometry and writes the result to GeoParquet and GeoPackage.

## Stack

- bash
- curl
- GDAL / ogr2ogr
- GeoParquet
- GeoPackage
