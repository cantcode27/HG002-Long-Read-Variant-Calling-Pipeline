nextflow.enable.dsl=2

params.reads  = params.reads  ?: 'data/hg002_subset.fastq'
params.ref    = params.ref    ?: 'ref/hg38.fa'
params.outdir = params.outdir ?: 'results'

workflow {

    reads_ch = Channel.fromPath(params.reads, checkIfExists: true)
    ref_ch   = Channel.fromPath(params.ref,   checkIfExists: true)

    // build index (publishes .fai to results/)
    faidx(ref_ch)

    // align + sort + index -> tuple(bam, bai)
    bam_tuple_ch = align_sort(ref_ch, reads_ch)

    // compute flagstat using the tuple(bam,bai)
    flagstat(bam_tuple_ch)
}

process faidx {

    tag "faidx"

    publishDir params.outdir, mode: 'copy'

    input:
    path ref

    output:
    path "${ref.simpleName}.fai"

    container "docker://quay.io/biocontainers/samtools:1.17--h00cdaf9_0"

    script:
    """
    samtools faidx ${ref}
    """
}

process align_sort {

    tag "align_sort"

    publishDir params.outdir, mode: 'copy'

    input:
    path ref
    path reads

    output:
    tuple path("hg002.sorted.bam"), path("hg002.sorted.bam.bai")

    container "docker://quay.io/biocontainers/minimap2:2.28--he4a0461_0"

    cpus 8
    memory '24 GB'
    time '3h'

    script:
    """
    minimap2 -t ${task.cpus} -ax map-hifi ${ref} ${reads} | \
      samtools view -@ ${task.cpus} -bS - | \
      samtools sort -@ ${task.cpus} -o hg002.sorted.bam

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
