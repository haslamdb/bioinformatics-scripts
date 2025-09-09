#!/bin/bash
#
# ==============================================================================
# Standalone InSilicoSeq Simulation Script
# ==============================================================================
#
# Description:
# This script generates a simulated metagenomic dataset using InSilicoSeq.
# It is designed to be run after the main benchmarking environment has been
# set up and the 'insilicoseq' conda environment exists.
#
# Author: Gemini
# Date: 2025-08-01
#
# To Run:
# 1. Save this file as 'run_simulation.sh'
# 2. Make it executable: chmod +x run_simulation.sh
# 3. Run it: ./run_simulation.sh
#
# ==============================================================================

# --- Configuration ---
# Stop the script if any command fails
set -e

# Define the base directories. These are assumed to be in your home directory.
# Your symlinks for data, databases, etc., will be respected.
BASE_DIR="$HOME"
ENV_DIR="$BASE_DIR/environments"
DATA_DIR="$BASE_DIR/sequence_data"

# --- Banner ---
echo "======================================================"
echo "Starting InSilicoSeq Metagenome Simulation"
echo "======================================================"
echo "Using environment: $ENV_DIR/insilicoseq"
echo "Output directory:  $DATA_DIR/simulated_metagenome_novaseq"
echo "------------------------------------------------------"

# Ensure the output directory exists
mkdir -p "$DATA_DIR"

# --- Run Simulation ---
echo "--> Generating a simulated metagenome with InSilicoSeq (NovaSeq)..."
# This command simulates 10 million reads using the NovaSeq error model.
# The output will include a 'ground_truth.txt' file, which is crucial for
# benchmarking the accuracy of your EM algorithm.
# We use the iss command to generate simulated reads.
# First check if genomes exist to simulate from
if [ ! -d "$BASE_DIR/databases/refseq" ]; then
    echo "Error: No reference genomes found. Using NCBI download option."
    "$ENV_DIR/insilicoseq/bin/iss" generate \
        --ncbi bacteria \
        --n_genomes_ncbi 500 \
        --model NovaSeq \
        --n_reads 10M \
        --output "$DATA_DIR/simulated_metagenome_10M_reads" \
        --cpus 48
else
    # Use existing genomes if available
    "$ENV_DIR/insilicoseq/bin/iss" generate \
        --genomes "$BASE_DIR/databases/refseq"/*.fna \
        --model NovaSeq \
        --n_reads 10M \
        --output "$DATA_DIR/simulated_metagenome_novaseq" \
        --cpus 48
fi

echo "--> Simulated data generated successfully in $DATA_DIR/simulated_metagenome_novaseq"
echo "======================================================"
echo "Simulation complete."
echo "======================================================"
