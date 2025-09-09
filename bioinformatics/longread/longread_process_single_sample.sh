#!/bin/bash

# --- process_longread_modified.sh ---
# Modified pipeline script to process a single bacterial Nanopore sample against a reference genome.
# It performs QC, filtering, alignment, and variant calling to produce a filtered VCF file.
# This version handles conda environment activation properly.

set -e # Exit immediately if a command exits with a non-zero status.

# --- CONDA SETUP ---
# Source conda to make it available in this script
source ~/miniforge3/etc/profile.d/conda.sh

# --- USER-DEFINED VARIABLES ---

# Get the path to the sample directory from the first command-line argument.
# E.g., ~/data/HaslamNanoporeSeq/Haslam-Control-1
SAMPLE_DIR=$1

# Get the path to the reference genome FASTA file from the second argument.
# E.g., /bulkpool/reference_data/Nissel1917/genomic.fna
REFERENCE_GENOME=$2

# Get the number of threads to use (optional, defaults to 8)
THREADS=${3:-8}

# --- SCRIPT LOGIC ---

# 1. Validate input.
if [ -z "$SAMPLE_DIR" ] || [ -z "$REFERENCE_GENOME" ]; then
    echo "Usage: ./process_longread_modified.sh <path_to_sample_dir> <path_to_reference_fasta> [threads]"
    exit 1
fi

if [ ! -d "$SAMPLE_DIR" ]; then
    echo "ERROR: Sample directory not found at '$SAMPLE_DIR'"
    exit 1
fi

if [ ! -f "$REFERENCE_GENOME" ]; then
    echo "ERROR: Reference FASTA file not found at '$REFERENCE_GENOME'"
    exit 1
fi

# Check if reference genome is indexed, create index if not
if [ ! -f "${REFERENCE_GENOME}.fai" ]; then
    echo "-> Reference genome index not found. Creating index with samtools faidx..."
    # Activate environment for samtools
    conda activate nanopore-wgs
    samtools faidx "$REFERENCE_GENOME"
    conda deactivate
    echo "-> Reference genome index created: ${REFERENCE_GENOME}.fai"
fi

# Get a clean sample name from the directory path.
SAMPLE_NAME=$(basename "$SAMPLE_DIR")
echo "--- Processing Sample: $SAMPLE_NAME ---"
echo "-> Using $THREADS threads"

# Create an output directory for this sample's results.
OUTPUT_DIR="${SAMPLE_DIR}/analysis_output"
mkdir -p "$OUTPUT_DIR"
echo "-> Results will be saved in: $OUTPUT_DIR"

# --- STEP 1: Concatenate FASTQ Files ---
COMBINED_FASTQ="${OUTPUT_DIR}/${SAMPLE_NAME}.combined.fastq.gz"

echo "-> Step 1: Combining FASTQ files..."
# Check if combined file already exists and might be incomplete
if [ -f "$COMBINED_FASTQ" ]; then
    echo "   Removing existing combined file to avoid append issues..."
    rm -f "$COMBINED_FASTQ"
fi

# Find all fastq files (compressed or not), concatenate them
# Check for files EXCLUDING the analysis_output directory
if find "$SAMPLE_DIR" \( -name "*.fastq.gz" -o -name "*.fq.gz" \) ! -path "*/analysis_output/*" | head -1 | grep -q .; then
    # If we have compressed files, use zcat
    echo "   Found compressed FASTQ files"
    find "$SAMPLE_DIR" \( -name "*.fastq.gz" -o -name "*.fq.gz" \) ! -path "*/analysis_output/*" -exec zcat {} \; | gzip > "$COMBINED_FASTQ"
elif find "$SAMPLE_DIR" \( -name "*.fastq" -o -name "*.fq" \) ! -path "*/analysis_output/*" | head -1 | grep -q .; then
    # If we have uncompressed files, cat and compress
    echo "   Found uncompressed FASTQ files"
    find "$SAMPLE_DIR" \( -name "*.fastq" -o -name "*.fq" \) ! -path "*/analysis_output/*" -exec cat {} \; | gzip > "$COMBINED_FASTQ"
else
    echo "ERROR: No FASTQ files found in $SAMPLE_DIR (excluding analysis_output/)"
    exit 1
fi
echo "-> Combined FASTQ created: $COMBINED_FASTQ"

# --- STEP 2: Quality Control & Filtering ---
FILTERED_FASTQ="${OUTPUT_DIR}/${SAMPLE_NAME}.filtered.fastq.gz"
QC_DIR="${OUTPUT_DIR}/qc"
mkdir -p "$QC_DIR"

echo "-> Step 2: Quality control and filtering..."
echo "   Activating nanopore-qc environment..."
conda activate nanopore-qc

# Run NanoPlot for QC visualization
echo "   Running NanoPlot for quality assessment..."
NanoPlot --fastq "$COMBINED_FASTQ" \
    --outdir "$QC_DIR" \
    --prefix "${SAMPLE_NAME}_" \
    --plots hex dot \
    --N50 \
    --threads $((THREADS / 4))

# Filter reads with Filtlong
echo "   Filtering reads with Filtlong (min length 1000bp, keep best 90%)..."
filtlong --min_length 1000 \
    --keep_percent 90 \
    --target_bases 500000000 \
    "$COMBINED_FASTQ" | gzip > "$FILTERED_FASTQ"

