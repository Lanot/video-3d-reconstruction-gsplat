#!/bin/bash
#
# video_to_gsplat.sh
#
# Author: Nandan Manjunatha nannigalaxy@gmail.com
# License: MIT
# Description:
#   This script extracts frames from a video at a specified FPS,
#   runs Structure-from-Motion (SfM) using COLMAP, and then trains Speedy-Splat model.
#
# Usage:
#   ./video_to_gsplat.sh <fps> <input_video_path> <sfm_output_dir> <gsplat_output_dir_path> [--disable_gpu]
#

# Check if enough arguments are passed
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <fps> <input_video_path> <sfm_output_dir> <gsplat_output_dir_path> [--disable_gpu]"
    exit 1
fi

# Reject flags in place of the 4 required positional arguments
for arg in "$1" "$2" "$3" "$4"; do
    case "$arg" in
        --*) echo "Missing positional argument (got option '$arg')."
             echo "Usage: $0 <fps> <input_video_path> <sfm_output_dir> <gsplat_output_dir_path> [--disable_gpu]"
             exit 1 ;;
    esac
done

# Read command-line arguments
FPS="$1"
INPUT_VIDEO="$2"
SFM_OUTPUT_DIR="$3"
GSPLAT_OUTPUT_DIR="$4"
shift 4

GPU_FLAG=""        # Default: GPU enabled (pass --disable_gpu to run on CPU)
EXHAUSTIVE_FLAG="" # Default: sequential matching
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --disable_gpu) GPU_FLAG="--disable_gpu" ;;
        --exhaustive) EXHAUSTIVE_FLAG="--exhaustive" ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Locate sibling scripts relative to this script, so the pipeline works from any
# CWD while user-supplied paths stay relative to the caller's CWD.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Stop immediately if any step fails
set -e

# Create necessary directories
mkdir -p "$SFM_OUTPUT_DIR/images"

###########################################
# Step 1: Extract Frames from Video
###########################################
echo "Extracting frames from video at $FPS FPS..."
# Remove frames from any previous run, otherwise a lower FPS leaves stale
# higher-numbered frames behind and COLMAP reconstructs a mix of two extractions.
rm -f "$SFM_OUTPUT_DIR/images"/frame_*.png
ffmpeg -y -i "$INPUT_VIDEO" -vf "fps=$FPS" "$SFM_OUTPUT_DIR/images/frame_%04d.png"

###########################################
# Step 2: Run COLMAP SfM and Export Undistorted Model
###########################################
echo "Running COLMAP SfM pipeline..."
# Unquoted on purpose: the flags are empty unless set, and must not become empty args.
"$SCRIPT_DIR/colmap_undistorted_sfm_export.sh" "$SFM_OUTPUT_DIR/images" "$SFM_OUTPUT_DIR" $GPU_FLAG $EXHAUSTIVE_FLAG

###########################################
# Step 3: Train GSplat Model
###########################################
echo "Training 3D GS..."

"$SCRIPT_DIR/train_speedy_splat.sh" "$SFM_OUTPUT_DIR/undistorted" "$GSPLAT_OUTPUT_DIR"
