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

mkdir -p /local/code/images
mkdir -p /local/code/tmp

export TMPDIR=/local/code/tmp
export TEMP=/local/code/tmp
export TMP=/local/code/tmp

echo "Temporary Directory set to: $TMPDIR"

# --- 4. DOWNLOAD DATA ---
cd /local/code
echo "Downloading imagery..."
aws s3 sync s3://$BUCKET/$KEY/ images/ --no-progress
aws s3 cp s3://$BUCKET/settings.yaml .
aws s3 cp s3://$BUCKET/$KEY/settings.yaml . || true
aws s3 cp s3://$BUCKET/$KEY/boundary.json . || true
aws s3 cp s3://$BUCKET/$KEY/gcp_list.txt . || true

# Check for boundary file
BOUNDARY_ARG="--auto-boundary"
if test -f "/local/code/boundary.json"; then
    echo "Using custom boundary file."
    BOUNDARY_ARG="--boundary /local/code/boundary.json"
fi

# --- 5. EXECUTE ODM ---
cd /code

echo "Starting ODM run..."

python3 run.py --rerun-all $BOUNDARY_ARG \
    --project-path /local \
    2>&1 | tee /local/code/odm_process.log

# --- 6. UPLOAD RESULTS ---
echo "Run complete. Syncing results..."
cd /local/code

aws s3 sync . s3://$BUCKET/$KEY/$OUTPUT/ --exclude "*" --include "odm_*" --include "3d_tile*" --no-progress || true
aws s3 cp odm_process.log s3://$BUCKET/$KEY/$OUTPUT/odm_process.log || true

echo "Job Complete."