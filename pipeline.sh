#!/usr/bin/env bash
#
# pipeline.sh — Download a year of NOAA Storm Events, convert to GeoParquet.
#
# Usage:
#   chmod +x pipeline.sh
#   ./pipeline.sh [YEAR]
# Example: ./pipeline.sh 2025
#
# Requires: bash, curl, gunzip, ogr2ogr, ogrinfo (GDAL >= 3.5)

# Safer Bash execution:
#   -e          Exit when a command fails.
#   -u          Exit when an unset variable is used.
#   -o pipefail Treat a pipeline as failed if any command within it fails.
set -euo pipefail
START_TIME=$SECONDS

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------

# Year to pull. Override by passing as the first argument.
YEAR="${1:-2025}"

if [[ ! "$YEAR" =~ ^[0-9]{4}$ ]]; then
  echo "Error: YEAR must be a four-digit year." >&2
  exit 2
fi

# NOAA file naming pattern: StormEvents_details-ftp_v1.0_d{YEAR}_c{CREATED_DATE}.csv.gz
# The "c{CREATED_DATE}" portion changes whenever NOAA republishes a year, so
# rather than hardcoding it, we scrape the directory listing below and pick
# the current filename for YEAR automatically:
# https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/
BASE_URL="https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles"

if ! FILE_NAME="$(
  curl -fsSL "${BASE_URL}/" |
    grep -oE "StormEvents_details-ftp_v1\.0_d${YEAR}_c[0-9]{8}\.csv\.gz" |
    sort -u |
    tail -n 1
)"; then
  echo "Error: Could not find a NOAA details file for year ${YEAR}." >&2
  exit 1
fi

URL="${BASE_URL}/${FILE_NAME}"

RAW_DIR="data/raw"
PROCESSED_DIR="data/processed"
RAW_GZ="${RAW_DIR}/${FILE_NAME}"
RAW_CSV="${RAW_DIR}/${FILE_NAME%.gz}"
OUT_PARQUET="${PROCESSED_DIR}/storms_events_${YEAR}.parquet"

# -----------------------------------------------------------------------------
# Step 1: Set up directories
# -----------------------------------------------------------------------------

echo "[1/5] Setting up directories"
mkdir -p "$RAW_DIR" "$PROCESSED_DIR"

echo "📁 Raw data directory: $RAW_DIR"
echo "📁 Processed data directory: $PROCESSED_DIR"

# -----------------------------------------------------------------------------
# Step 2: Download the raw file
# -----------------------------------------------------------------------------
# Skip the download if the file already exists (idempotency).
echo "[2/5] Downloading ${FILE_NAME}"
if [[ -f "$RAW_GZ" ]]; then
  echo "  Already downloaded; skipping."
else
  curl --fail --location --output "${RAW_GZ}.part" "$URL"
  mv "${RAW_GZ}.part" "$RAW_GZ"
  echo "✅ Downloaded to $RAW_GZ"
fi

# -----------------------------------------------------------------------------
# Step 3: Decompress
# -----------------------------------------------------------------------------
# Skip this step if RAW_CSV already exists.

echo "[3/5] Decompressing"

if [[ -f "$RAW_CSV" ]]; then
  echo "  Already decompressed; skipping."
else
  gunzip -k "$RAW_GZ"
  echo "✅ Decompressed to $RAW_CSV"
fi

# --- Preview CSV stats and columns ---
ROW_COUNT=$(($(wc -l < "$RAW_CSV") - 1))
CSV_SIZE=$(wc -c < "$RAW_CSV")
IFS=',' read -ra COLUMNS < <(head -n 1 "$RAW_CSV")

echo ""
echo "📊 ${FILE_NAME}: ${ROW_COUNT} rows, ${CSV_SIZE} bytes"
echo "📋 Column names:"
printf '%s\n' "${COLUMNS[@]:0:20}"
echo "   ... (${#COLUMNS[@]} columns total)"

# -----------------------------------------------------------------------------
# Step 4: Convert CSV to GeoParquet
# -----------------------------------------------------------------------------
# The CSV uses BEGIN_LON / BEGIN_LAT for the storm start point. ogr2ogr can
# pick those up if you tell it the column names with -oo:
#
#   -oo X_POSSIBLE_NAMES=BEGIN_LON
#   -oo Y_POSSIBLE_NAMES=BEGIN_LAT
#
echo "[4/5] Converting to GeoParquet"
echo "🔄 Converting to GeoParquet with point geometry from BEGIN_LAT/BEGIN_LON..."
rm -f "$OUT_PARQUET"

ogr2ogr \
  -f "Parquet" \
  -progress \
  "$OUT_PARQUET" \
  "$RAW_CSV" \
  -oo AUTODETECT_TYPE=YES \
  -oo X_POSSIBLE_NAMES=BEGIN_LON \
  -oo Y_POSSIBLE_NAMES=BEGIN_LAT \
  -a_srs EPSG:4326


# -----------------------------------------------------------------------------
# Step 5: Build a GeoPackage for visual inspection in QGIS
# -----------------------------------------------------------------------------
# Convert this year's GeoParquet file to a GeoPackage for use in QGIS.
echo "[5/5] Building GeoPackage"
GPKG_FILE="storms_events_${YEAR}.gpkg"

echo ""
echo "📦 Building GeoPackage for QGIS ($GPKG_FILE)..."
rm -f "${PROCESSED_DIR}/${GPKG_FILE}"

echo "   Adding layer: storms_events_${YEAR}"
ogr2ogr \
    -f "GPKG" \
    -progress \
    "${PROCESSED_DIR}/${GPKG_FILE}" \
    "$OUT_PARQUET" \
    -nln "storms_events_${YEAR}"

GPKG_SIZE=$(du -m "${PROCESSED_DIR}/${GPKG_FILE}" | cut -f1)
echo "✅ Created ${PROCESSED_DIR}/${GPKG_FILE} (${GPKG_SIZE} MB, 1 layer)"

# --- Final summary --------------------------------------------------------
echo ""
echo "================================================================"
echo "  Summary"
echo "================================================================"
echo ""
echo "Files in ${PROCESSED_DIR}:"
ls -lh "${PROCESSED_DIR}"/*.parquet "${PROCESSED_DIR}"/*.gpkg
echo ""

# Verify the GeoPackage file with ogrinfo
echo "🔍 Verifying ${GPKG_FILE} with ogrinfo:"
ogrinfo -so "${PROCESSED_DIR}/${GPKG_FILE}" "storms_events_${YEAR}"
echo ""

echo "🎉 All done! 1 year of NOAA Storm Events data ready."


echo "   Open ${PROCESSED_DIR}/${GPKG_FILE} in QGIS to explore the data visually."

echo "Or open the Parquet file in DuckDB:"
echo "  duckdb -c \"INSTALL spatial; LOAD spatial; SELECT COUNT(*) FROM read_parquet('${OUT_PARQUET}');\""
echo "Enjoy your data! :)"

ELAPSED=$((SECONDS - START_TIME))
printf "⏱️  Total time: %02d:%02d (mm:ss)\n" $((ELAPSED / 60)) $((ELAPSED % 60))
