//
// Raw data processing with Space Ranger
//

include { UNTAR } from "../../modules/nf-core/untar"
include { SPACERANGER_COUNT } from '../../modules/nf-core/spaceranger/count'

workflow SPACERANGER {
    take:
    ch_samplesheet

    main:

    ch_versions = Channel.empty()

    // Space Ranger analysis: --------------------------------------------------

    // Split channel into tarballed and directory inputs
    ch_spaceranger = ch_samplesheet
        .map { it -> [it, it.fastq_dir]}
        .branch {
            tar: it[1].name.contains(".tar.gz")
            dir: !it[1].name.contains(".tar.gz")
        }

    // Extract tarballed inputs
    UNTAR ( ch_spaceranger.tar )
    ch_versions = ch_versions.mix(UNTAR.out.versions)

    // Combine extracted and directory inputs into one channel
    ch_spaceranger_combined = UNTAR.out.untar
        .mix ( ch_spaceranger.dir )
        .map { meta, dir -> meta + [fastq_dir: dir] }

    // Create final meta map and check input existance
    ch_spaceranger_input = ch_spaceranger_combined.map { create_channel_spaceranger(it) }


    //
    // Reference files
    //
    ch_reference = Channel.empty()
    if (params.spaceranger_reference ==~ /.*\.tar\.gz$/) {
        ref_file = file(params.spaceranger_reference)
        UNTAR(
            [
                [id: "reference"],
                ref_file,
            ]
        )
        ch_reference = UNTAR.out.untar.map { meta, ref -> ref }
        ch_versions = ch_versions.mix(UNTAR.out.versions)
    }
    else {
        ch_reference = file(params.spaceranger_reference, type: "dir", checkIfExists: true)
    }

    //
    // Optional: probe set
    //
    ch_probeset = Channel.empty()
    if (params.spaceranger_probeset) {
        ch_probeset = file(params.spaceranger_probeset, checkIfExists: true)
    }
    else {
        ch_probeset = []
    }

    //
    // Run Space Ranger count
    //
    SPACERANGER_COUNT(
        ch_spaceranger_input,
        ch_reference,
        ch_probeset,
    )

    ch_samplesheet = SPACERANGER_COUNT.out.outs.map { outs -> outs[0] }
    ch_versions = ch_versions.mix(SPACERANGER_COUNT.out.versions.first())

    emit:
    ch_samplesheet = ch_samplesheet
    versions = ch_versions // channel: [ versions.yml ]
}


// Function to get list of [ meta, [ fastq_dir, tissue_hires_image, slide, area ]]
def create_channel_spaceranger(LinkedHashMap meta) {
    // Convert a path in `meta` to a file object and return it. If `key` is not contained in `meta`
    // return an empty list which is recognized as 'no file' by nextflow.
    def get_file_from_meta = {key ->
        v = meta.remove(key);
        return v ? file(v) : []
    }

    fastq_dir = meta.remove("fastq_dir")
    fastq_files = file("${fastq_dir}/${meta['id']}*.fastq.gz")
    manual_alignment = get_file_from_meta("manual_alignment")
    slidefile = get_file_from_meta("slidefile")
    image = get_file_from_meta("image")
    cytaimage = get_file_from_meta("cytaimage")
    colorizedimage = get_file_from_meta("colorizedimage")
    darkimage = get_file_from_meta("darkimage")

    if(!fastq_files.size()) {
        error "No `fastq_dir` specified or no samples found in folder."
    }

    check_optional_files = ["manual_alignment", "slidefile", "image", "cytaimage", "colorizedimage", "darkimage"]
    for(k in check_optional_files) {
        if(this.binding[k] && !this.binding[k].exists()) {
            error "File for `${k}` is specified, but does not exist: ${this.binding[k]}."
        }
    }
    if(!(image || cytaimage || colorizedimage || darkimage)) {
        error "Need to specify at least one of 'image', 'cytaimage', 'colorizedimage', or 'darkimage' in the samplesheet"
    }

    return [meta, fastq_files, image, cytaimage, darkimage, colorizedimage, manual_alignment, slidefile]
}

