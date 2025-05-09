include { ArgsCLI } from '../../../modules/local/utils'

workflow baysor {
    take:
    ch_patches
    config

    main:
    baysor_args = ArgsCLI(config.segmentation.baysor, null, ["config"])

    ch_patches
        .map { meta, sdata_path, patches_file_transcripts -> [meta, sdata_path, patches_file_transcripts.splitText()] }
        .flatMap { meta, sdata_path, patches_indices -> patches_indices.collect { index -> [meta, sdata_path, baysor_args, index.trim().toInteger(), patches_indices.size] } }
        .set { ch_baysor }

    ch_segmented = patchSegmentationBaysor(ch_baysor).map { meta, sdata_path, _out, n_patches -> [groupKey(meta.sdata_dir, n_patches), [meta, sdata_path]] }.groupTuple().map { it -> it[1][0] }

    (ch_resolved, _out) = resolveBaysor(ch_segmented, resolveArgs(config))

    emit:
    ch_resolved
}


process patchSegmentationBaysor {
    label "process_long"

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'apptainer' && !task.ext.singularity_pull_docker_container
        ? 'docker://quentinblampey/sopa:2.0.6-baysor'
        : 'docker.io/quentinblampey/sopa:2.0.6-baysor'}"

    input:
    tuple val(meta), path(sdata_path), val(cli_arguments), val(index), val(n_patches)

    output:
    tuple val(meta), path(sdata_path), path("${sdata_path}/.sopa_cache/transcript_patches/${index}/segmentation_counts.loom"), val(n_patches)

    script:
    """
    if command -v module &> /dev/null; then
        module purge
    fi
    
    sopa segmentation baysor ${sdata_path} --patch-index ${index} ${cli_arguments}
    """
}

process resolveBaysor {
    label "process_low"

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'apptainer' && !task.ext.singularity_pull_docker_container
        ? 'docker://quentinblampey/sopa:2.0.6-baysor'
        : 'docker.io/quentinblampey/sopa:2.0.6-baysor'}"

    input:
    tuple val(meta), path(sdata_path)
    val cli_arguments

    output:
    tuple val(meta), path(sdata_path)
    path "${sdata_path}/shapes/baysor_boundaries"

    script:
    """
    sopa resolve baysor ${sdata_path} ${cli_arguments}

    rm -r ${sdata_path}/.sopa_cache/transcript_patches    # cleanup large baysor files
    """
}

def resolveArgs(Map config) {
    def gene_column = config.segmentation.baysor.config.data.gene
    def min_area = config.segmentation.baysor.min_area ?: 0

    return "--gene-column ${gene_column} --min-area ${min_area}"
}
