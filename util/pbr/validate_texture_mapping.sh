#!/usr/bin/env bash
# Validate candidate source-to-Devtest texture names against the committed archive.
# This is an inventory check, not a visual/material correctness certification.
set -euo pipefail

archive="Parallax PBR 64x v2.5.zip"
manifest="util/pbr/devtest_texture_mapping.json"
audit_dir="build/pbr-audit"
channel_dir="build/pbr-channel-audit"
out="build/pbr-mapping-audit"
mkdir -p "$out"

command -v jq >/dev/null
archive_list="$audit_dir/archive-files.txt"
target_list="$audit_dir/devtest-textures.txt"
height_list="$channel_dir/height-alpha-candidates.txt"
[[ -f "$archive_list" && -f "$target_list" && -f "$height_list" ]]

jq -e '.schema_version == 1 and (.mappings | type == "array")' "$manifest" >/dev/null

zip_root="Parallax PBR 64x v2.5/assets/minecraft/textures"
result="$out/mapping-validation.tsv"
printf 'devtest_texture\tsource_asset\ttarget_exists\tsource_exists\tnormal_map_exists\tspecular_map_exists\theight_alpha_candidate\n' > "$result"

while IFS="$(printf '\t')" read -r target source; do
  [[ -n "$target" ]] || continue

  if grep -Fqx "$target" "$target_list"; then target_exists=true; else target_exists=false; fi

  if [[ -z "$source" ]]; then
    source_exists=false
    normal_exists=false
    specular_exists=false
    height_candidate=false
  else
    source_path="$zip_root/$source"
    if grep -Fqx "$source_path" "$archive_list"; then source_exists=true; else source_exists=false; fi

    normal_source="$(printf '%s' "$source" | sed 's/[.]png$/_n.png/')"
    specular_source="$(printf '%s' "$source" | sed 's/[.]png$/_s.png/')"
    normal_path="$zip_root/$normal_source"
    specular_path="$zip_root/$specular_source"

    if grep -Fqx "$normal_path" "$archive_list"; then normal_exists=true; else normal_exists=false; fi
    if grep -Fqx "$specular_path" "$archive_list"; then specular_exists=true; else specular_exists=false; fi
    if grep -Fqx "$normal_path" "$height_list"; then height_candidate=true; else height_candidate=false; fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$target" "$source" "$target_exists" "$source_exists" "$normal_exists" \
    "$specular_exists" "$height_candidate" >> "$result"
done < <(jq -r '.mappings[] | [.target, (.source_asset // "")] | @tsv' "$manifest")

awk -F '\t' '
  NR == 1 { next }
  {
    total++
    if ($3 == "true") target++
    if ($4 == "true") source++
    if ($5 == "true") normal++
    if ($6 == "true") specular++
    if ($7 == "true") height++
    if ($3 != "true" || $4 != "true") unmapped++
    if ($4 == "true" && ($5 != "true" || $6 != "true")) maps_missing++
  }
  END {
    printf "mapping_rows=%d\ntargets_found=%d\nsource_assets_found=%d\nnormal_maps_found=%d\nspecular_maps_found=%d\nheight_alpha_candidates=%d\nunmapped_or_missing=%d\nsource_assets_missing_pbr_maps=%d\n",
      total,target,source,normal,specular,height,unmapped,maps_missing
  }
' "$result" > "$out/mapping-summary.txt"

cut -f2 "$result" | awk 'NF { print }' | LC_ALL=C sort | uniq -c |
  awk '$1 > 1 { print $2 "\t" $1 }' > "$out/duplicate-source-mappings.tsv"

{
  echo "Manifest: $manifest"
  echo "Archive: $archive"
  echo "Status: filename/path validation only; candidate mappings need visual review."
  echo
  cat "$out/mapping-summary.txt"
  echo
  echo "Duplicate source assignments (some may be intentional overlays/liquids):"
  cat "$out/duplicate-source-mappings.tsv"
  echo
  echo
  echo "Complete mapping validation TSV:"
  cat "$result"
} > "$out/report.txt"

cat "$out/report.txt"
