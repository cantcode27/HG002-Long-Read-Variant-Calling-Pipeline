# 🧬 HG002 Long-Read Variant Calling Pipeline

**A Containerized Nextflow Workflow for Detecting Genetic Variants — Executed on a SLURM HPC Cluster**

---

## Table of Contents

- [What Does This Pipeline Do?](#what-does-this-pipeline-do)
- [Background (For Non-Bioinformaticians)](#background-for-non-bioinformaticians)
- [Dataset](#dataset)
- [Tools & Versions](#tools--versions)
- [Pipeline Architecture](#pipeline-architecture)
- [HPC Execution Model](#hpc-execution-model)
- [Repository Structure](#repository-structure)
- [Step-by-Step Reproduction Guide](#step-by-step-reproduction-guide)
- [Final Successful Execution](#final-successful-execution)
- [Generated Outputs](#generated-outputs)
- [Debugging & Architectural Lessons](#debugging--architectural-lessons)
- [Academic Context](#academic-context)

---

## What Does This Pipeline Do?

This pipeline takes **raw DNA sequencing data** from a human genome sample and automatically:

1. **Aligns** the sequencing reads to a human reference genome (like matching puzzle pieces to a template)
2. **Processes** the alignment into an analysis-ready format
3. **Calls variants** — identifies positions where this individual's DNA differs from the reference genome (e.g., mutations, insertions, deletions)

All of this runs inside **software containers** (pre-packaged environments) on a **high-performance computing (HPC) cluster**, making the entire workflow **reproducible** — meaning anyone with the same setup can re-run it and get the same results.

---

## Background (For Non-Bioinformaticians)

If you're not familiar with genomics or bioinformatics, here's a quick primer on the key concepts used in this project:

### What is DNA Sequencing?

DNA sequencing is the process of reading the order of bases (A, T, C, G) in a person's genome. Modern sequencers produce millions of short "reads" — small fragments of the genome that must be computationally assembled and analyzed.

### What are "Long Reads"?

Traditional sequencing produces short reads (~150 bases). **PacBio HiFi** technology produces **long reads** (10,000–20,000 bases) with high accuracy. Longer reads make it easier to align to a reference and detect complex structural variants.

### What is Variant Calling?

Every human genome differs slightly from the reference genome. **Variant calling** is the process of identifying these differences — such as single-nucleotide changes (SNPs), small insertions, or deletions. These variants can be linked to diseases, traits, or population genetics.

### What is an HPC Cluster?

A **High-Performance Computing (HPC) cluster** is a group of powerful computers managed by a job scheduler (in our case, **SLURM**). Instead of running tasks on your laptop, you submit "jobs" that run on dedicated compute nodes with more memory, CPUs, and storage.

### What are Containers?

**Containers** (like Docker or Singularity) package software and all its dependencies into a portable, self-contained unit. This ensures that the pipeline behaves the same way on any machine — solving the classic "it works on my machine" problem.

### What is Nextflow?

**Nextflow** is a workflow manager designed for scientific computing. It lets you define a multi-step pipeline (align → sort → call variants) and handles parallelism, error recovery, and execution on HPC clusters automatically.

---

## Dataset

| Property | Detail |
|---|---|
| **Sample** | HG002 (NA24385) — a well-characterized human reference sample used globally for benchmarking |
| **Sequencing Type** | PacBio HiFi long reads |
| **Data Source** | [NHGRI Human Pangenome Project](https://humanpangenome.org/) (publicly available) |
| **Subsampling** | Original FASTQ was subsampled to **25%** using `seqtk` to reduce computation time |
| **Reference Genome** | hg38 (GRCh38) — the current standard human reference genome, downloaded from UCSC |

**Input files used in the pipeline:**

| File | Description | How to Obtain |
|---|---|---|
| `data/hg002_subset.fastq` | Subsampled PacBio HiFi reads | Download from the Human Pangenome Project, then subsample with `seqtk sample -s100 input.fastq 0.25 > hg002_subset.fastq` |
| `ref/hg38.fa` | Human reference genome (FASTA format) | Download from [UCSC Genome Browser](https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz) and decompress with `gunzip hg38.fa.gz` |

> **Note:** These files are too large to include in the repository. You must download them separately before running the pipeline — see the [Reproduction Guide](#step-by-step-reproduction-guide) below.

---

## Tools & Versions

All tools were run inside **Singularity containers** pulled from Docker registries. This means you don't need to install any bioinformatics software manually — just have Singularity available on your system and the containers will be pulled automatically.

| Tool | What It Does | Version | Container Source |
|---|---|---|---|
| **Nextflow** | Orchestrates the entire pipeline | 25.10.4 | Installed natively on the HPC |
| **minimap2** | Aligns sequencing reads to the reference genome | latest | `docker://quay.io/biocontainers/minimap2` |
| **samtools** | Converts, sorts, indexes, and generates statistics for alignment files | latest | `docker://quay.io/biocontainers/samtools` |
| **Clair3** | Deep learning-based variant caller optimized for long reads | latest | `docker://hkubal/clair3` |
| **Singularity** | Runs Docker containers on HPC systems (where Docker isn't allowed) | — | System module |
| **DeepVariant** |Deep neural nwtwork learning based next generation seuencing variant caller | latest | `docker://hkubal/deepvariant` |
---

## Pipeline Architecture

Below is a visual overview of the pipeline, followed by a detailed explanation of each step.

```
FASTQ reads ──→ [1. Index Reference] ──→ [2. Align Reads] ──→ [3. Sort & Convert]
                                                                       │
                                                                       ▼
                                              [5. Flagstat QC] ←── [4. Index BAM]
                                                                       │
                                                                       ▼
                                                              [6. Variant Calling]
                                                                       │
                                                                       ▼
                                                                 output.vcf
```

### Step 1 — Reference Indexing

```bash
samtools faidx hg38.fa
```

- **What it does:** Creates an index file (`.fai`) for the reference genome. Think of it like creating a table of contents for a book — it allows tools to quickly jump to specific chromosomal regions instead of reading the entire 3-billion-base-pair file from start to finish.
- **Output:** `hg38.fa.fai`

### Step 2 — Read Alignment

```bash
minimap2 -ax map-hifi hg38.fa reads.fastq
```

- **What it does:** Takes each sequencing read and finds where it best matches on the reference genome. Imagine you have thousands of puzzle pieces (reads) and a completed puzzle image (reference) — this step figures out where each piece belongs. The `-ax map-hifi` flag tells minimap2 that these are PacBio HiFi reads, so it uses the appropriate alignment parameters.
- **Output:** SAM file (human-readable alignment format)
- **SLURM script:** `Scripts/align.slurm`

### Step 3 — SAM → BAM Conversion & Sorting

```bash
samtools view -bS aligned.sam | samtools sort -o hg002.sorted.bam
```

- **What it does:** Converts the alignment from SAM (text format, very large ~894 MB) to BAM (binary, compressed ~325 MB), then sorts the reads by their position on the genome. Sorting is required by almost all downstream analysis tools.
- **Output:** `hg002.sorted.bam`

### Step 4 — BAM Indexing

```bash
samtools index hg002.sorted.bam
```

- **What it does:** Creates an index for the BAM file, enabling tools to quickly access reads at specific genomic locations without scanning the entire file. Similar to Step 1, but for the alignment file instead of the reference.
- **Output:** `hg002.sorted.bam.bai`

### Step 5 — Alignment Statistics (Quality Control)

```bash
samtools flagstat hg002.sorted.bam
```

- **What it does:** Generates a summary of alignment quality — how many reads were mapped successfully, how many failed, duplication rate, etc. This is a crucial sanity check to confirm the alignment worked correctly before proceeding to variant calling.
- **Output:** `hg002.flagstat.txt`

### Step 6 — Variant Calling 
**Clair3:**
- **What it does:** Clair3 uses a deep neural network to examine the aligned reads and identify positions where this individual's genome differs from the reference. It outputs a VCF (Variant Call Format) file — a standardized format that lists all detected variants with quality scores and metadata.
- **Output:** `clair3.vcf.gz (+ index .tbi)`
- Clair3 was run using containerized execution within SLURM.

 **DeepVariant:**
 
- **What it does:**   DeepVariant uses a deep learning model to convert aligned reads into candidate variant sites, then classifies each candidate as a SNP/INDEL with genotype likelihoods. It produces a VCF file containing short variants (SNVs and small INDELs) with quality and supporting annotations. DeepVariant is designed to generalize across sequencing technologies using pretrained models (here, long-read PacBio/HiFi mode).
  - **Output:** `deepvariant.vcf.gz (+ index .tbi)`
  - DeepVariant was run using containerized execution within SLURM.
---

## HPC Execution Model

### How Jobs Were Submitted

All processes were submitted through SLURM using:

```bash
sbatch Scripts/run_nf.slurm
```

Individual pipeline stages also have dedicated SLURM scripts for modular execution:

- `Scripts/idx_ref.slurm` — Reference indexing job
- `Scripts/align.slurm` — Read alignment job

### SLURM Job Configuration

The following resources were allocated for the pipeline:

```bash
#SBATCH -J a1_nf              # Job name
#SBATCH -p gpu                 # Partition (queue) to submit to
#SBATCH --cpus-per-task=8      # Number of CPU cores
#SBATCH --mem=24G              # Memory allocation
#SBATCH -t 03:30:00            # Maximum wall time (3 hours 30 minutes)
```

### Nextflow Configuration

In `Scripts/nextflow.config`, the following settings were used:

```groovy
executor = 'slurm'            // Submit each process as a SLURM job
singularity.enabled = true     // Use Singularity to run containers
autoMounts = true              // Automatically mount file paths into containers
```

Containers were cached locally to avoid re-downloading on subsequent runs.

---

## Repository Structure

```
a2/
│
├── README.md                          # This file — project documentation
├── .gitignore                         # Tells Git which large files to exclude
│
├── Scripts/
│   ├── main.nf                        # Nextflow DSL2 pipeline definition
│   ├── nextflow.config                # Nextflow + SLURM + Singularity configuration
│   ├── run_nf.slurm                   # Main SLURM submission script
│   ├── align.slurm                    # SLURM script for the alignment step
│   └── idx_ref.slurm                  # SLURM script for reference indexing
│
└── results/
    ├── hg002.flagstat.txt             # Alignment quality control statistics
    ├── hg38.fa.fai                    # Reference genome index (chromosome sizes)
    ├── nf_report.html                 # Nextflow execution report (open in browser)
    ├── nf_timeline.html               # Visual timeline of pipeline execution
    └── nf_trace.txt                   # Detailed resource usage log per process
```

> **Note:** Large files (BAM, SAM, FASTQ, reference genome, Singularity containers) are excluded via `.gitignore` as they are too large for GitHub. See the [Reproduction Guide](#step-by-step-reproduction-guide) for instructions on obtaining them.

---

## Step-by-Step Reproduction Guide

Follow these steps to reproduce the entire pipeline from scratch on any SLURM-managed HPC cluster.

### Prerequisites

Before starting, ensure you have the following available on your HPC system:

| Requirement | Minimum | How to Check |
|---|---|---|
| **SLURM** | Job scheduler must be available | `sinfo` should show partitions |
| **Singularity/Apptainer** | For running containerized tools | `singularity --version` |
| **Nextflow** | Version ≥ 25.x | `nextflow -version` |
| **CPUs** | ≥ 8 cores | Check with `nproc` |
| **RAM** | ≥ 24 GB | Check with `free -h` |
| **Disk Space** | ~50 GB free | Check with `df -h` |

> **Don't have Nextflow?** Install it with: `curl -s https://get.nextflow.io | bash`

### Step 1 — Clone the Repository

```bash
git clone <repo-url>
cd a2
```

### Step 2 — Download the Reference Genome

```bash
mkdir -p ref
cd ref
wget https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz
gunzip hg38.fa.gz
cd ..
```

### Step 3 — Download and Subsample the Sequencing Data

```bash
mkdir -p data

# Download HG002 PacBio HiFi reads from the Human Pangenome Project
# Visit https://humanpangenome.org/ to get the exact download URL
wget <HG002_PACBIO_HIFI_FASTQ_URL> -O data/hg002_full.fastq

# Subsample to 25% to reduce computation time
# The -s100 flag sets the random seed for reproducibility
seqtk sample -s100 data/hg002_full.fastq 0.25 > data/hg002_subset.fastq
```

> **Don't have seqtk?** Install it via conda: `conda install -c bioconda seqtk`

### Step 4 — Pull Singularity Containers

```bash
# These will be cached locally so they only download once
singularity pull docker://quay.io/biocontainers/minimap2
singularity pull docker://quay.io/biocontainers/samtools
singularity pull docker://hkubal/clair3
```

### Step 5 — Verify Directory Structure

Your project directory should look like this before running:

```
a2/
├── Scripts/
│   ├── main.nf
│   ├── nextflow.config
│   ├── run_nf.slurm
│   ├── align.slurm
│   └── idx_ref.slurm
├── data/
│   └── hg002_subset.fastq       ← downloaded in Step 3
└── ref/
    └── hg38.fa                   ← downloaded in Step 2
```

### Step 6 — Run the Pipeline

```bash
sbatch Scripts/run_nf.slurm
```

### Step 7 — Monitor the Job

```bash
# Check if your job is running
squeue -u $USER

# Watch the output log in real time (replace <job_id> with your SLURM job number)
tail -f slurm-<job_id>.out
```

### Step 8 — Check Results

Once the job completes, results will be in the `results/` directory:

```bash
ls results/

# Quick check — view alignment stats
cat results/hg002.flagstat.txt

# Open the Nextflow report in your browser for a visual summary
# (copy nf_report.html to your local machine and open it)
```

---

## Final Successful Execution

| Metric | Value |
|---|---|
| **Run Name** | amazing_leavitt |
| **SLURM Job ID** | 1722 |
| **Status** | ✅ COMPLETED |
| **Duration** | 5m 38s |
| **CPU Hours** | 0.5 |
| **Peak CPUs** | 10 |
| **Peak Memory** | 28 GB |

All workflow stages completed successfully:

| Stage | What It Did | Status |
|---|---|---|
| faidx | Indexed the reference genome | ✔ Completed |
| align | Aligned reads to reference | ✔ Completed |
| sort_index | Sorted and indexed the BAM file | ✔ Completed |
| flagstat | Generated alignment QC statistics | ✔ Completed |
| clair3.vcf.gz | compressed VCF of called variants | ✔ Completed |
| clair3.vcf.gz.tbi | tabix index for fast region queries and benchmarking tools | ✔ Completed |
| deepvariant.vcf.gz | compressed VCF of called variants | ✔ Completed |
| deepvariant.vcf.gz.tbi | tabix index for fast region queries and benchmarking tools | ✔ Completed |
---

## Generated Outputs

All output files are located in the `results/` directory after a successful run.

| File | Description | How to View |
|---|---|---|
| `hg002.flagstat.txt` | Alignment quality statistics | `cat results/hg002.flagstat.txt` |
| `hg38.fa.fai` | Reference genome index listing all chromosomes and their sizes | `cat results/hg38.fa.fai` |
| `nf_report.html` | Nextflow execution report with resource usage graphs | Open in any web browser |
| `nf_timeline.html` | Visual timeline showing when each task ran | Open in any web browser |
| `nf_trace.txt` | Tab-separated log of CPU, memory, and time per task | `cat results/nf_trace.txt` or open in Excel |
| clair3.vcf.gz | compressed VCF of called variants | singularity exec docker://quay.io/biocontainers/bcftools:1.17--h00cdaf9_0 \bcftools view results/clair3.vcf.gz |
| clair3.vcf.gz.tbi | tabix index for fast region queries and benchmarking tools | singularity exec docker://quay.io/biocontainers/bcftools:1.17--h00cdaf9_0 \bcftools view results/clair3.vcf.gz.tbi |
| deepvariant.vcf.gz | compressed VCF of called variants | singularity exec docker://quay.io/biocontainers/bcftools:1.17--h00cdaf9_0 \bcftools view results/deepvariant.vcf.gz |
| deepvariant.vcf.gz.tbi | tabix index for fast region queries and benchmarking tools | singularity exec docker://quay.io/biocontainers/bcftools:1.17--h00cdaf9_0 \bcftools view results/deepvariant.vcf.gz.tbi |


**Alignment statistics from our run:**

- **45,266** total reads processed
- **45,078** reads successfully mapped to the reference genome
- **99.58%** mapping rate

> A mapping rate above 95% is considered excellent and indicates high-quality alignment. Our 99.58% rate confirms that the PacBio HiFi reads aligned very well to the hg38 reference.

---

## Debugging & Architectural Lessons

During development, several HPC-specific issues were encountered and resolved. These are documented here to help others reproduce the pipeline and avoid common pitfalls.

| Problem | What Went Wrong | How It Was Fixed |
|---|---|---|
| Container nesting error | Calling `singularity exec` manually inside a Nextflow process that was already running in a container | Removed manual singularity calls — let Nextflow handle all container execution automatically |
| File self-copy conflict | `publishDir` directive tried to copy a file onto itself when source and destination were the same | Used `mode: 'copy'` with separate output directories |
| Exit status 127 | The `singularity` binary was not found inside the container (because you can't run singularity inside singularity) | Ensured all processes run via Nextflow's `container` directive instead of manual calls |
| SLURM queue misconfiguration | Jobs failed because the wrong partition was specified | Updated `#SBATCH -p` to the correct available partition |
| Report overwrite conflicts | Multiple Nextflow runs tried writing to the same report file | Added unique naming conventions and used `-resume` flag for reruns |

**Key design decisions that made the pipeline work:**

- **No manual singularity calls** inside Nextflow `script` blocks — Nextflow manages all container execution through its `container` directive
- **Clean process separation** — each bioinformatics step is its own Nextflow process with well-defined inputs and outputs
- **Correct tuple channel handling** — multiple output files (e.g., BAM + BAI) are passed between processes as tuples
- **Proper publishDir usage** — results are copied to the output directory without file conflicts

---

## Academic Context

This project was completed as part of a bioinformatics coursework assignment (STBI, 6th Semester). It demonstrates:

- **HPC workflow orchestration** — using Nextflow to coordinate multi-step pipelines and SLURM to manage compute resources on a cluster
- **Containerized bioinformatics** — running all tools inside Singularity containers for portability and reproducibility across different systems
- **Reproducibility in genomics** — a fully documented, version-controlled workflow that anyone can clone and re-run to get the same results
- **Long-read variant calling** — leveraging PacBio HiFi technology and state-of-the-art tools (minimap2, Clair3) to detect genetic variants

---

> ⚠️ **Disclaimer:** This workflow is for academic purposes only and is not intended for clinical diagnostic use.
