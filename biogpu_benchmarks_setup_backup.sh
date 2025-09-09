#!/bin/bash
#
# ==============================================================================
# Benchmarking Environment Setup Script for BioGPU Project
# ==============================================================================
#
# Description:
# This script automates the download and setup of common bioinformatics tools,
# reference databases, and test datasets for benchmarking against BioGPU.
#
# It uses mamba (from your miniforge3 installation) for fast and robust
# environment management. Each tool or pipeline is installed in a separate
# conda environment to prevent dependency conflicts.
#
# Author: Gemini
# Date: 2025-08-01
#
# ==============================================================================

# --- Configuration ---
# Stop the script if any command fails
set -e

# Define the base directories based on your provided structure.
# The script assumes it is being run from your home directory `~`.
# If not, you may need to adjust the paths.
BASE_DIR="$HOME"
CODE_DIR="$BASE_DIR/code"
ENV_DIR="$BASE_DIR/environments"
DB_DIR="$BASE_DIR/databases"
DATA_DIR="$BASE_DIR/sequence_data"
SCRIPTS_DIR="$BASE_DIR/scripts"

# --- Banner ---
echo "======================================================"
echo "Starting Bioinformatics Benchmarking Environment Setup"
echo "======================================================"
echo "Using the following directories:"
echo "Code:       $CODE_DIR"
echo "Environments: $ENV_DIR"
echo "Databases:  $DB_DIR"
echo "Data:       $DATA_DIR"
echo "------------------------------------------------------"

# --- 1. Tool Installation ---
echo "[Step 1/4] Installing bioinformatics software..."

# Ensure the environments directory exists
mkdir -p "$ENV_DIR"

# A. SRA Toolkit for downloading data
echo "--> Installing SRA Toolkit..."
mamba create -p "$ENV_DIR/sra-tools" -c bioconda -c conda-forge sra-tools -y

# B. BWA-MEM2 (fast aligner)
echo "--> Installing BWA-MEM2 and Samtools..."
mamba create -p "$ENV_DIR/bwa-mem2" -c bioconda -c conda-forge bwa-mem2 samtools -y

# C. Bowtie2 (another popular aligner)
echo "--> Installing Bowtie2..."
mamba create -p "$ENV_DIR/bowtie2" -c bioconda -c conda-forge bowtie2 samtools -y

# D. AMRFinderPlus (NCBI's AMR tool)
echo "--> Installing AMRFinderPlus..."
mamba create -p "$ENV_DIR/amrfinderplus" -c bioconda ncbi-amrfinderplus -y

# E. RGI / CARD (Comprehensive Antibiotic Resistance Database tools)
echo "--> Installing RGI..."
mamba create -p "$ENV_DIR/rgi" -c bioconda -c conda-forge rgi -y

# F. InSilicoSeq (for simulating metagenomes with ground truth)
echo "--> Installing InSilicoSeq..."
mamba create -p "$ENV_DIR/insilicoseq" -c bioconda -c conda-forge insilicoseq -y

echo "[Step 1/4] Software installation complete."
echo "------------------------------------------------------"


# --- 2. Database Download ---
echo "[Step 2/4] Downloading reference AMR databases..."

# Ensure the databases directory exists
mkdir -p "$DB_DIR"
cd "$DB_DIR"

# A. Download and set up AMRFinderPlus database
echo "--> Downloading AMRFinderPlus database..."
# First, activate the environment to use its 'amrfinder' command
source "$BASE_DIR/miniforge3/etc/profile.d/conda.sh"
conda activate "$ENV_DIR/amrfinderplus"
# Download/update the database
amrfinder -u
conda deactivate

# B. Download and set up CARD database for RGI
echo "--> Downloading CARD database for RGI..."
conda activate "$ENV_DIR/rgi"
rgi main --clean
rgi load --card_json "$DB_DIR/card.json" --local
conda deactivate

echo "[Step 2/4] Database download complete."
echo "------------------------------------------------------"


# --- 3. Test Data Acquisition ---
echo "[Step 3/4] Acquiring test datasets..."

# Ensure the sequence data directory exists
mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

# A. Download a real human gut metagenome dataset from SRA
# This is a well-known dataset from the Human Microbiome Project
# SRR ID: SRS011061 (sample from the retroauricular crease)
# We will download a small subset for initial testing.
echo "--> Downloading real metagenome data from SRA (first 1M spots)..."
conda activate "$ENV_DIR/sra-tools"
prefetch --max-size 1G SRR341578 # A smaller gut metagenome sample
fastq-dump --split-files --gzip --readids --defline-qual '+' --defline-seq '@$ac.$si.$ri' SRR341578
conda deactivate
echo "--> Real data downloaded to $DATA_DIR/SRR341578"

# B. Generate a simulated dataset with known composition
echo "--> Generating a simulated metagenome with InSilicoSeq..."
conda activate "$ENV_DIR/insilicoseq"
# This command simulates 1 million reads from a default bacterial community.
# The output will include a 'ground_truth.txt' file, which is crucial for
# benchmarking the accuracy of your EM algorithm.
insilicoseq --preset miseq --n_reads 1M --output "$DATA_DIR/simulated_metagenome" --cpus 32
conda deactivate
echo "--> Simulated data generated in $DATA_DIR/simulated_metagenome"

echo "[Step 3/4] Test data acquisition complete."
echo "------------------------------------------------------"

# --- 4. Finalization ---
echo "[Step 4/4] Setup finished successfully!"
echo ""
echo "Next Steps:"
echo "1. Review the downloaded tools, databases, and data in their respective directories."
echo "2. Activate an environment using: conda activate $ENV_DIR/<env_name>"
echo "3. The next major task is to write a wrapper script in '$SCRIPTS_DIR' that:"
echo "   - Iterates through the test datasets."
echo "   - Runs each tool (BWA, Bowtie2, AMRFinder+, RGI, and your BioGPU) on the data."
echo "   - Logs the runtime, CPU usage, and memory usage (e.g., with /usr/bin/time -v)."
echo "   - Saves all output to the '$HOME/analysis' directory for comparison."
echo ""
echo "======================================================"

cd "$BASE_DIR"
