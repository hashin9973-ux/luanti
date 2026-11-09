#!/usr/bin/env bash
# Inventory the user-supplied PBR archive without altering or redistributing it.
set -euo pipefail

archive="${1:-Parallax PBR 64x v2.5.zip}"
game_root="${2:-games/devtest}"
out="${3:-build/pbr-audit}"
mkdir -p "$out"

if [[ ! -f "$archive" ]]; then
  echo "Asset archive not found: $archive" >&2
  exit 2
fi
command -v unzip >/dev/null
unzip -tqq "$archive"
unzip -Z1 "$archive" | LC_ALL=C sort -f > "$out/archive-files.txt"

# Preserve every image path in the inventory and classify conventional map suffixes.
awk '
  BEGIN { IGNORECASE=1 }
  /\.(png|tga|jpg|jpeg|bmp|webp)$/ {
    n=$0; sub(/^.*\//, "", n); lower=tolower(n)
    if (lower ~ /(_normal|_n|_norm|_bump|_height|_h|_parallax|_displacement|_disp|_specular|_spec|_s|_roughness|_rough|_r|_metallic|_metal|_m|_ao|_occlusion)(\.[^.]+)$/) {
      maps++
      if (lower ~ /(_normal|_n|_norm|_bump)(\.[^.]+)$/) normal++
      if (lower ~ /(_height|_h|_parallax|_displacement|_disp)(\.[^.]+)$/) height++
      if (lower ~ /(_specular|_spec|_s)(\.[^.]+)$/) specular++
      if (lower ~ /(_roughness|_rough|_r)(\.[^.]+)$/) roughness++
      if (lower ~ /(_metallic|_metal|_m)(\.[^.]+)$/) metallic++
      if (lower ~ /(_ao|_occlusion)(\.[^.]+)$/) ao++
    } else {
      base++
    }
  }
  END {
    printf "base_images=%d\nmap_images=%d\nnormal_candidates=%d\nheight_candidates=%d\nspecular_candidates=%d\nroughness_candidates=%d\nmetallic_candidates=%d\nao_candidates=%d\n",
      base,maps,normal,height,specular,roughness,metallic,ao
  }
' "$out/archive-files.txt" > "$out/archive-summary.txt"

awk '
  BEGIN { IGNORECASE=1 }
  /\\.(png|tga|jpg|jpeg|bmp|webp)$/ {
    n=$0; sub(/^.*\\//, "", n); lower=tolower(n)
    if (lower !~ /(_normal|_n|_norm|_bump|_height|_h|_parallax|_displacement|_disp|_specular|_spec|_s|_roughness|_rough|_r|_metallic|_metal|_m|_ao|_occlusion)(\\.[^.]+)$/)
      print
  }
' "$out/archive-files.txt" > "$out/archive-base-images.txt"

grep -E '^mods/basenodes/textures/.*\\.(png|tga|jpg|jpeg|bmp|webp) -type f \( -iname '*.png' -o -iname '*.tga' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.webp' \) -printf '%P\n' | LC_ALL=C sort > "$out/devtest-textures.txt"

# These files determine redistribution and attribution obligations. Do not assume
# that the engine's LGPL license covers the archive's separate assets.
grep -Ei '(^|/)(license|licence|copying|copyright|readme|credits|notice)(\.[^/]*)?$' "$out/archive-files.txt" > "$out/archive-license-files.txt" || true

{
  echo "Archive: $archive"
  echo "SHA-256: $(sha256sum "$archive" | awk '{print $1}')"
  echo "Archive entries: $(wc -l < "$out/archive-files.txt")"
  echo
  cat "$out/archive-summary.txt"
  echo
  echo "Potential license/attribution entries:"
  cat "$out/archive-license-files.txt"
  echo
  echo "Archive base-color images:"
  cat "$out/archive-base-images.txt"
  echo
  echo "Devtest basenodes texture images:"
  cat "$out/devtest-basenodes-textures.txt"
} > "$out/report.txt"

cat "$out/report.txt"
 "$out/devtest-textures.txt" > "$out/devtest-basenodes-textures.txt" || true

find "$game_root" -type f \( -iname '*.png' -o -iname '*.tga' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.webp' \) -printf '%P\n' | LC_ALL=C sort > "$out/devtest-textures.txt"

# These files determine redistribution and attribution obligations. Do not assume
# that the engine's LGPL license covers the archive's separate assets.
grep -Ei '(^|/)(license|licence|copying|copyright|readme|credits|notice)(\.[^/]*)?$' "$out/archive-files.txt" > "$out/archive-license-files.txt" || true

{
  echo "Archive: $archive"
  echo "SHA-256: $(sha256sum "$archive" | awk '{print $1}')"
  echo "Archive entries: $(wc -l < "$out/archive-files.txt")"
  echo
  cat "$out/archive-summary.txt"
  echo
  echo "Potential license/attribution entries:"
  cat "$out/archive-license-files.txt"
} > "$out/report.txt"

cat "$out/report.txt"
