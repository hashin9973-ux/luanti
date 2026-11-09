#!/usr/bin/env bash
# Inspect LabPBR-compatible channel data in the source archive.
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
printf 'source_stem,base_present,normal_present,normal_channels,normal_alpha_min,normal_alpha_max,normal_alpha_mean,specular_present,specular_channels\n' > "$csv"

find "$tmp" -type f -name '*_n.png' -print0 | LC_ALL=C sort -z |
while IFS= read -r -d '' normal; do
  rel="$(printf '%s' "$normal" | sed "s|^$tmp/||")"
  stem="$(printf '%s' "$rel" | sed 's/_n\.png$//')"
  base="$tmp/$stem.png"
  spec="$tmp/$stem"_s.png

  normal_channels="$(identify -format '%[channels]' "$normal")"
  alpha_stats="$(convert "$normal" -alpha extract -format '%[fx:minima],%[fx:maxima],%[fx:mean]' info: 2>/dev/null)"
  alpha_min="$(printf '%s' "$alpha_stats" | cut -d, -f1)"
  alpha_max="$(printf '%s' "$alpha_stats" | cut -d, -f2)"
  alpha_mean="$(printf '%s' "$alpha_stats" | cut -d, -f3)"

  if [[ -f "$spec" ]]; then
    spec_present=true
    spec_channels="$(identify -format '%[channels]' "$spec")"
  else
    spec_present=false
    spec_channels=missing
  fi

  if [[ -f "$base" ]]; then
    base_present=true
  else
    base_present=false
  fi

  printf '"%s",%s,true,%s,%s,%s,%s,%s,%s\n' \
    "$rel" "$base_present" "$normal_channels" "$alpha_min" "$alpha_max" \
    "$alpha_mean" "$spec_present" "$spec_channels" >> "$csv"
done

awk -F, '
  NR == 1 { next }
  {
    total++
    if ($2 == "true") bases++
    if ($8 == "true") paired++
    if (tolower($4) ~ /a/) alpha_maps++
    if (($6 + 0) - ($5 + 0) > 0.001) varying_alpha++
  }
  END {
    printf "normal_maps=%d\nbase_color_pairs=%d\nnormal_specular_pairs=%d\nnormal_maps_with_alpha_channel=%d\nnormal_maps_with_varying_alpha=%d\n",
      total,bases,paired,alpha_maps,varying_alpha
  }
' "$csv" > "$out/channel-summary.txt"

awk -F, 'NR > 1 && ($6 + 0) - ($5 + 0) > 0.001 {
  path=$1
  sub(/^"/, "", path)
  sub(/"$/, "", path)
  print path
}' "$csv" > "$out/height-alpha-candidates.txt"

{
  echo "Source archive: $archive"
  echo "Interpretation: LabPBR channel compatibility is inferred, not declared."
  echo "No texture.properties declaration was found by the archive inventory."
  echo
  cat "$out/channel-summary.txt"
  echo
  echo "Sample channel records:"
  head -n 31 "$csv"
} > "$out/report.txt"

cat "$out/report.txt"
