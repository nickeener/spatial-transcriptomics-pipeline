#!/usr/bin/env cwl-runner

class: Workflow
cwlVersion: v1.2

requirements:
   - class: SubworkflowFeatureRequirement
   - class: InlineJavascriptRequirement
   - class: StepInputExpressionRequirement
   - class: MultipleInputFeatureRequirement
   - class: ScatterFeatureRequirement

inputs:
  input_dir:
    type: Directory
    doc: Root directory containing space_tx formatted experiment

  dir_size:
    type: long?
    doc: The size of input_dir in MiB. If provided, will be used to specify storage space requests.

  parameter_json:
    type: File?
    doc: json containing step parameters.

  selected_fovs:
    type: int[]?
    doc: If provided, processing will only be run on FOVs with these indices.

  fov_count:
    type: int?
    doc: The number of FOVs that are included in this experiment

  clip_min:
    type: float?
    doc: Pixels below this percentile are set to 0.

  clip_max:
    type: float?
    doc: Pixels above this percentile are set to 1.

  level_method:
    type: string?
    doc: Levelling method for clip and scale application. Defaults to SCALE_BY_CHUNK. If rescaling is configured in parameter_json, will be set to SCALE_BY_CHUNK if true, SCALE_BY_IMAGE if false.

  is_volume:
    type: boolean?
    doc: Whether to treat the zplanes as a 3D image.

  register_aux_view:
    type: string?
    doc: The name of the auxillary view to be used for image registration.

  register_to_primary:
    type: boolean?
    doc: If true, registration will be performed between the first round of register_aux_view and the primary images.

  channels_per_reg:
    type: int?
    doc: The number of images associated with each channel in the registration image.  Will be calculated from aux view if provided through parameter_json, otherwise defaults to one.

  background_view:
    type: string?
    doc: The name of the auxillary view to be used for background subtraction.  Background will be estimated if not provided.

  register_background:
    type: boolean?
    doc: If true, the `background_view` will be aligned to the `aux_view`.

  anchor_view:
    type: string?
    doc: The name of the auxillary view to be processed in parallel with primary view, such as for anchor round in ISS processing. Will not be included if not provided.

  high_sigma:
    type: int?
    doc: Sigma value for high pass gaussian filter. Will not be run if not provided.

  deconvolve_iter:
    type: int?
    doc: Number of iterations to perform for deconvolution. High values remove more noise while lower values remove less. The value 15 will work for most datasets unless image is very noisy. Will not be run if not provided.

  deconvolve_sigma:
    type: int?
    doc: Sigma value for deconvolution. Should be approximately the expected spot size.

  low_sigma:
    type: int?
    doc: Sigma value for low pass gaussian filter. Will not be run if not provided.

  rolling_radius:
    type: int?
    doc: Radius for rolling ball background subtraction. Larger values lead to increased intensity evening effect. The value of 3 will work for most datasets. Will not be run if not provided.

  match_histogram:
    type: boolean?
    doc: If true, histograms will be equalized.

  tophat_radius:
    type: int?
    doc: Radius for white top hat filter. Should be slightly larger than the expected spot radius. Will not be run if not provided.

  rescale:
    type: boolean?
    doc: Whether to iteratively rescale images before running the decoder. If true, will skip clip and scale at the end of this step.

  n_processes:
    type: int?
    doc: If provided, the number of processes that will be spawned for processing. Otherwise, the maximum number of available CPUs will be used.

outputs:
  processed_exp:
    type: Directory
    outputSource: execute_processing/processed_exp

