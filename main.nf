#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

params.input = false
params.help = false
params.debug = true

include { check_required_params; check_nb_cpus } from './modules/local/verify_inputs.nf'
include { REGISTRATION_ANTS } from './modules/nf-neuro/registration/ants/main.nf'

workflow get_data {
    main:
        if (params.help) {
            usage = file("$baseDir/USAGE")
            cpu_count = Runtime.runtime.availableProcessors()

            bindings = ["atlas_directory":"$params.atlas_directory",
                        "run_average_bundles":"$params.run_average_bundles",
                        "minimal_vote_ratio":"$params.minimal_vote_ratio",
                        "seed":"$params.seed",
                        "outlier_alpha":"$params.outlier_alpha",
                        "register_processes":"$params.register_processes",
                        "rbx_processes":"$params.rbx_processes",
                        "single_dataset_size_GB":"$params.single_dataset_size_GB",
                        "cpu_count":"$cpu_count"]

            engine = new groovy.text.SimpleTemplateEngine()
            template = engine.createTemplate(usage.text).make(bindings)
            print template.toString()
            return
        }

        log.info "SCIL RecobundlesX pipeline"
        log.info "=========================="
        log.info ""
        log.info "Start time: $workflow.start"
        log.info ""

        log.debug "[Command-line]"
        log.debug "$workflow.commandLine"
        log.debug ""

        log.info "[Git Info]"
        log.info "$workflow.repository - $workflow.revision [$workflow.commitId]"
        log.info ""

        check_required_params(['input', 'atlas_directory'])

        log.info "Options"
        log.info "======="
        log.info ""
        log.info "[Inputs]"
        log.info " Input: $params.input"
        log.info " Atlas Directory: $params.atlas_directory"
        log.info ""
        log.info "[Recobundles options]"
        log.info " Minimal Vote Percentage: $params.minimal_vote_ratio"
        log.info " Random Seed: $params.seed"
        log.info " Outlier Removal Alpha: $params.outlier_alpha"
        log.info " Run Average Bundles: $params.run_average_bundles"
        log.info ""
        log.info ""

        root = file(params.input)

        // Prepare the input data
        in_tractograms = Channel.fromFilePairs("$root/**/*.{trk,tck,fib,vtk,dpy}",
                        size:-1,
                        maxDepth:1) {[id: it.parent.name]}

        anats = Channel.fromPath("$root/**/*_fa.nii.gz", maxDepth:1).map{[[id: it.parent.name], it]}

        // Prepare the atlas
        atlas_directory = Channel.fromPath("$params.atlas_directory/atlas")
        atlas_anat = Channel.fromPath("$params.atlas_directory/mni_masked.nii.gz")
        atlas_config = Channel.fromPath("$params.atlas_directory/config_fss_1.json")
        centroids_dir = Channel.fromPath("$params.atlas_directory/centroids/", type: 'dir')

    emit:
        in_tractograms
        anats
        atlas_directory
        atlas_anat
        atlas_config
        centroids_dir
}

workflow {
    // ** Fetch your files ** //
    data = get_data()

    anat_for_registration = data.anats.combine(data.atlas_anat)
        .map {meta, anat, atlas_anat -> [meta, atlas_anat, anat, []]}
    REGISTRATION_ANTS(anat_for_registration)

    if (!params.disable_centroid_transformation) {
        // This is usually used for downstream analysis
        // there is the option to disable it as it does
        // not affect the bundle recognition and cleaning process.
        anat_and_transformation = data.anats
            .join(REGISTRATION_ANTS.out.affine, by: 0)
            .combine(data.centroids_dir)
        TRANSFORM_CENTROIDS(anat_and_transformation)
    }

    tractogram_and_transformation = data.in_tractograms
        .join(data.anats)
        .join(REGISTRATION_ANTS.out.affine)
        .combine(data.atlas_config)
        .combine(data.atlas_directory)
    RECOGNIZE_BUNDLES(tractogram_and_transformation)

    all_bundles_transfo_for_clean_average = RECOGNIZE_BUNDLES.out.bundles
        .combine(REGISTRATION_ANTS.out.affine, by:0)
        .combine(data.atlas_anat)
    CLEAN_BUNDLES(all_bundles_transfo_for_clean_average)

    if (params.run_average_bundles) {
        all_bundle_for_average = CLEAN_BUNDLES.out.bundles
            .flatten()
            .transpose()
            .combine(data.centroids_dir)
            .groupTuple(by: 1)

        AVERAGE_BUNDLES(all_bundle_for_average)
    }
}

