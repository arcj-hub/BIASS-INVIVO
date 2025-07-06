#!/bin/bash

# Example usage:
# chmod +x run_segmentation_pipeline.sh
# ./run_segmentation_pipeline.sh

# ---- USER-DEFINED PATHS (EDIT THESE) ----

# Set parent directory where subject folders are stored
parent_directory="/path/to/parent_directory"

# Path to SPM12 TPM.nii file (for prior probability maps)
spm_tpm="/path/to/spm12/tpm/TPM.nii"

# Path to ANTs template and mask
ants_template="/path/to/ANTs/template/T_template.nii.gz"
ants_mask="/path/to/ANTs/template/T_templateProbabilityMask.nii.gz"

# Output CSV for tissue fractions
output_file="${parent_directory}/all_subjects_tissue_fractions.txt"

# ---- DO NOT EDIT BELOW UNLESS CUSTOMIZING ----

# Initialize output file
echo -e "Subject,GM_Fraction,WM_Fraction,CSF_Fraction" > "$output_file"

# Loop through all subject directories
for subject_dir in "${parent_directory}"/*/; do
  subject=$(basename "$subject_dir")

  for session_dir in "${subject_dir}"*/; do
    session=$(basename "$session_dir")
    anat_dir="${session_dir}/anat"

    # Define key files
    structural_file="${anat_dir}/${subject}_${session}_T1w.nii"
    mask_file="${anat_dir}/${subject}_${session}_acq-slaser_svs_space-scanner_mask.nii.gz"
    priors_output="${anat_dir}/SPM_Priors"

    # Skip if anatomical data is missing
    if [ ! -d "$anat_dir" ]; then
      echo "Skipping $subject $session: No anatomical directory."
      continue
    fi

    if [ ! -f "$structural_file" ]; then
      echo "Skipping $subject $session: Structural file not found."
      continue
    fi

    cd "$anat_dir" || continue

    # Brain extraction with ANTs
    echo "Processing $subject $session: Brain extraction"
    antsBrainExtraction.sh -d 3 -a "$structural_file" \
      -m "$ants_mask" \
      -e "$ants_template" \
      -o "T_"

    if [ ! -f "T_BrainExtractionBrain.nii.gz" ]; then
      echo "Error: Brain extraction failed for $subject $session"
      continue
    fi

    # Create prior directory
    mkdir -p "$priors_output"

    # Extract priors from SPM TPM.nii
    echo "Extracting SPM priors for $subject $session"
    for i in {1..6}; do
      fslroi "$spm_tpm" "${priors_output}/prior${i}.nii.gz" $((i-1)) 1
    done

    for i in {1..6}; do
      if [ ! -f "${priors_output}/prior${i}.nii.gz" ]; then
        echo "Error: Missing prior${i} for $subject $session"
        continue 2
      fi
    done

    # Warp SPM priors into native space
    echo "Warping priors to subject space for $subject $session"
    for i in {1..6}; do
      antsRegistrationSyNQuick.sh -d 3 \
        -f "T_BrainExtractionBrain.nii.gz" \
        -m "${priors_output}/prior${i}.nii.gz" \
        -o "${priors_output}/prior${i}"

      mv "${priors_output}/prior${i}Warped.nii.gz" "${priors_output}/priorWarped${i}.nii.gz"
    done

    # Run Atropos segmentation
    echo "Segmenting with Atropos for $subject $session"
    antsAtroposN4.sh -d 3 \
      -a "T_BrainExtractionBrain.nii.gz" \
      -c 3 \
      -x "T_BrainExtractionMask.nii.gz" \
      -p "${priors_output}/priorWarped%d.nii.gz" \
      -o "T_"

    # Compute tissue fractions
    echo "Calculating tissue fractions for $subject $session"
    gm_fraction=$(fslstats "${parent_directory}/T_SegmentationPosteriors1.nii.gz" -k "$mask_file" -m)
    wm_fraction=$(fslstats "${parent_directory}/T_SegmentationPosteriors2.nii.gz" -k "$mask_file" -m)
    csf_fraction=$(fslstats "${parent_directory}/T_SegmentationPosteriors3.nii.gz" -k "$mask_file" -m)

    echo -e "$subject,$gm_fraction,$wm_fraction,$csf_fraction" >> "$output_file"

    echo "Finished $subject $session"
  done
done

echo "All done. Res
