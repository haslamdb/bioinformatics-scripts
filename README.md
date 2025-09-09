# Bioinformatics Scripts

A collection of bioinformatics pipeline scripts for processing sequencing data.

## Directory Structure

```
bioinformatics/
├── longread/       # Nanopore long-read processing scripts
├── shortread/      # Illumina short-read processing scripts  
├── assembly/       # Assembly tools (Unicycler, etc.)
└── utils/          # Utility scripts
```

## Long-Read Processing Scripts

### longread_process_single_sample.sh
Processes a single bacterial Nanopore sample against a reference genome.
- Performs QC and filtering
- Alignment with minimap2
- Variant calling with Clair3
- Produces filtered VCF files

**Usage:**
```bash
./longread_process_single_sample.sh <sample_dir> <reference_fasta> [threads]
```

### longread_batch_processor.sh
Batch processing script optimized for high-core systems.
- Processes multiple samples in parallel
- Configurable threading strategies
- Automatic resource management

**Usage:**
```bash
./longread_batch_processor.sh
```

## Requirements

- Conda/Mamba with the following environments:
  - `nanopore-qc`: QC and filtering tools
  - `nanopore-wgs`: Alignment and variant tools  
  - `clair3-env`: Clair3 variant caller

## Reference Genomes

Reference genomes should be stored in `/bulkpool/reference_data/`