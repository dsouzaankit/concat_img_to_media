Randomized FHD image slideshow (similar to concat_media).

# Layout
#   Canonical:   X:\path\to\concat_img_to_media
#   Deploy:      {image_folder}\slideshow\  (via setup_script_files.py)
#
# After editing, redeploy:
#   python .\setup_script_files.py

# Setup — push slideshow\ into every folder under root_dirs that contains images
# Edit root_dirs in setup_script_files.py (or setup_script_files.local.py, gitignored) first.
python .\setup_script_files.py

# Run — from a deployed slideshow\ folder (images are in the parent dir)
.\rand_img_slideshow.ps1
.\rand_img_slideshow.ps1 -ImageIntervalSeconds 5
.\rand_img_slideshow.ps1 -ImageIntervalSeconds 2.5 -LimitMinutes 30 -MaxRandFileCount 100

# Params
#   -ImageIntervalSeconds  Seconds per image (default: 3)
#   -LimitMinutes          Stop adding clips after this many minutes (default: 60)
#   -MaxRandFileCount      Max clips in the random pick (default: 5000)

# Output
#   <grandparent_folder>_all_pics_<interval>s.mp4  (written two levels above slideshow\)
#   Example:
#     ...\creator_name\creator_pics\slideshow\  ->  ...\creator_name\creator_name_all_pics_3s.mp4

# Behavior (2-pass — required for mixed image resolutions)
#   Pass 1: encode every parent-folder image -> slideshow\standardized\
#           Clip names keep trailing '_' identity + interval:
#             foo_abc_id.jpg       -> abc_id_3s.mp4    (last two segments)
#             3840x4800_abc.jpg    -> abc_3s.mp4       (drop WxH prefix)
#           Encode to %TEMP%\concat_img_slideshow\, copy to a short _up_*_3s.mp4 staging
#           name on the media drive, then rename to the final clip name (cloud-sync-safe).
#           If rename is blocked by a ghost placeholder, the staged _up_*_3s.mp4 is kept.
#           Skips clips that already exist and are readable; removes broken placeholders.
#           %TEMP%\concat_img_slideshow is wiped at start and again when the script finishes
#           (or on concat/publish failure). Per-clip temps are deleted after each publish.
#   Pass 2: shuffle usable standardized clips, concat (-c copy) up to LimitMinutes /
#           MaxRandFileCount. Final MP4 also builds in %TEMP% then copies to grandparent
#           as <folder>_all_pics_<interval>s.mp4.
#
#   Per-image FHD treatment (filter_complex_fhd.txt):
#     - pad to even dims (odd JPEG sizes break yuv420p / zscale)
#     - zscale: JPEG full range -> TV limited + bt709 (avoids deprecated yuvj warning)
#     - blurred full-frame bg + sharp overlay fit; setsar=1 (1920x1080 SAR 1:1)
#   Encode: hevc_qsv (color_range tv / bt709), falls back to libx264. Needs ffmpeg on PATH.
#   ffmpeg is launched via ProcessStartInfo (not & splat) so [vout]/[aout] are not
#   glob-expanded by PowerShell. Console logging is inherited (CreateNoWindow = false).
#   Uses -/filter_complex (required by current ffmpeg essentials; same as concat_media).

# Harmless log noise
#   "unable to attach displaymatrix from EXIF" — mjpeg prints this once per looped frame; ignore.
#   Do not use one-pass concat of raw images + filter_complex: mixed resolutions freeze / fail.

# Rebuild clips after filter / naming changes
#   Delete slideshow\standardized\ (old long / hash-only names are obsolete), then re-run.

# Change default interval permanently
#   Edit param ImageIntervalSeconds in slideshow\rand_img_slideshow.ps1, then re-run setup_script_files.py
