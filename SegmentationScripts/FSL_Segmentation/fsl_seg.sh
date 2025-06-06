#!/bin/bash

# chmod +x BetSeg_fsl3T.sh

# ------------------------------
# USER-DEFINED INPUTS
# ------------------------------

# Set the parent directory for all subjects and sessions (EDIT THIS)
parent_directory="/path/to/your/data"

# Set the output file path (EDIT THIS)
output_txt="${parent_directory}/all_tissue_fractions.txt"

# ------------------------------
# SCRIPT START
# ------------------------------

# Create the output file with headers
echo -e "Subject\tSession\tGM\tWM\tCSF" > "$output_txt"

# Loop through each subject directory
for subject_directory in "$parent_directory"/*/; do
    subject_id=$(basename "$subject_directory")

    # Loop through each session directory
    for session_directory in "$subject_directory"/*/; do
        session_id=$(basename "$session_directory")

        # Define paths to T1w image and mask file
        anat_dir="${session_directory}/anat"
        t1w_image="${anat_dir}/${subject_id}_${session_id}_T1w.nii"
        mask_file="${anat_dir}/${subject_id}_${session_id}_acq-slaser_svs_space-scanner_mask.nii.gz"

        # Check for required files
        if [ -f "$t1w_image" ] && [ -f "$mask_file" ]; then
            echo "Processing $subject_id $session_id"

            # Run BET
            bet "$t1w_image" "${anat_dir}/${subject_id}_${session_id}_bet.nii.gz" -f 0.5
            echo "BET completed for $subject_id $session_id"

            # Run FAST segmentation
            fast -t 1 -n 3 "${anat_dir}/${subject_id}_${session_id}_bet.nii.gz"
            echo "FAST segmentation completed for $subject_id $session_id"

            # Compute tissue fractions
            gm_fraction=$(fslstats "${anat_dir}/${subject_id}_${session_id}_bet_pve_1.nii.gz" -k "$mask_file" -m)
            wm_fraction=$(fslstats "${anat_dir}/${subject_id}_${session_id}_bet_pve_2.nii.gz" -k "$mask_file" -m)
            csf_fraction=$(fslstats "${anat_dir}/${subject_id}_${session_id}_bet_pve_0.nii.gz" -k "$mask_file" -m)

            # Append to output file
            echo -e "$subject_id\t$session_id\t$gm_fraction\t$wm_fraction\t$csf_fraction" >> "$output_txt"
            echo "Tissue fractions saved for $subject_id $session_id"
        else
            echo "Missing files for $subject_id $session_id. Skipping."
        fi
    done
done

echo "Batch processing complete. Results saved in: $output_txt"
