#!/bin/bash
#SBATCH -J a1_idx
#SBATCH -p gpu
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH -t 00:20:00
#SBATCH -o ../logs/idx_ref_%j.out
#SBATCH -e ../logs/idx_ref_%j.err

set -euo pipefail

cd ~/special/a1/ref

singularity exec ../scripts/samtools.sif samtools faidx hg38.fa

ls -lh hg38.fa hg38.fa.fai

