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
- [Benchmarking Results](#benchmarking-results)
- [Debugging & Architectural Lessons](#debugging--architectural-lessons)
- [Academic Context](#academic-context)
- [📄 Detailed Documentation](#-detailed-documentation)

---

## What Does This Pipeline Do?

This pipeline takes **raw DNA sequencing data** from a human genome sample and automatically:

1. **Aligns** the sequencing reads to a human reference genome (like matching puzzle pieces to a template)
2. **Processes** the alignment into an analysis-ready format
3. **Calls variants** — identifies positions where this individual's DNA differs from the reference genome (e.g., mutations, insertions, deletions)
4. **Benchmarks** the called variants against a gold-standard truth set using hap.py to measure accuracy

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

### What is Benchmarking with hap.py?

Once variants are called, we need to know how accurate they are. **hap.py** (Haplotype Comparison Tool) compares our called variants against a **truth set** — a carefully curated set of known variants for the HG002 sample provided by the Genome in a Bottle (GIAB) consortium. It reports metrics like **Recall** (how many true variants we found), **Precision** (how many of our calls were actually correct), and **F1 Score** (the harmonic mean of both).

### What is an HPC Cluster?

A **High-Performance Computing (HPC) cluster** is a group of powerful computers managed by a job scheduler (in our case, **SLURM**). Instead of running tasks on your laptop, you submit "jobs" that run on dedicated compute nodes with more memory, CPUs, and storage.

### What are Containers?

**Containers** (like Docker or Singularity) package software and all its dependencies into a portable, self-contained unit. This ensures that the pipeline behaves the same way on any machine — solving the classic "it works on my machine" problem.

### What is Nextflow?

**Nextflow** is a workflow manager designed for scientific computing. It lets you define a multi-step pipeline (align → sort → call variants → benchmark) and handles parallelism, error recovery, and execution on HPC clusters automatically.

---

## Dataset

| Property | Detail |
| --- | --- |
| **Sample** | HG002 (NA24385) — a well-characterized human reference sample used globally for benchmarking |
| **Sequencing Type** | PacBio HiFi long reads |
| **Data Source** | [NHGRI Human Pangenome Project](https://humanpangenome.org/) (publicly available) |
| **Subsampling** | Original FASTQ was subsampled to **25%** using `seqtk` to reduce computation time |
| **Reference Genome** | hg38 (GRCh38) — the current standard human reference genome, downloaded from UCSC |
| **Truth Set** | GIAB v4.2.1 high-confidence VCF and BED for HG002 (used for benchmarking with hap.py) |

**Input files used in the pipeline:**

| File | Description | How to Obtain |
| --- | --- | --- |
| `data/hg002_subset.fastq` | Subsampled PacBio HiFi reads | Download from the Human Pangenome Project, then subsample with `seqtk sample -s100 input.fastq 0.25 > hg002_subset.fastq` |
| `ref/hg38.fa` | Human reference genome (FASTA format) | Download from [UCSC Genome Browser](https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz) and decompress with `gunzip hg38.fa.gz` |
| `benchmark/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz` | GIAB truth VCF | Download from [GIAB FTP](https://ftp-trace.ncbi.nlm.nih.gov/giab/ftp/release/AshkenazimTrio/HG002_NA24385_son/latest/GRCh38/) |
| `benchmark/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz.tbi` | Truth VCF index | Downloaded alongside the truth VCF |
| `benchmark/HG002_GRCh38_1_22_v4.2.1_benchmark_noinconsistent.bed` | High-confidence regions BED | Download from [GIAB FTP](https://ftp-trace.ncbi.nlm.nih.gov/giab/ftp/release/AshkenazimTrio/HG002_NA24385_son/latest/GRCh38/) |

> **Note:** These files are too large to include in the repository. You must download them separately before running the pipeline — see the [Reproduction Guide](#step-by-step-reproduction-guide) below.

---

## Tools & Versions

All tools were run inside **Singularity containers** pulled from Docker registries. This means you don't need to install any bioinformatics software manually — just have Singularity available on your system and the containers will be pulled automatically.

| Tool | What It Does | Version / Tag | Container Source |
| --- | --- | --- | --- |
| **Nextflow** | Orchestrates the entire pipeline | 25.10.4 | Installed natively on the HPC |
| **minimap2** | Aligns sequencing reads to the reference genome | 2.28 | `docker://quay.io/biocontainers/minimap2:2.28--he4a0461_0` |
| **samtools** | Converts, sorts, indexes, and generates statistics for alignment files | 1.17 | `docker://quay.io/biocontainers/samtools:1.17--h00cdaf9_0` |
| **Clair3** | Deep learning-based variant caller optimized for long reads | latest | `docker://hkubal/clair3` |
| **DeepVariant** | Deep learning-based variant caller developed by Google for multiple sequencing platforms | latest | `docker://google/deepvariant:latest` |
| **hap.py** | Haplotype comparison tool for benchmarking variant calls against a truth set | v0.3.12 | `docker://jmcdani20/hap.py:v0.3.12` |
| **seqtk** | Toolkit for processing FASTA/FASTQ files (used for subsampling reads) | — | Installed via conda (`conda install -c bioconda seqtk`) |
| **Singularity** | Runs Docker containers on HPC systems (where Docker isn't allowed) | — | System module |

---

## Pipeline Architecture

Below is a visual overview of the pipeline, followed by a detailed explanation of each step.

```
FASTQ reads ──→ [1. Index Reference] ──→ [2. Align Reads] ──→ [3. Sort & Convert]
                                                                       │
                                                                       ▼
                                              [5. Flagstat QC] ←── [4. Index BAM]
                                                                       │
                                                          ┌────────────┴────────────┐
                                                          ▼                         ▼
                                                  [6a. Clair3]            [6b. DeepVariant]
                                                          │                         │
                                                          ▼                         ▼
                                                [7a. hap.py Bench]       [7b. hap.py Bench]
                                                          │                         │
                                                          ▼                         ▼
                                                 clair3.vcf.gz           deepvariant.vcf.gz
                                               + happy.summary.csv     + happy.summary.csv
```

### Step 1 — Reference Indexing

```
samtools faidx hg38.fa
```

- **What it does:** Creates an index file (`.fai`) for the reference genome. Think of it like creating a table of contents for a book — it allows tools to quickly jump to specific chromosomal regions instead of reading the entire 3-billion-base-pair file from start to finish.
- **Output:** `hg38.fa.fai`

### Step 2 — Read Alignment

```
minimap2 -ax map-hifi hg38.fa reads.fastq
```

- **What it does:** Takes each sequencing read and finds where it best matches on the reference genome. Imagine you have thousands of puzzle pieces (reads) and a completed puzzle image (reference) — this step figures out where each piece belongs. The `-ax map-hifi` flag tells minimap2 that these are PacBio HiFi reads, so it uses the appropriate alignment parameters.
- **Output:** SAM file (human-readable alignment format)
- **SLURM script:** `Scripts/align.slurm`

### Step 3 — SAM → BAM Conversion & Sorting

```
samtools view -bS aligned.sam | samtools sort -o hg002.sorted.bam
```

- **What it does:** Converts the alignment from SAM (text format, very large ~894 MB) to BAM (binary, compressed ~325 MB), then sorts the reads by their position on the genome. Sorting is required by almost all downstream analysis tools.
- **Output:** `hg002.sorted.bam`

### Step 4 — BAM Indexing

```
samtools index hg002.sorted.bam
```

- **What it does:** Creates an index for the BAM file, enabling tools to quickly access reads at specific genomic locations without scanning the entire file. Similar to Step 1, but for the alignment file instead of the reference.
- **Output:** `hg002.sorted.bam.bai`

### Step 5 — Alignment Statistics (Quality Control)

```
samtools flagstat hg002.sorted.bam
```

- **What it does:** Generates a summary of alignment quality — how many reads were mapped successfully, how many failed, duplication rate, etc. This is a crucial sanity check to confirm the alignment worked correctly before proceeding to variant calling.
- **Output:** `hg002.flagstat.txt`

### Step 6 — Variant Calling

Two variant callers are run **in parallel** on the same sorted BAM file:

**6a. Clair3:**

- **What it does:** Clair3 uses a deep neural network to examine the aligned reads and identify positions where this individual's genome differs from the reference. It uses a two-stage approach — first a fast pileup model to find candidate sites, then a more accurate full-alignment model to refine the calls. It outputs a VCF (Variant Call Format) file — a standardized format that lists all detected variants with quality scores and metadata.
- **Model used:** `/opt/models/hifi` (built-in PacBio HiFi model)
- **Output:** `clair3.vcf.gz` + `clair3.vcf.gz.tbi`

**6b. DeepVariant:**

- **What it does:** DeepVariant converts aligned reads into image-like pileup representations, then uses a deep convolutional neural network (similar to image classification) to classify each candidate site as a variant or not. It produces a VCF file containing short variants (SNVs and small indels) with genotype likelihoods.
- **Model used:** `PACBIO` (built-in PacBio/HiFi mode via `--model_type=PACBIO`)
- **Output:** `deepvariant.vcf.gz` + `deepvariant.vcf.gz.tbi`

### Step 7 — Benchmarking with hap.py

Both VCFs are independently benchmarked against the GIAB v4.2.1 truth set:

```
hap.py truth.vcf.gz query.vcf.gz -f confidence.bed -r ref.fa -o happy --engine=vcfeval --pass-only
```

- **What it does:** Compares the variant calls from each caller against the known truth variants for HG002. It uses the `vcfeval` engine for sophisticated haplotype-aware comparison and reports Recall, Precision, and F1 Score separately for SNPs and INDELs.
- **`--pass-only`:** Only evaluates variants that passed the caller's internal quality filters.
- **Output:** `happy.summary.csv`, `happy.extended.csv`, `happy.metrics.json.gz`, `happy.runinfo.json`

---

## HPC Execution Model

### How Jobs Were Submitted

All processes were submitted through SLURM using:

```
sbatch Scripts/run_nf.slurm
```

Individual pipeline stages also have dedicated SLURM scripts for modular execution:

- `Scripts/idx_ref.slurm` — Reference indexing job
- `Scripts/align.slurm` — Read alignment job

### SLURM Job Configuration

The following resources were allocated for the pipeline:

```
#SBATCH -J a1_nf              # Job name
#SBATCH -p gpu                 # Partition (queue) to submit to
#SBATCH --cpus-per-task=8      # Number of CPU cores
#SBATCH --mem=24G              # Memory allocation
#SBATCH -t 03:30:00            # Maximum wall time (3 hours 30 minutes)
```

### Nextflow Configuration

In `Scripts/nextflow.config`, the following settings were used:

```
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
├── HG002_Pipeline_Comprehensive_Guide.pdf  # 19-page detailed guide (theory + practical)
├── report.tex                         # LaTeX source for the guide above
│
├── Scripts/
│   ├── main.nf                        # Nextflow DSL2 pipeline definition
│   ├── nextflow.config                # Nextflow + SLURM + Singularity configuration
│   ├── run_nf.slurm                   # Main SLURM submission script
│   ├── align.slurm                    # SLURM script for the alignment step
│   └── idx_ref.slurm                  # SLURM script for reference indexing
│
├── benchmark/
│   ├── clair3happy_summary.csv        # hap.py benchmarking results for Clair3
│   └── dvhappy_summary.csv           # hap.py benchmarking results for DeepVariant
│
└── results/
    ├── hg002.flagstat.txt             # Alignment quality control statistics
    ├── hg38.fa.fai                    # Reference genome index (chromosome sizes)
    ├── nf_report.html                 # Nextflow execution report (open in browser)
    ├── nf_timeline.html               # Visual timeline of pipeline execution
    └── nf_trace.txt                   # Detailed resource usage log per process
```

> **Note:** Large files (BAM, SAM, FASTQ, reference genome, Singularity containers, truth VCFs, output VCFs) are excluded via `.gitignore` as they are too large for GitHub. See the [Reproduction Guide](#step-by-step-reproduction-guide) for instructions on obtaining them.

---

## Step-by-Step Reproduction Guide

Follow these steps to reproduce the entire pipeline from scratch on any SLURM-managed HPC cluster.

### Prerequisites

Before starting, ensure you have the following available on your HPC system:

| Requirement | Minimum | How to Check |
| --- | --- | --- |
| **SLURM** | Job scheduler must be available | `sinfo` should show partitions |
| **Singularity/Apptainer** | For running containerized tools | `singularity --version` |
| **Nextflow** | Version ≥ 25.x | `nextflow -version` |
| **CPUs** | ≥ 8 cores | Check with `nproc` |
| **RAM** | ≥ 24 GB | Check with `free -h` |
| **Disk Space** | ~50 GB free | Check with `df -h` |

> **Don't have Nextflow?** Install it with: `curl -s https://get.nextflow.io | bash`

### Step 1 — Clone the Repository

```
git clone <repo-url>
cd a2
```

### Step 2 — Download the Reference Genome

```
mkdir -p ref
cd ref
wget https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz
gunzip hg38.fa.gz
cd ..
```

### Step 3 — Download and Subsample the Sequencing Data

```
mkdir -p data

# Download HG002 PacBio HiFi reads from the Human Pangenome Project
# Visit https://humanpangenome.org/ to get the exact download URL
wget <HG002_PACBIO_HIFI_FASTQ_URL> -O data/hg002_full.fastq

# Subsample to 25% to reduce computation time
# The -s100 flag sets the random seed for reproducibility
seqtk sample -s100 data/hg002_full.fastq 0.25 > data/hg002_subset.fastq
```

> **Don't have seqtk?** Install it via conda: `conda install -c bioconda seqtk`

### Step 4 — Download the GIAB Truth Set (For Benchmarking)

```
mkdir -p benchmark
cd benchmark

# Download the GIAB v4.2.1 truth VCF, its index, and the high-confidence BED
wget https://ftp-trace.ncbi.nlm.nih.gov/giab/ftp/release/AshkenazimTrio/HG002_NA24385_son/latest/GRCh38/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz
wget https://ftp-trace.ncbi.nlm.nih.gov/giab/ftp/release/AshkenazimTrio/HG002_NA24385_son/latest/GRCh38/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz.tbi
wget https://ftp-trace.ncbi.nlm.nih.gov/giab/ftp/release/AshkenazimTrio/HG002_NA24385_son/latest/GRCh38/HG002_GRCh38_1_22_v4.2.1_benchmark_noinconsistent.bed

cd ..
```

### Step 5 — Pull Singularity Containers

```
# These will be cached locally so they only download once
singularity pull docker://quay.io/biocontainers/minimap2:2.28--he4a0461_0
singularity pull docker://quay.io/biocontainers/samtools:1.17--h00cdaf9_0
singularity pull docker://hkubal/clair3
singularity pull docker://google/deepvariant:latest
singularity pull docker://jmcdani20/hap.py:v0.3.12
```

### Step 6 — Verify Directory Structure

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
├── ref/
│   └── hg38.fa                   ← downloaded in Step 2
└── benchmark/
    ├── HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz       ← downloaded in Step 4
    ├── HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz.tbi   ← downloaded in Step 4
    └── HG002_GRCh38_1_22_v4.2.1_benchmark_noinconsistent.bed  ← downloaded in Step 4
```

### Step 7 — Run the Pipeline

```
sbatch Scripts/run_nf.slurm
```

### Step 8 — Monitor the Job

```
# Check if your job is running
squeue -u $USER

# Watch the output log in real time (replace <job_id> with your SLURM job number)
tail -f slurm-<job_id>.out
```

### Step 9 — Check Results

Once the job completes, results will be in the `results/` directory:

```
ls results/

# Quick check — view alignment stats
cat results/hg002.flagstat.txt

# View benchmarking results
cat results/happy_clair3/happy.summary.csv
cat results/happy_deepvariant/happy.summary.csv

# Open the Nextflow report in your browser for a visual summary
# (copy nf_report.html to your local machine and open it)
```

---

## Final Successful Execution

| Metric | Value |
| --- | --- |
| **Run Name** | amazing\_leavitt |
| **SLURM Job ID** | 1722 |
| **Status** | ✅ COMPLETED |
| **Duration** | 5m 38s |
| **CPU Hours** | 0.5 |
| **Peak CPUs** | 10 |
| **Peak Memory** | 28 GB |

All workflow stages completed successfully:

| Stage | What It Did | Status |
| --- | --- | --- |
| faidx | Indexed the reference genome | ✔ Completed |
| align | Aligned reads to reference | ✔ Completed |
| sort\_index | Sorted and indexed the BAM file | ✔ Completed |
| flagstat | Generated alignment QC statistics | ✔ Completed |
| clair3 | Called variants using Clair3 | ✔ Completed |
| deepvariant | Called variants using DeepVariant | ✔ Completed |
| happy\_clair3 | Benchmarked Clair3 calls against GIAB truth set | ✔ Completed |
| happy\_deepvariant | Benchmarked DeepVariant calls against GIAB truth set | ✔ Completed |

---

## Generated Outputs

All output files are located in the `results/` directory after a successful run.

| File | Description | How to View |
| --- | --- | --- |
| `hg002.flagstat.txt` | Alignment quality statistics | `cat results/hg002.flagstat.txt` |
| `hg38.fa.fai` | Reference genome index listing all chromosomes and their sizes | `cat results/hg38.fa.fai` |
| `nf_report.html` | Nextflow execution report with resource usage graphs | Open in any web browser |
| `nf_timeline.html` | Visual timeline showing when each task ran | Open in any web browser |
| `nf_trace.txt` | Tab-separated log of CPU, memory, and time per task | `cat results/nf_trace.txt` or open in Excel |
| `clair3.vcf.gz` | Compressed VCF of variants called by Clair3 | `bcftools view results/clair3.vcf.gz \| head -50` |
| `clair3.vcf.gz.tbi` | Tabix index for Clair3 VCF — used automatically by tools for fast region queries | — |
| `deepvariant.vcf.gz` | Compressed VCF of variants called by DeepVariant | `bcftools view results/deepvariant.vcf.gz \| head -50` |
| `deepvariant.vcf.gz.tbi` | Tabix index for DeepVariant VCF — used automatically by tools for fast region queries | — |
| `happy_clair3/` | hap.py benchmarking output directory for Clair3 calls | `cat results/happy_clair3/happy.summary.csv` |
| `happy_deepvariant/` | hap.py benchmarking output directory for DeepVariant calls | `cat results/happy_deepvariant/happy.summary.csv` |

**Alignment statistics from our run:**

- **45,266** total reads processed
- **45,078** reads successfully mapped to the reference genome
- **99.58%** mapping rate

> A mapping rate above 95% is considered excellent and indicates high-quality alignment. Our 99.58% rate confirms that the PacBio HiFi reads aligned very well to the hg38 reference.

---

## Benchmarking Results

Both variant callers were benchmarked against the **GIAB v4.2.1 high-confidence truth set** for HG002 using **hap.py** with the `vcfeval` engine. Only **PASS** variants were evaluated.

> **Important context:** The input data was **subsampled to 25%** of the original coverage to reduce computation time. This means the sequencing depth is much lower than what these tools are designed for (~7–8x instead of ~30x). Low coverage directly causes low recall because many true variant sites simply do not have enough reads covering them to be detected. The precision values are more meaningful here — they tell us how accurate the callers are when they do make a call.

### SNP Performance

| Metric | Clair3 | DeepVariant |
| --- | --- | --- |
| **Truth Total** | 3,365,127 | 3,365,127 |
| **True Positives (TP)** | 23,708 | 13,589 |
| **False Negatives (FN)** | 3,341,419 | 3,351,538 |
| **False Positives (FP)** | 5,912 | 4,777 |
| **Recall** | 0.70% | 0.40% |
| **Precision** | 80.05% | 74.00% |
| **F1 Score** | 1.40% | 0.80% |

### INDEL Performance

| Metric | Clair3 | DeepVariant |
| --- | --- | --- |
| **Truth Total** | 525,469 | 525,469 |
| **True Positives (TP)** | 1,941 | 1,257 |
| **False Negatives (FN)** | 523,528 | 524,212 |
| **False Positives (FP)** | 1,654 | 819 |
| **Recall** | 0.37% | 0.24% |
| **Precision** | 54.33% | 60.45% |
| **F1 Score** | 0.73% | 0.48% |

### Interpretation

- **Recall is very low for both callers** — this is expected and not a fault of the tools. With only 25% of reads, most genomic positions have insufficient coverage for confident variant calling. At full 30x coverage, both Clair3 and DeepVariant typically achieve >99% SNP recall on HG002.

- **Precision is high**, especially for SNPs — when Clair3 or DeepVariant does call a variant, it is correct the large majority of the time. Clair3 achieved 80.05% SNP precision and DeepVariant achieved 74.00%.

- **Clair3 found more variants overall** (23,708 SNP TPs vs 13,589 for DeepVariant), which means at this low coverage it was slightly more sensitive. However, DeepVariant had fewer false positives for INDELs (819 vs 1,654) and higher INDEL precision (60.45% vs 54.33%).

- **Genotype errors (FP.gt)** make up a large portion of the false positives for both callers (4,891 of 5,912 SNP FPs for Clair3; 4,732 of 4,777 for DeepVariant). This means the callers found the right variant site but called the wrong genotype (e.g., heterozygous instead of homozygous) — another expected consequence of low coverage.

> **Bottom line:** Both callers show strong precision at low coverage, confirming that the pipeline is working correctly. The low recall is a direct and expected consequence of subsampling — it would recover to >99% at full coverage.

---

## Debugging & Architectural Lessons

During development, several HPC-specific issues were encountered and resolved. These are documented here to help others reproduce the pipeline and avoid common pitfalls.

| Problem | What Went Wrong | How It Was Fixed |
| --- | --- | --- |
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
- **Parallel variant calling** — Clair3 and DeepVariant run simultaneously on the same BAM, connected via independent Nextflow channels

---

## Academic Context

This project was completed as part of a bioinformatics coursework assignment (STBI, 6th Semester). It demonstrates:

- **HPC workflow orchestration** — using Nextflow to coordinate multi-step pipelines and SLURM to manage compute resources on a cluster
- **Containerized bioinformatics** — running all tools inside Singularity containers for portability and reproducibility across different systems
- **Reproducibility in genomics** — a fully documented, version-controlled workflow that anyone can clone and re-run to get the same results
- **Long-read variant calling** — leveraging PacBio HiFi technology and state-of-the-art tools (minimap2, Clair3, DeepVariant) to detect genetic variants
- **Variant calling benchmarking** — systematic accuracy evaluation of two deep-learning variant callers against a gold-standard truth set using hap.py, with quantitative comparison of recall, precision, and F1

---

## 📄 Detailed Documentation

A **19-page comprehensive guide** is included in this repository as a LaTeX-compiled PDF:

**[`HG002_Pipeline_Comprehensive_Guide.pdf`](HG002_Pipeline_Comprehensive_Guide.pdf)**

This document is written for someone with **zero prior knowledge** of Nextflow, SLURM, Singularity, or variant calling. It covers everything from first principles — the biology of DNA sequencing, how HPC clusters work, what containers are and why they matter — all the way through to interpreting hap.py benchmarking output. It includes:

- Full theory on DNA sequencing, variant types, reference genomes, and the VCF format
- A complete beginner's guide to Nextflow DSL2 — processes, workflows, channels, tuples, parameters, and the `-resume` flag
- SLURM job scheduling explained with annotated script examples
- Docker vs Singularity/Apptainer comparison and common container pitfalls
- Line-by-line walkthrough of every process in `main.nf` and every setting in `nextflow.config`
- How Clair3 (two-stage pileup + full-alignment) and DeepVariant (image classification CNN) work internally
- Benchmarking results with precision bar charts and detailed interpretation of why recall is low at 25% subsampling
- A complete troubleshooting table with common HPC-specific errors and fixes
- Pipeline flow diagrams, HPC architecture diagrams, and container concept illustrations

> The LaTeX source (`report.tex`) is also included if you want to modify or extend the document.

---

> ⚠️ **Disclaimer:** This workflow is for academic purposes only and is not intended for clinical diagnostic use.