echo "   QC reports saved to: $QC_DIR"

# --- STEP 3: Alignment ---
echo "-> Step 3: Aligning reads to reference with Minimap2..."
echo "   Activating nanopore-wgs environment..."
conda activate nanopore-wgs

SORTED_BAM="${OUTPUT_DIR}/${SAMPLE_NAME}.sorted.bam"

# Run minimap2 alignment with appropriate settings for ONT data
minimap2 -ax map-ont -t $THREADS "$REFERENCE_GENOME" "$FILTERED_FASTQ" | \
    samtools view -bS -@ $((THREADS / 2)) - | \
    samtools sort -@ $((THREADS / 2)) -o "$SORTED_BAM"

echo "-> Indexing BAM file..."
samtools index "$SORTED_BAM"

# Generate alignment statistics
echo "-> Generating alignment statistics..."
samtools flagstat "$SORTED_BAM" > "${OUTPUT_DIR}/${SAMPLE_NAME}.flagstat.txt"
samtools depth "$SORTED_BAM" | awk '{sum+=$3} END {print "Average coverage:", sum/NR}' > "${OUTPUT_DIR}/${SAMPLE_NAME}.coverage.txt"

# --- STEP 4: Variant Calling & Filtering ---
RAW_VCF="${OUTPUT_DIR}/${SAMPLE_NAME}.raw.vcf.gz"
FILTERED_VCF="${OUTPUT_DIR}/${SAMPLE_NAME}.filtered.vcf.gz"

echo "-> Step 4a: Calling variants with Clair3..."
echo "   Switching to clair3-env environment..."
conda deactivate
conda activate clair3-env

# Create output directory for Clair3
CLAIR3_OUTPUT="${OUTPUT_DIR}/clair3_output"
mkdir -p "$CLAIR3_OUTPUT"

# Run Clair3 with the correct script name and parameters
# Note: Adjust model path based on your installation
run_clair3.sh \
    --bam_fn="$SORTED_BAM" \
    --ref_fn="$REFERENCE_GENOME" \
    --threads=$THREADS \
    --platform="ont" \
    --model_path="/home/david/miniforge3/envs/clair3-env/bin/models/ont" \
    --output="$CLAIR3_OUTPUT" \
    --sample_name="$SAMPLE_NAME" \
    --include_all_ctgs \
    --haploid_sensitive

# Check if Clair3 output exists and move it
if [ -f "${CLAIR3_OUTPUT}/merge_output.vcf.gz" ]; then
    mv "${CLAIR3_OUTPUT}/merge_output.vcf.gz" "$RAW_VCF"
    mv "${CLAIR3_OUTPUT}/merge_output.vcf.gz.tbi" "$RAW_VCF.tbi"
else
    echo "ERROR: Clair3 output not found. Check ${CLAIR3_OUTPUT} for details."
    exit 1
fi

echo "-> Step 4b: Filtering variants with BCFtools..."
echo "   Switching back to nanopore-wgs environment..."
conda deactivate
conda activate nanopore-wgs

# Filter variants for high confidence calls
# For bacterial (haploid) genomes, we want high VAF
# Check if the raw VCF has any variants first
RAW_COUNT=$(bcftools view -H "$RAW_VCF" 2>/dev/null | wc -l)
if [ "$RAW_COUNT" -eq 0 ]; then
    echo "   Warning: No variants found in raw VCF file"
    cp "$RAW_VCF" "$FILTERED_VCF"
    cp "${RAW_VCF}.tbi" "${FILTERED_VCF}.tbi"
else
    # Apply filters - use FORMAT/DP instead of INFO/DP for Clair3 output
    bcftools view -i 'QUAL > 20 && FORMAT/DP[0] > 10 && FORMAT/AF[0] > 0.8' "$RAW_VCF" | \
        bgzip > "$FILTERED_VCF"
    tabix "$FILTERED_VCF"
fi

# Generate variant statistics
echo "-> Generating variant statistics..."
FILTERED_COUNT=$(bcftools view -H "$FILTERED_VCF" 2>/dev/null | wc -l)
if [ "$FILTERED_COUNT" -gt 0 ]; then
    bcftools stats "$FILTERED_VCF" > "${OUTPUT_DIR}/${SAMPLE_NAME}.vcf_stats.txt"
    echo "Total variants called: $FILTERED_COUNT" >> "${OUTPUT_DIR}/${SAMPLE_NAME}.vcf_stats.txt"
else
    echo "No variants found in filtered VCF" > "${OUTPUT_DIR}/${SAMPLE_NAME}.vcf_stats.txt"
fi
echo "   Raw variants: $RAW_COUNT"
echo "   Filtered variants: $FILTERED_COUNT"

echo
echo "--- SUCCESS! ---"
echo "Processing for sample $SAMPLE_NAME is complete."
echo "Results summary:"
echo "  - Aligned BAM: $SORTED_BAM"
echo "  - Raw VCF: $RAW_VCF"
echo "  - Filtered VCF: $FILTERED_VCF"
echo "  - QC reports: ${QC_DIR}"
echo "  - Statistics: ${OUTPUT_DIR}/*.txt"