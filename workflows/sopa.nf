/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_sopa_pipeline'
include { cellpose } from '../subworkflows/local/cellpose'
include { baysor } from '../subworkflows/local/baysor'
include { readConfigFile } from '../modules/local/utils'
include { mapToCliArgs } from '../modules/local/utils'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SOPA {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    configfile // sopa configfile  from --configfile

    main:

    ch_versions = Channel.empty()

    def config = readConfigFile(configfile)

    ch_spatialdata = toSpatialData(ch_samplesheet.map { meta -> [meta, meta.sdata_dir] }, mapToCliArgs(config.read))

    if (config.segmentation.tissue) {
        (ch_tissue_seg, _out) = tissueSegmentation(ch_spatialdata, mapToCliArgs(config.segmentation.tissue))
    }
    else {
        ch_tissue_seg = ch_spatialdata
    }

    if (config.segmentation.cellpose) {
        (ch_image_patches, _out) = makeImagePatches(ch_tissue_seg, mapToCliArgs(config.patchify, "pixel"))
        ch_resolved = cellpose(ch_image_patches, config)
    }

    if (config.segmentation.baysor) {
        ch_input_baysor = config.segmentation.cellpose ? ch_resolved : ch_tissue_seg

        (ch_transcripts_patches, _out) = makeTranscriptPatches(ch_input_baysor, transcriptPatchesArgs(config))
        ch_resolved = baysor(ch_transcripts_patches, config)
    }

    (ch_aggregated, _out) = aggregate(ch_resolved, mapToCliArgs(config.aggregate))

    report(ch_aggregated)
    explorer(ch_aggregated, mapToCliArgs(config.explorer))


    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions).collectFile(
        storeDir: "${params.outdir}/pipeline_info",
        name: 'nf_core_sopa_software_versions.yml',
        sort: true,
        newLine: true,
    )

    emit:
    versions = ch_versions // channel: [ path(versions.yml) ]
}

process toSpatialData {
    label "process_high"

    input:
    tuple val(meta), val(sdata_dir)
    val cli_arguments

    output:
    tuple val(meta), path(sdata_dir)

    script:
    """
    sopa convert ${meta.id} --sdata-path ${meta.sdata_dir} ${cli_arguments}
    """
}

process tissueSegmentation {
    label "process_low"

    input:
    tuple val(meta), path(sdata_path)
    val cli_arguments

    output:
    tuple val(meta), path(sdata_path)
    path "${sdata_path}/shapes/region_of_interest"

    script:
    """
    sopa segmentation tissue ${sdata_path} ${cli_arguments}
    """
}

process makeImagePatches {
    label "process_single"

    input:
    tuple val(meta), path(sdata_path)
    val cli_arguments

    output:
    tuple val(meta), path(sdata_path), path("${sdata_path}/.sopa_cache/patches_file_image")
    path "${sdata_path}/shapes/image_patches"

    script:
    """
    sopa patchify image ${sdata_path} ${cli_arguments}
    """
}

process makeTranscriptPatches {
    label "process_medium"

    input:
    tuple val(meta), path(sdata_path)
    val cli_arguments

    output:
    tuple val(meta), path(sdata_path), path("${sdata_path}/.sopa_cache/patches_file_transcripts")

    script:
    """
    sopa patchify transcripts ${sdata_path} ${cli_arguments}
    """
}

process aggregate {
    label "process_medium"

    input:
    tuple val(meta), path(sdata_path)
    val cli_arguments

    output:
    tuple val(meta), path(sdata_path)
    path "${sdata_path}/tables/table"

    script:
    """
    sopa aggregate ${sdata_path} ${cli_arguments}
    """
}

process explorer {
    label "process_high"

    input:
    tuple val(meta), path(sdata_path)
    val cli_arguments

    output:
    path meta.explorer_dir

    script:
    """
    sopa explorer write ${sdata_path} --output-path ${meta.explorer_dir} ${cli_arguments}
    """
}

process report {
    label "process_medium"

    input:
    tuple val(meta), path(sdata_path)

    output:
    path "${meta.explorer_dir}/analysis_summary.html"

    script:
    """
    mkdir -p ${meta.explorer_dir}

    sopa report ${sdata_path} ${meta.explorer_dir}/analysis_summary.html
    """
}

def transcriptPatchesArgs(Map config) {
    def prior_args = mapToCliArgs(config.segmentation.baysor, null, ["prior_shapes_key", "unassigned_value"])

    return mapToCliArgs(config.patchify, "micron") + " " + prior_args
}
