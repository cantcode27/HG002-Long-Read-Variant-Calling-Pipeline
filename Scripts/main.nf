nextflow.enable.dsl=2

params.reads  = params.reads  ?: 'data/hg002_subset.fastq'
params.ref    = params.ref    ?: 'ref/hg38.fa'
params.outdir = params.outdir ?: 'results'
// ===== Appended params for Variant Calling + Benchmarking =====
params.clair3_model   = params.clair3_model   ?: '/opt/models/hifi'
params.truth_vcf      = params.truth_vcf      ?: 'benchmark/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz'
params.truth_vcf_tbi  = params.truth_vcf_tbi  ?: 'benchmark/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz.tbi'
params.truth_bed      = params.truth_bed      ?: 'benchmark/HG002_GRCh38_1_22_v4.2.1_benchmark_noinconsistent.bed'
workflow {

    reads_ch = Channel.fromPath(params.reads, checkIfExists: true)
    ref_ch   = Channel.fromPath(params.ref,   checkIfExists: true)

    // Make faidx an explicit dependency by passing (ref, fai) forward
    ref_fai_ch = faidx(ref_ch)

    sam_ch = align(ref_fai_ch, reads_ch)

    bam_tuple_ch = sort_index(sam_ch)

    flagstat(bam_tuple_ch)
        // ===== Appended: Variant Calling (Clair3 + DeepVariant) =====
    clair3_vcf_ch      = clair3(ref_fai_ch, bam_tuple_ch)
    deepvariant_vcf_ch = deepvariant(ref_fai_ch, bam_tuple_ch)

    // ===== Appended: Benchmarking (hap.py) =====
    happy_clair3(ref_fai_ch, clair3_vcf_ch)
    happy_deepvariant(ref_fai_ch, deepvariant_vcf_ch)
}

process faidx {
    tag { "faidx:${ref.getSimpleName()}" }
    publishDir params.outdir, mode: 'copy'

    input:
    path ref

    output:
    tuple path(ref), path("${ref}.fai")

    container "docker://quay.io/biocontainers/samtools:1.17--h00cdaf9_0"

    script:
    """
    samtools faidx ${ref}
    """
}

process align {
    tag "align"
    publishDir params.outdir, mode: 'copy'

    input:
    tuple path(ref), path(fai)
    path reads

    output:
    path "hg002.sam"

    container "docker://quay.io/biocontainers/minimap2:2.28--he4a0461_0"

    cpus 8
    memory '24 GB'
    time '3h'

    script:
    """
    minimap2 -t ${task.cpus} -ax map-hifi ${ref} ${reads} > hg002.sam
    """
}

process sort_index {
    tag "sort_index"
    publishDir params.outdir, mode: 'copy'

    input:
    path sam

    output:
    tuple path("hg002.sorted.bam"), path("hg002.sorted.bam.bai")

    container "docker://quay.io/biocontainers/samtools:1.17--h00cdaf9_0"

    cpus 8
    memory '24 GB'
    time '3h'

    script:
    """
    samtools view -@ ${task.cpus} -bS ${sam} \
      | samtools sort -@ ${task.cpus} -o hg002.sorted.bam

    samtools index hg002.sorted.bam
    """
}

process flagstat {
    tag "flagstat"
    publishDir params.outdir, mode: 'copy'

    input:
    tuple path(bam), path(bai)

    output:
    path "hg002.flagstat.txt"

    container "docker://quay.io/biocontainers/samtools:1.17--h00cdaf9_0"

    script:
    """
    samtools flagstat ${bam} > hg002.flagstat.txt
    """
}
process clair3 {
    tag "clair3"
    publishDir params.outdir, mode: 'copy'

    input:
    tuple path(ref), path(fai)
    tuple path(bam), path(bai)

    output:
    tuple path("clair3.vcf.gz"), path("clair3.vcf.gz.tbi")

    container "docker://hkubal/clair3"

    cpus 8
    memory '24 GB'
    time '3h'

    script:
    """
    run_clair3.sh \
      --bam_fn=${bam} \
      --ref_fn=${ref} \
      --threads=${task.cpus} \
      --platform=hifi \
      --model_path=${params.clair3_model} \
      --output=clair3_tmp

    # Clair3 commonly writes merge_output.vcf.gz (+ .tbi); standardize name for deliverables
    cp clair3_tmp/merge_output.vcf.gz clair3.vcf.gz
    cp clair3_tmp/merge_output.vcf.gz.tbi clair3.vcf.gz.tbi
    """
}
process deepvariant {
    tag "deepvariant"
    publishDir params.outdir, mode: 'copy'

    input:
    tuple path(ref), path(fai)
    tuple path(bam), path(bai)

    output:
    tuple path("deepvariant.vcf.gz"), path("deepvariant.vcf.gz.tbi")

    container "docker://google/deepvariant:latest"

    cpus 8
    memory '24 GB'
    time '6h'

    script:
    """
    mkdir -p dv_out

    /opt/deepvariant/bin/run_deepvariant \
      --model_type=PACBIO \
      --ref=${ref} \
      --reads=${bam} \
      --output_vcf=dv_out/deepvariant.vcf.gz \
      --num_shards=${task.cpus}

    # index VCF (tabix)
    /opt/deepvariant/bin/bcftools index -t dv_out/deepvariant.vcf.gz

    cp dv_out/deepvariant.vcf.gz deepvariant.vcf.gz
    cp dv_out/deepvariant.vcf.gz.tbi deepvariant.vcf.gz.tbi
    """
}
process happy_clair3 {
    tag "happy_clair3"
    publishDir "${params.outdir}/happy_clair3", mode: 'copy'

    input:
    tuple path(ref), path(fai)
    tuple path(query_vcf), path(query_tbi)

    output:
    path "happy.summary.csv"
    path "happy.extended.csv"
    path "happy.metrics.json.gz"
    path "happy.runinfo.json"

    container "docker://jmcdani20/hap.py:v0.3.12"

    cpus 8
    memory '24 GB'
    time '2h'

    script:
    """
    /opt/hap.py/bin/hap.py \
      ${params.truth_vcf} \
      ${query_vcf} \
      -f ${params.truth_bed} \
      -r ${ref} \
      -o happy \
      --engine=vcfeval \
      --pass-only \
      --threads ${task.cpus}
    """
}
process happy_deepvariant {
    tag "happy_deepvariant"
    publishDir "${params.outdir}/happy_deepvariant", mode: 'copy'

    input:
    tuple path(ref), path(fai)
    tuple path(query_vcf), path(query_tbi)

    output:
    path "happy.summary.csv"
    path "happy.extended.csv"
    path "happy.metrics.json.gz"
    path "happy.runinfo.json"

    container "docker://jmcdani20/hap.py:v0.3.12"

    cpus 8
    memory '24 GB'
    time '2h'

    script:
    """
    /opt/hap.py/bin/hap.py \
      ${params.truth_vcf} \
      ${query_vcf} \
      -f ${params.truth_bed} \
      -r ${ref} \
      -o happy \
      --engine=vcfeval \
      --pass-only \
      --threads ${task.cpus}
    """
}
