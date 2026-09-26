#!/bin/bash
#
# colmap_undistorted_sfm_export.sh
#
# Author: Nandan Manjunatha nannigalaxy@gmail.com
# License: MIT
# Description: 
#   This script automates the COLMAP pipeline for feature extraction, matching,
#   sparse reconstruction, image undistortion, and model export.
#
# Usage:
#   ./colmap_undistorted_sfm_export.sh <input_images> <output_dir> [--exhaustive] [--disable_gpu]
#

# Check if minimum required arguments are passed
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <input_images> <output_dir> [--exhaustive] [--disable_gpu]"
    exit 1
fi

# Read required arguments
INPUT_IMAGES=$1
OUTPUT_DIR=$2

# Default values
MATCHER_MODE="sequence"  # Default matcher mode
ENABLE_GPU="1"           # Default: GPU enabled

# Parse optional arguments
shift 2
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --exhaustive) MATCHER_MODE="exhaustive" ;;  # Use exhaustive matching
        --disable_gpu) ENABLE_GPU="0" ;;            # Run COLMAP on CPU
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Paths
DATABASE_PATH="$OUTPUT_DIR/database.db"
SPARSE_DIR="$OUTPUT_DIR/sparse"
UNDISTORTED_DIR="$OUTPUT_DIR/undistorted"

# Create output directories
mkdir -p "$OUTPUT_DIR"

###########################################
# Step 1: Feature Extraction
###########################################
echo "Running feature extraction (GPU enabled: $ENABLE_GPU)..."
colmap feature_extractor \
    --FeatureExtraction.use_gpu=$ENABLE_GPU \
    --database_path "$DATABASE_PATH" \
    --image_path "$INPUT_IMAGES"

if [ $? -ne 0 ]; then
    echo "ERROR: colmap feature_extractor failed. If no CUDA-capable GPU is available, re-run with --disable_gpu."
    exit 1
fi

###########################################
# Step 2: Feature Matching
###########################################
if [ "$MATCHER_MODE" == "exhaustive" ]; then
    echo "Running exhaustive matcher (GPU enabled: $ENABLE_GPU)..."
    colmap exhaustive_matcher \
        --FeatureMatching.use_gpu=$ENABLE_GPU \
        --database_path "$DATABASE_PATH"
else
    echo "Running sequence matcher (GPU enabled: $ENABLE_GPU)..."
    colmap sequential_matcher \
        --FeatureMatching.use_gpu=$ENABLE_GPU \
        --database_path "$DATABASE_PATH"
fi

if [ $? -ne 0 ]; then
    echo "ERROR: colmap matcher failed. If no CUDA-capable GPU is available, re-run with --disable_gpu."
    exit 1
fi

###########################################
# Step 3: Sparse 3D Reconstruction
###########################################
mkdir -p "$SPARSE_DIR"
colmap mapper \
    --database_path "$DATABASE_PATH" \
    --image_path "$INPUT_IMAGES" \
    --output_path "$SPARSE_DIR"

if [ $? -ne 0 ] || [ ! -d "$SPARSE_DIR/0" ]; then
    echo "ERROR: colmap mapper failed to reconstruct a sparse model (no $SPARSE_DIR/0)."
    echo "This usually means too few feature matches were found (e.g. insufficient overlap between frames, or feature_extractor/matcher silently failed)."
    exit 1
fi

# The mapper emits 0/, 1/, ... when tracking breaks; only sparse/0 is used below,
# and it is not necessarily the largest model.
NUM_MODELS=$(find "$SPARSE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
if [ "$NUM_MODELS" -gt 1 ]; then
    echo "WARNING: colmap mapper produced $NUM_MODELS separate models in $SPARSE_DIR."
    echo "Only sparse/0 will be used, which may cover a fraction of the frames."
    echo "Consider re-running with --exhaustive, or extracting frames at a higher FPS for more overlap."
fi

###########################################
# Step 4: Undistort Images
###########################################
mkdir -p "$UNDISTORTED_DIR"
colmap image_undistorter \
    --image_path "$INPUT_IMAGES" \
    --input_path "$SPARSE_DIR/0" \
    --output_path "$UNDISTORTED_DIR" \
    --output_type COLMAP

if [ $? -ne 0 ]; then
    echo "ERROR: colmap image_undistorter failed."
    exit 1
fi

###########################################
# Step 5: Check and Fix Sparse Directory
###########################################
if [ ! -d "$UNDISTORTED_DIR/sparse/0" ]; then
    echo "sparse/0 not found, checking if sparse/ has data..."

    if [ -f "$UNDISTORTED_DIR/sparse/cameras.bin" ] && \
       [ -f "$UNDISTORTED_DIR/sparse/images.bin" ] && \
       [ -f "$UNDISTORTED_DIR/sparse/points3D.bin" ]; then
        echo "Moving existing sparse/ data into sparse/0/..."
        mkdir -p "$UNDISTORTED_DIR/sparse/0"
        if ! mv "$UNDISTORTED_DIR/sparse/cameras.bin" "$UNDISTORTED_DIR/sparse/images.bin" "$UNDISTORTED_DIR/sparse/points3D.bin" "$UNDISTORTED_DIR/sparse/0/"; then
            echo "ERROR: Failed to move sparse model files into sparse/0/."
            exit 1
        fi
        echo "Moved data into sparse/0/"
    else
        echo "ERROR: No complete model found in $UNDISTORTED_DIR/sparse/ (expected cameras.bin, images.bin, points3D.bin)."
        echo "Undistortion might have failed or produced only a partial model."
        exit 1
    fi
fi

###########################################
# Optional for debugging
###########################################
# These exports are for inspection only; a failure here must not fail the
# pipeline, since undistorted/sparse/0 is already complete and usable.
mkdir -p "$OUTPUT_DIR/custom_export"

# Export model to PLY
colmap model_converter \
    --input_path "$UNDISTORTED_DIR/sparse/0" \
    --output_path "$OUTPUT_DIR/custom_export/scene.ply" \
    --output_type PLY || echo "WARNING: debug PLY export failed (continuing)."

# Export model to TXT
colmap model_converter \
    --input_path "$UNDISTORTED_DIR/sparse/0" \
    --output_path "$OUTPUT_DIR/custom_export" \
    --output_type TXT || echo "WARNING: debug TXT export failed (continuing)."

exit 0
