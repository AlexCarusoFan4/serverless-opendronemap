#!/bin/bash

handle_error() {
    echo "!!! JOB FAILED !!!"
    df -h
    echo "Diagnostic: Directory Contents"
    ls -al /local/code
    echo "SLEEPING 2 HOURS FOR DEBUGGING..."
    sleep 7200
    exit 1
}

trap 'handle_error' ERR

echo "Launching Serverless OpenDroneMap"

# --- 1. WAIT FOR HOST ---
echo "Waiting for Host signal..."
while [ ! -f /local/host_ready.txt ]; do
    sleep 5
done

# --- 3. CONFIGURE PATHS ---
BUCKET="$4"
KEY="$5"
OUTPUT="$6"

# Ensure clean slate
rm -rf /local/code

mkdir -p /local/code/images
mkdir -p /local/code/tmp

export TMPDIR=/local/code/tmp
export TEMP=/local/code/tmp
export TMP=/local/code/tmp

echo "Temporary Directory set to: $TMPDIR"

# --- 4. DOWNLOAD DATA ---
cd /local/code
echo "Downloading imagery..."
aws s3 sync s3://$BUCKET/$KEY/ images/ --delete --exclude "progress.json" --no-progress
aws s3 cp s3://$BUCKET/settings.yaml . || true
aws s3 cp s3://$BUCKET/$KEY/settings.yaml . || true
aws s3 cp s3://$BUCKET/$KEY/boundary.json . || true
aws s3 cp s3://$BUCKET/$KEY/gcp_list.txt . || true

# Strip proprietary MakerNotes to avoid exifread crashing on malformed DJI blobs.
# MakerNotes are not used by ODM (GPS/focal length are standard EXIF; RTK is XMP).
# -overwrite_original is required so exiftool does NOT leave *_original backups
# that ODM would then try to load as images.
echo "Stripping MakerNotes from imagery..."
exiftool -MakerNotes= -overwrite_original -q -r /local/code/images/ || true

# Check for boundary file
BOUNDARY_ARG="--auto-boundary"
if test -f "/local/code/boundary.json"; then
    echo "Using custom boundary file."
    BOUNDARY_ARG="--boundary /local/code/boundary.json"
fi

# --- 5. EXECUTE ODM ---
cd /code

# Patch ODM 3.5.6 boundary.py: CRS.from_proj4() rejects authority codes (EPSG:4326,
# OGC:CRS84) returned by newer fiona. CRS.from_user_input() handles all formats.
sed -i 's/CRS\.from_proj4(fiona\.crs\.to_string(src\.crs))/CRS.from_user_input(fiona.crs.to_string(src.crs))/g' /code/opendm/boundary.py

# Parse YAML to CLI arguments
echo "Parsing settings.yaml into command line arguments..."
YAML_ARGS=""
if test -f "/local/code/settings.yaml"; then
    YAML_ARGS=$(python3 -c "
import yaml
try:
    with open('/local/code/settings.yaml') as f:
        d = yaml.safe_load(f) or {}
    args = []
    for k, v in d.items():
        k_arg = k.replace('_', '-')
        if str(v).lower() == 'true':
            args.append(f'--{k_arg}')
        elif str(v).lower() == 'false':
            continue  # Omit flag entirely if false
        else:
            args.append(f'--{k_arg} {v}')
    print(' '.join(args))
except Exception as e:
    print(f'') # Fail silently on python side, handled by bash
")
    echo "Parsed arguments: $YAML_ARGS"
else
    echo "No settings.yaml found, proceeding with defaults."
fi

echo "Starting ODM run..."

# Inject the parsed $YAML_ARGS directly into the python3 execution
python3 run.py --rerun-all $BOUNDARY_ARG $YAML_ARGS \
    --project-path /local \
    2>&1 | tee /local/code/odm_process.log

# --- 6. UPLOAD RESULTS ---
echo "Run complete. Syncing results..."
cd /local/code

aws s3 sync . s3://$BUCKET/$KEY/$OUTPUT/ --exclude "*" --include "odm_*" --include "3d_tile*" --no-progress || true
aws s3 cp odm_process.log s3://$BUCKET/$KEY/$OUTPUT/odm_process.log || true

echo "Job Complete."