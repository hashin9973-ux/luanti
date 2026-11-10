#!/usr/bin/env bash
# Inspect LabPBR-compatible channel data and texture dimensions in the archive.
# This reports channel evidence; it does not declare the pack LabPBR-compliant.
set -euo pipefail

archive="Parallax PBR 64x v2.5.zip"
out="build/pbr-channel-audit"
if [[ $# -ge 1 ]]; then archive="$1"; fi
if [[ $# -ge 2 ]]; then out="$2"; fi
mkdir -p "$out"

command -v unzip >/dev/null
command -v identify >/dev/null
command -v convert >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -qq "$archive" '*.png' -d "$tmp"

csv="$out/normal-specular-channel-data.csv"
printf 'source_stem,base_present,base_dimensions,normal_present,normal_dimensions,normal_channels,normal_alpha_min,normal_alpha_max,normal_alpha_mean,specular_present,specular_dimensions,specular_channels,dimensions_match\n' > "$csv"

find "$tmp" -type f -name '*_n.png' -print0 | LC_ALL=C sort -z |
while IFS= read -r -d '' normal; do
  rel="$(printf '%s' "$normal" | sed "s|^$tmp/||")"
  stem="$(printf '%s' "$rel" | sed 's/_n\.png$//')"
  base="$tmp/$stem.png"
  spec="$tmp/$stem"_s.png

  normal_channels="$(identify -format '%[channels]' "$normal")"
  normal_dimensions="$(identify -format '%wx%h' "$normal")"
  alpha_stats="$(convert "$normal" -alpha extract -format '%[fx:minima],%[fx:maxima],%[fx:mean]' info: 2>/dev/null)"
  alpha_min="$(printf '%s' "$alpha_stats" | cut -d, -f1)"
  alpha_max="$(printf '%s' "$alpha_stats" | cut -d, -f2)"
  alpha_mean="$(printf '%s' "$alpha_stats" | cut -d, -f3)"

  if [[ -f "$spec" ]]; then
    spec_present=true
    spec_channels="$(identify -format '%[channels]' "$spec")"
    spec_dimensions="$(identify -format '%wx%h' "$spec")"
  else
    spec_present=false
    spec_channels=missing
    spec_dimensions=missing
  fi

  if [[ -f "$base" ]]; then
    base_present=true
    base_dimensions="$(identify -format '%wx%h' "$base")"
  else
    base_present=false
    base_dimensions=missing
  fi

  if [[ "$base_present" == true && "$spec_present" == true &&
        "$base_dimensions" == "$normal_dimensions" &&
        "$base_dimensions" == "$spec_dimensions" ]]; then
    dimensions_match=true
  else
    dimensions_match=false
  fi

  printf '"%s",%s,%s,true,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$rel" "$base_present" "$base_dimensions" "$normal_dimensions" \
    "$normal_channels" "$alpha_min" "$alpha_max" "$alpha_mean" \
    "$spec_present" "$spec_dimensions" "$spec_channels" "$dimensions_match" >> "$csv"
done

awk -F, '
  NR == 1 { next }
  {
    total++
    if ($2 == "true") bases++
    if ($10 == "true") paired++
    if (tolower($6) ~ /a/) alpha_maps++
    if (($8 + 0) - ($7 + 0) > 0.001) varying_alpha++
    if ($13 == "true") dimensions_match++
    if ($2 == "true" && $10 == "true" && $13 != "true") dimensions_mismatch++
  }
  END {
    printf "normal_maps=%d\nbase_color_pairs=%d\nnormal_specular_pairs=%d\nnormal_maps_with_alpha_channel=%d\nnormal_maps_with_varying_alpha=%d\ncomplete_materials_with_matching_dimensions=%d\ncomplete_materials_with_dimension_mismatch=%d\n",
      total,bases,paired,alpha_maps,varying_alpha,dimensions_match,dimensions_mismatch
  }
' "$csv" > "$out/channel-summary.txt"

awk -F, 'NR > 1 && ($8 + 0) - ($7 + 0) > 0.001 {
  path=$1
  sub(/^"/, "", path)
  sub(/"$/, "", path)
  print path
}' "$csv" > "$out/height-alpha-candidates.txt"

{
  echo "Source archive: $archive"
  echo "Interpretation: LabPBR channel compatibility is inferred, not declared."
  echo "No texture.properties declaration was found by the archive inventory."
  echo "Dimension matches require base, normal, and specular images to share width and height."
  echo
  cat "$out/channel-summary.txt"
  echo
  echo "Sample channel records:"
  head -n 31 "$csv"
} > "$out/report.txt"

cat "$out/report.txt"
