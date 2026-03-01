#!/bin/bash
#SBATCH -J a1_nf
#SBATCH -p gpu
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH -t 03:30:00
#SBATCH -o ../logs/nf_%j.out
#SBATCH -e ../logs/nf_%j.err

set -euo pipefail

cd ~/special/a1

mkdir -p work results logs

# Keep Nextflow + Singularity cache inside your assignment folder (quota-safe)
export NXF_HOME="$PWD/work/nxf_home"
export NXF_SINGULARITY_CACHEDIR="$PWD/work/singularity_cache"

nextflow run main.nf \
  -c nextflow.config \
  --reads data/hg002_subset.fastq \
  --ref ref/hg38.fa \
  --outdir results \
  -work-dir work/nxf_work \
  