steps:

  read_schema:
    run:
      class: CommandLineTool
      baseCommand: cat

      requirements:
        DockerRequirement:
          dockerPull: hubmap/starfish-custom:latest
        ResourceRequirement:
          ramMin: 1000
          tmpdirMin: 1000
          outdirMin: 1000

      inputs:
        schema:
          type: string
          inputBinding:
            position: 1

      outputs:
        data:
          type: stdout

    in:
      schema:
        valueFrom: "/opt/processing.json"
    out: [data]

  stage_processing:
    run: inputParser.cwl
    in:
      datafile: parameter_json
      schema: read_schema/data
    out: [fov_count, selected_fovs, clip_min, clip_max, level_method, rescale, register_aux_view, register_to_primary, channels_per_reg, background_view, register_background, anchor_view, high_sigma, deconvolve_iter, deconvolve_sigma, low_sigma, rolling_radius, match_histogram, tophat_radius, channel_count, aux_tilesets_aux_names, aux_tilesets_aux_channel_count, is_volume, n_processes]
    when: $(inputs.datafile != null)

  tmpname:
    run: tmpdir.cwl
    in: []
    out: [tmp]

  execute_processing:
    run:
      class: CommandLineTool
      baseCommand: /opt/imgProcessing.py

      requirements:
        InitialWorkDirRequirement:
          listing:
            - entryname: "$('input_dir_'+inputs.tmp_prefix)"
              writable: true
              entry: "$(inputs.input_files)"
        DockerRequirement:
          dockerPull: hubmap/starfish-custom:latest
        ResourceRequirement:
          tmpdirMin: |
            ${
              if(inputs.dir_size === null) {
                return null;
              } else {
                return inputs.dir_size;
              }
            }
          outdirMin: |
            ${
              return 1000;
            }
          coresMin: |
            ${
              if(inputs.n_processes === null) {
                return null;
              } else {
                return inputs.n_processes;
              }
            }
          ramMin: |
            ${
              if(inputs.n_processes === null) {
                return null;
              } else {
                return Math.max(inputs.n_processes * 20 * 24, inputs.dir_size / 75);
              }
            }

      inputs:
        dir_size:
          type: long?

        tmp_prefix:
          type: string
          inputBinding:
            prefix: --tmp-prefix

        input_files:
          type: Directory
          doc: Raw input folder, possibly with ugly docker string.

        input_dir:
          type: string
          inputBinding:
            prefix: --input-dir
          doc: Root directory containing space_tx formatted experiment

        selected_fovs:
          type: int[]?
          inputBinding:
            prefix: --selected-fovs
          doc: If provided, processing will only be run on FOVs with these indices.

        clip_min:
          type: float?
          inputBinding:
            prefix: --clip-min
          doc: Pixels below this percentile are set to 0. Defaults to 95.

        clip_max:
          type: float?
          inputBinding:
            prefix: --clip-max
          doc: Pixels above this percentile are set to 1. Defaults to 99.9.

        level_method:
          type: string?
          inputBinding:
            prefix: --level-method
          doc: Levelling method for clip and scale application. Defaults to SCALE_BY_CHUNK.

        is_volume:
          type: boolean?
          inputBinding:
            prefix: --is-volume
          doc: Whether to treat the zplanes as a 3D image.

        rescale:
          type: boolean?
          inputBinding:
            prefix: --rescale

        register_aux_view:
          type: string?
          inputBinding:
            prefix: --register-aux-view
          doc: The name of the auxillary view to be used for image registration. Registration will not be performed if not provided.

        register_to_primary:
          type: boolean?
          inputBinding:
            prefix: --register-to-primary

        channels_per_reg:
          type: int?
          inputBinding:
            prefix: --ch-per-reg
          doc: The number of images associated with each channel of the registration image.  Defaults to 1.

        background_view:
          type: string?
          inputBinding:
            prefix: --background-view
          doc: The name of the auxillary view to be used for background subtraction.  Background will be estimated if not provided.

        register_background:
          type: boolean?
          inputBinding:
            prefix: --register-background
          doc: If true, the `background_view` will be aligned to the `aux_name`.

        anchor_view:
          type: string?
          inputBinding:
            prefix: --anchor-view
          doc: The name of the auxillary view to be processed in parallel with primary view, such as for anchor round in ISS processing. Will not be included if not provided.

        high_sigma:
          type: int?
          inputBinding:
            prefix: --high-sigma
          doc: Sigma value for high pass gaussian filter. Will not be run if not provided.

        deconvolve_iter:
          type: int?
          inputBinding:
            prefix: --decon-iter
          doc: Number of iterations to perform for deconvolution. High values remove more noise while lower values remove less. The value 15 will work for most datasets unless image is very noisy. Will not be run if not provided.

        deconvolve_sigma:
          type: int?
          inputBinding:
            prefix: --decon-sigma
          doc: Sigma value for deconvolution. Should be approximately the expected spot size.

        low_sigma:
          type: int?
          inputBinding:
            prefix: --low-sigma
          doc: Sigma value for low pass gaussian filter. Will not be run if not provided.

        rolling_radius:
          type: int?
          inputBinding:
            prefix: --rolling-radius
          doc: Radius for rolling ball background subtraction. Larger values lead to increased intensity evening effect. The value of 3 will work for most datasets. Will not be run if not provided.

        match_histogram:
          type: boolean?
          inputBinding:
            prefix: --match-histogram
          doc: If true, histograms will be equalized.

        tophat_radius:
          type: int?
          inputBinding:
            prefix: --tophat-radius
          doc: Radius for white top hat filter. Should be slightly larger than the expected spot radius. Will not be run if not provided.

        n_processes:
          type: int?
          inputBinding:
            prefix: --n-processes
          doc: If provided, the number of processes that will be spawned for processing. Otherwise, the maximum number of available CPUs will be used.

      outputs:
        processed_exp:
          type: Directory
          outputBinding:
            glob: $("tmp/" + inputs.tmp_prefix + "/3_processed/")
    in:
      dir_size: dir_size
      tmp_prefix: tmpname/tmp
      input_files: input_dir
      input_dir:
        valueFrom: $("input_dir_" + inputs.tmp_prefix)
      selected_fovs: selected_fovs
      clip_min:
        source: [stage_processing/clip_min, clip_min]
        valueFrom: |
          ${
            if(!(self[0] === null)){
              return self[0];
            } else if(!(self[1] === null)) {
              return self[1];
            } else {
              return null;
            }
          }
      clip_max:
        source: [stage_processing/clip_max, clip_max]
        valueFrom: |
          ${
            if(!(self[0] === null)){
              return self[0];
            } else if(!(self[1] === null)) {
              return self[1];
            } else {
              return null;
            }
          }
      level_method:
        source: [stage_processing/level_method, level_method]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      is_volume:
        source: [stage_processing/is_volume, is_volume]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      rescale:
        source: [stage_processing/rescale, rescale]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      register_aux_view:
        source: [stage_processing/register_aux_view, register_aux_view]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      register_to_primary:
        source: [stage_processing/register_to_primary, register_to_primary]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      channels_per_reg:
        source: [stage_processing/channels_per_reg, channels_per_reg, stage_processing/channel_count, stage_processing/register_aux_view, register_aux_view, stage_processing/aux_tilesets_aux_names, stage_processing/aux_tilesets_aux_channel_count]
        valueFrom: |
          ${
            if (self[1]){
              return self[1];
            } else if (self[2] && self[5] && self[6]) {
              var name = "";
              if(self[3]){
                name = self[3];
              } else {
                name = self[4];
              }
              var aux_ind = self[5].indexOf(name);
              var aux_count = self[6][aux_ind];
              return Math.round(self[2] / aux_count);
            } else if(self[0]){
              return self[0];
            } else {
              return null;
            }
          }
      background_view:
        source: [stage_processing/background_view, background_view]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      register_background:
        source: [stage_processing/register_background, register_background]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      anchor_view:
        source: [stage_processing/anchor_view, anchor_view]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      high_sigma:
       source: [stage_processing/high_sigma, high_sigma]
       valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      deconvolve_iter:
        source: [stage_processing/deconvolve_iter, deconvolve_iter]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      deconvolve_sigma:
        source: [stage_processing/deconvolve_sigma, deconvolve_sigma]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      low_sigma:
        source: [stage_processing/low_sigma, low_sigma]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      rolling_radius:
        source: [stage_processing/rolling_radius, rolling_radius]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      match_histogram:
        source: [stage_processing/match_histogram, match_histogram]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if (self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      tophat_radius:
        source: [stage_processing/tophat_radius, tophat_radius]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
      n_processes:
        source: [stage_processing/n_processes, n_processes]
        valueFrom: |
          ${
            if(self[0]){
              return self[0];
            } else if(self[1]) {
              return self[1];
            } else {
              return null;
            }
          }
    out: [processed_exp]
