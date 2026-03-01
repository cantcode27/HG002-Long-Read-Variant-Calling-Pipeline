#!/bin/bash
#SBATCH -J a1_align
#SBATCH -p gpu
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH -t 03:00:00
#SBATCH -o ../logs/align_%j.out
#SBATCH -e ../logs/align_%j.err

set -euo pipefail

cd ~/special/a1

# show starting sizes (for report evidence)
du -sh data ref results work || true

# Align (HiFi preset) -> BAM -> sort, without writing SAM to disk
singularity exec ./scripts/minimap2.sif minimap2 -t 8 -ax map-hifi ref/hg38.fa data/hg002_subset.fastq | \
  singularity exec ./scripts/samtools.sif samtools view -@ 8 -bS - | \
  singularity exec ./scripts/samtools.sif samtools sort -@ 8 -o results/hg002.sorted.bam

singularity exec ./scripts/samtools.sif samtools index results/hg002.sorted.bam

ls -lh results/hg002.sorted.bam results/hg002.sorted.bam.bai
du -sh results work || true