process TRANSFORM_CENTROIDS {
    tag "$meta.id"

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.1.0.sif':
        'scilus/scilus:2.1.0' }"

    input:
    tuple val(meta), path(anat), path(transfo), path(centroids_dir)

    output:
    path "${meta.id}__*.trk", optional: true

    when:
    !params.disable_centroid_transformation

    script:
    """
    for centroid in ${centroids_dir}/*.trk;
        do bname=\${centroid/_centroid/}
        bname=\$(basename \$bname .trk)

        scil_tractogram_apply_transform.py \${centroid} ${anat} ${transfo} tmp.trk --inverse --keep_invalid -f
        scil_tractogram_remove_invalid.py tmp.trk ${meta.id}__\${bname}.trk --cut_invalid --remove_single_point --remove_overlapping_points --no_empty
    done
    """
}

process RECOGNIZE_BUNDLES {
    tag "$meta.id"

    cpus params.rbx_processes
    memory { params.single_dataset_size_GB.GB * params.rbx_processes }

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.1.0.sif':
        'scilus/scilus:2.1.0' }"

    input:
    tuple val(meta), path(tractograms), path(refenrence), path(transfo), path(config), path(directory)

    output:
    tuple val(meta), path("*.trk"), emit: bundles
    path "results.json"
    path "logfile.txt"

    script:
    """
    mkdir tmp/
    scil_tractogram_segment_with_bundleseg.py ${tractograms} ${config} ${directory}/ ${transfo} --inverse --out_dir tmp/ \
        -v DEBUG --minimal_vote_ratio $params.minimal_vote_ratio \
        --seed $params.seed --processes $params.rbx_processes
    mv tmp/* ./
    """
}

process CLEAN_BUNDLES {
    tag "$meta.id"

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.1.0.sif':
        'scilus/scilus:2.1.0' }"

    input:
    tuple val(meta), path(bundles), path(transfo), path(atlas)

    output:
    tuple val(meta), path("${meta.id}__*_cleaned.trk") 
    path "${meta.id}__*.nii.gz", optional: true, emit: bundles

    script:
    String bundles_list = bundles.join(", ").replace(',', '')
    """
    for bundle in $bundles_list;
        do if [[ \$bundle == *"__"* ]]; then
            pos=\$((\$(echo \$bundle | grep -b -o __ | cut -d: -f1)+2))
            bname=\${bundle:\$pos}
            bname=\$(basename \$bname .trk)
        else
            bname=\$(basename \$bundle .trk)
        fi

        scil_bundle_reject_outliers.py \${bundle} "${meta.id}__\${bname}_cleaned.trk" \
            --alpha $params.outlier_alpha
            
        if [ -s "${meta.id}__\${bname}_cleaned.trk" ]; then 
            if ${params.run_average_bundles}; then
                scil_tractogram_apply_transform.py "${meta.id}__\${bname}_cleaned.trk" \
		            ${atlas} ${transfo} tmp.trk --remove_invalid -f
            
                scil_tractogram_compute_density_map.py tmp.trk "${meta.id}__\${bname}_density_mni.nii.gz"

                scil_volume_math.py lower_threshold "${meta.id}__\${bname}_density_mni.nii.gz" 0.01 \
                    "${meta.id}__\${bname}_binary_mni.nii.gz"
            fi
        else
            echo "After cleaning \${bundle} all streamlines were outliers."
        fi
    done
    """
}

process AVERAGE_BUNDLES {
    tag "all"

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.1.0.sif':
        'scilus/scilus:2.1.0' }"

    input:
    tuple path(bundles), path(centroids_dir)

    output:
    path "*_average_density_mni.nii.gz", optional: true
    path "*_average_binary_mni.nii.gz", optional: true

    when:
    params.run_average_bundles

    script:
    """
    shopt -s nullglob
    mkdir tmp/
    for centroid in $centroids_dir/*.trk;
        do bname=\${centroid/_centroid/}
        bname=\$(basename \$bname .trk)

        nfiles=\$(find ./ -maxdepth 1 -type f -name "*__\${bname}_density_mni.nii.gz" | wc -l)
        if [[ \$nfiles -gt 1 ]]; then
            scil_volume_math.py addition *__\${bname}_density_mni.nii.gz tmp/\${bname}_average_density_mni.nii.gz
            scil_volume_math.py addition *__\${bname}_binary_mni.nii.gz tmp/\${bname}_average_binary_mni.nii.gz

            scil_volume_math.py lower_threshold tmp/\${bname}_average_binary_mni.nii.gz 0.01 \
                tmp/\${bname}_average_binary_mni.nii.gz --data_type uint8 -f

        elif [[ \$nfiles -eq 1 ]]; then
            cp *__\${bname}_density_mni.nii.gz tmp/\${bname}_average_density_mni.nii.gz
            scil_volume_math.py convert *__\${bname}_binary_mni.nii.gz tmp/\${bname}_average_binary_mni.nii.gz \
                --data_type uint8 -f
        else
            echo "No files found for \${bname}"
        fi
    done
    mv tmp/* ./
    """
}