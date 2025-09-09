#!/bin/bash

# --- run_all_samples_optimized.sh ---
# Optimized batch processing for high-core systems
# Configured for 128 threads total

set -e

# === SYSTEM CONFIGURATION ===
TOTAL_THREADS=128
TOTAL_SAMPLES=6

# === PROCESSING STRATEGIES ===
# Strategy 1: Maximum parallelism (all samples at once, moderate threads each)
PARALLEL_ALL_THREADS=$((TOTAL_THREADS / TOTAL_SAMPLES))  # ~21 threads per sample

# Strategy 2: Balanced (3 samples at a time, more threads each)
BALANCED_PARALLEL_JOBS=3
BALANCED_THREADS=$((TOTAL_THREADS / BALANCED_PARALLEL_JOBS))  # ~42 threads per sample

# Strategy 3: Speed priority (2 samples at a time, maximum threads)
SPEED_PARALLEL_JOBS=2
SPEED_THREADS=$((TOTAL_THREADS / SPEED_PARALLEL_JOBS))  # 64 threads per sample

# === USER CONFIGURATION ===
REFERENCE_GENOME="/bulkpool/reference_data/Nissel1917/ncbi_dataset/data/GCF_000714595.1/GCF_000714595.1_ASM71459v1_genomic.fna"

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROCESS_SCRIPT="${SCRIPT_DIR}/longread_process_single_sample.sh"

# Check requirements
if [ ! -f "$PROCESS_SCRIPT" ]; then
    echo "ERROR: Processing script not found at $PROCESS_SCRIPT"
    exit 1
fi

if [ ! -f "$REFERENCE_GENOME" ]; then
    echo "ERROR: Reference genome not found at $REFERENCE_GENOME"
    exit 1
fi

# Function to process a single sample
process_sample() {
    local sample_dir=$1
    local threads=$2
    local sample_name=$(basename "$sample_dir")
    local log_file="${sample_dir}/processing_main.log"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting $sample_name with $threads threads"
    
    if "$PROCESS_SCRIPT" "$sample_dir" "$REFERENCE_GENOME" "$threads" &> "$log_file"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Completed $sample_name"
        return 0
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Failed $sample_name (see $log_file)"
        return 1
    fi
}

# Main execution
clear
echo "================================================"
echo "   Optimized Batch Processing for 128 Threads"
echo "================================================"
echo "System: $TOTAL_THREADS threads available"
echo "Reference: $(basename $REFERENCE_GENOME)"
echo "Script directory: $SCRIPT_DIR"
echo ""

# Find all sample directories
SAMPLE_DIRS=($(find "$SCRIPT_DIR" -maxdepth 1 -type d -name "Haslam-*" | sort))

if [ ${#SAMPLE_DIRS[@]} -eq 0 ]; then
    echo "ERROR: No sample directories found"
    exit 1
fi

echo "Found ${#SAMPLE_DIRS[@]} samples:"
for dir in "${SAMPLE_DIRS[@]}"; do
    echo "  • $(basename $dir)"
done
echo ""

echo "Select processing strategy:"
echo ""
echo "  1) MAXIMUM PARALLELISM - All 6 samples simultaneously"
echo "     → ${PARALLEL_ALL_THREADS} threads per sample"
echo "     → Best for: Similar sample sizes, maximum throughput"
echo ""
echo "  2) BALANCED - 3 samples at a time"
echo "     → ${BALANCED_THREADS} threads per sample"
echo "     → Best for: Mixed sample sizes, good balance"
echo ""
echo "  3) SPEED PRIORITY - 2 samples at a time"
echo "     → ${SPEED_THREADS} threads per sample"
echo "     → Best for: Large samples, fastest per-sample completion"
echo ""
echo "  4) CUSTOM - Specify your own configuration"
echo ""
echo "  5) EXIT"
echo ""
read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        MAX_PARALLEL_JOBS=6
        THREADS_PER_SAMPLE=$PARALLEL_ALL_THREADS
        echo "Using MAXIMUM PARALLELISM: 6 jobs × $THREADS_PER_SAMPLE threads"
        ;;
    2)
        MAX_PARALLEL_JOBS=$BALANCED_PARALLEL_JOBS
        THREADS_PER_SAMPLE=$BALANCED_THREADS
        echo "Using BALANCED: $MAX_PARALLEL_JOBS jobs × $THREADS_PER_SAMPLE threads"
        ;;
    3)
        MAX_PARALLEL_JOBS=$SPEED_PARALLEL_JOBS
        THREADS_PER_SAMPLE=$SPEED_THREADS
        echo "Using SPEED PRIORITY: $MAX_PARALLEL_JOBS jobs × $THREADS_PER_SAMPLE threads"
        ;;
    4)
        read -p "Number of parallel jobs (1-6): " MAX_PARALLEL_JOBS
        read -p "Threads per sample: " THREADS_PER_SAMPLE
        TOTAL_USED=$((MAX_PARALLEL_JOBS * THREADS_PER_SAMPLE))
        echo "Custom configuration: $MAX_PARALLEL_JOBS jobs × $THREADS_PER_SAMPLE threads = $TOTAL_USED threads total"
        if [ $TOTAL_USED -gt $TOTAL_THREADS ]; then
            echo "WARNING: This will use more threads than available!"
            read -p "Continue anyway? (y/n): " confirm
            if [ "$confirm" != "y" ]; then
                exit 0
            fi
        fi
        ;;
    5)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "Starting processing..."
