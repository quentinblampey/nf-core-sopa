include { ArgsCLI } from '../../../modules/local/utils'

workflow proseg {
    take:
    ch_patches
    config

    main:
    proseg_args = ArgsCLI(config.segmentation.proseg, null, ["command_line_suffix"])

    (ch_segmented, _out) = patchSegmentationProseg(ch_patches, proseg_args)

    emit:
    ch_segmented
}


process patchSegmentationProseg {
    label "process_high"

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'apptainer' && !task.ext.singularity_pull_docker_container
        ? 'docker://quentinblampey/sopa:2.0.6-proseg'
        : 'docker.io/quentinblampey/sopa:2.0.6-proseg'}"

    input:
    tuple val(meta), path(sdata_path)
    val cli_arguments

    output:
    tuple val(meta), path(sdata_path)
    path "${sdata_path}/shapes/proseg_boundaries"

    script:
    """
    sopa segmentation proseg ${sdata_path} ${cli_arguments}
    """
}
