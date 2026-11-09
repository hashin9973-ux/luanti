#!/usr/bin/env bash
# Inventory the PBR archive without altering or redistributing source assets.
set -euo pipefail

archive="Parallax PBR 64x v2.5.zip"
game_root="games/devtest"
out="build/pbr-audit"
if [[ $# -ge 1 ]]; then archive="$1"; fi
if [[ $# -ge 2 ]]; then game_root="$2"; fi
if [[ $# -ge 3 ]]; then out="$3"; fi
mkdir -p "$out"

if [[ ! -f "$archive" ]]; then
  echo "Asset archive not found: $archive" >&2
  exit 2
fi
command -v unzip >/dev/null
unzip -tqq "$archive"
unzip -Z1 "$archive" | LC_ALL=C sort -f > "$out/archive-files.txt"

awk '
  {
    name=tolower($0)
    if (name ~ /[.](png|tga|jpg|jpeg|bmp|webp)$/) {
      leaf=name
      sub(/^.*[/]/, "", leaf)
      if (leaf ~ /(_normal|_n|_norm|_bump|_height|_h|_parallax|_displacement|_disp|_specular|_spec|_s|_roughness|_rough|_r|_metallic|_metal|_m|_ao|_occlusion)[.][^.]+$/) {
        maps++
        if (leaf ~ /(_normal|_n|_norm|_bump)[.][^.]+$/) normal++
        if (leaf ~ /(_height|_h|_parallax|_displacement|_disp)[.][^.]+$/) height++
        if (leaf ~ /(_specular|_spec|_s)[.][^.]+$/) specular++
        if (leaf ~ /(_roughness|_rough|_r)[.][^.]+$/) roughness++
        if (leaf ~ /(_metallic|_metal|_m)[.][^.]+$/) metallic++
        if (leaf ~ /(_ao|_occlusion)[.][^.]+$/) ao++
      } else {
        base++
        print $0 > base_file
      }
    }
  }
  END {
    printf "base_images=%d\nmap_images=%d\nnormal_candidates=%d\nheight_named_candidates=%d\nspecular_candidates=%d\nroughness_named_candidates=%d\nmetallic_named_candidates=%d\nao_named_candidates=%d\n",
      base,maps,normal,height,specular,roughness,metallic,ao
  }
' base_file="$out/archive-base-images.txt" "$out/archive-files.txt" > "$out/archive-summary.txt"

find "$game_root" -type f \( -iname '*.png' -o -iname '*.tga' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.webp' \) -printf '%P\n' | LC_ALL=C sort > "$out/devtest-textures.txt"
grep -E '^mods/basenodes/textures/.*[.](png|tga|jpg|jpeg|bmp|webp)$' "$out/devtest-textures.txt" > "$out/devtest-basenodes-textures.txt" || true

: > "$out/archive-license-files.txt"
grep -Ei '(^|/)(license|licence|copying|copyright|readme|credits|notice)([.][^/]*)?$' "$out/archive-files.txt" > "$out/archive-license-files.txt" || true

: > "$out/texture-properties-files.txt"
grep -Ei '(^|/)texture[.]properties$' "$out/archive-files.txt" > "$out/texture-properties-files.txt" || true

: > "$out/normal-specular-files.txt"
grep -Ei '(_n|_s)[.](png|tga|jpg|jpeg|bmp|webp)$' "$out/archive-files.txt" > "$out/normal-specular-files.txt" || true

: > "$out/related-source-base-images.txt"
grep -Ei '/(apple|ice|jungle|lava|water|snow|grass|oak|spruce|sand|stone|cobblestone|gravel|leaves|log|planks|ore|dirt)[^/]*[.](png|tga|jpg|jpeg)$' "$out/archive-base-images.txt" > "$out/related-source-base-images.txt" || true

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
  echo "PBR format metadata files:"
  cat "$out/texture-properties-files.txt"
  while IFS= read -r path; do
    echo "--- $path"
    unzip -p "$archive" "$path"
    echo
  done < "$out/texture-properties-files.txt"
  echo
  echo "Related source base-color image filenames:"
  cat "$out/related-source-base-images.txt"
  echo
  echo "First 100 normal/specular map paths:"
  head -n 100 "$out/normal-specular-files.txt"
  echo
  echo "Devtest basenodes texture images:"
  cat "$out/devtest-basenodes-textures.txt"
} > "$out/report.txt"

cat "$out/report.txt"