echo "================================================"
START_TIME=$(date +%s)

# Export functions and variables for parallel execution
export -f process_sample
export PROCESS_SCRIPT REFERENCE_GENOME

# Process samples with GNU parallel if available
if command -v parallel &> /dev/null; then
    printf '%s\n' "${SAMPLE_DIRS[@]}" | \
        parallel -j $MAX_PARALLEL_JOBS --eta --bar \
        process_sample {} $THREADS_PER_SAMPLE
else
    # Fallback to background jobs
    echo "Processing with background jobs (install GNU parallel for progress bar)..."
    
    JOB_COUNT=0
    for sample_dir in "${SAMPLE_DIRS[@]}"; do
        # Wait if we've reached max parallel jobs
        while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL_JOBS ]; do
            sleep 2
        done
        
        process_sample "$sample_dir" "$THREADS_PER_SAMPLE" &
        JOB_COUNT=$((JOB_COUNT + 1))
        echo "Started job $JOB_COUNT/6: $(basename $sample_dir)"
    done
    
    echo ""
    echo "Waiting for all jobs to complete..."
    wait
fi

# Calculate runtime
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))
RUNTIME_MIN=$((RUNTIME / 60))
RUNTIME_SEC=$((RUNTIME % 60))

# Final summary
echo ""
echo "================================================"
echo "           Processing Complete"
echo "================================================"

# Count successful samples
SUCCESS_COUNT=0
FAILED_SAMPLES=()
for sample_dir in "${SAMPLE_DIRS[@]}"; do
    if [ -f "${sample_dir}/analysis_output/$(basename $sample_dir).filtered.vcf.gz" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAILED_SAMPLES+=("$(basename $sample_dir)")
    fi
done

echo "Runtime: ${RUNTIME_MIN}m ${RUNTIME_SEC}s"
echo "Success: $SUCCESS_COUNT/${#SAMPLE_DIRS[@]} samples"

if [ ${#FAILED_SAMPLES[@]} -gt 0 ]; then
    echo ""
    echo "Failed samples:"
    for sample in "${FAILED_SAMPLES[@]}"; do
        echo "  ✗ $sample"
    done
fi

echo ""
echo "Results location: */analysis_output/"
echo ""

# Show summary statistics if all succeeded
if [ $SUCCESS_COUNT -eq ${#SAMPLE_DIRS[@]} ]; then
    echo "Quick statistics summary:"
    echo "------------------------"
    for sample_dir in "${SAMPLE_DIRS[@]}"; do
        sample_name=$(basename "$sample_dir")
        if [ -f "${sample_dir}/analysis_output/${sample_name}_summary.txt" ]; then
            echo ""
            echo "[$sample_name]"
            grep -E "Filtered variants:|mapped \(" "${sample_dir}/analysis_output/${sample_name}_summary.txt" | head -2
        fi
    done
fi