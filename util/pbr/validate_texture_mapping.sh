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
base_list="$audit_dir/archive-base-images.txt"
target_list="$audit_dir/devtest-textures.txt"
height_list="$channel_dir/height-alpha-candidates.txt"
[[ -f "$archive_list" && -f "$base_list" && -f "$target_list" && -f "$height_list" ]]

jq -e '.schema_version == 1 and (.mappings | type == "array")' "$manifest" >/dev/null

zip_root="Parallax PBR 64x v2.5/assets/minecraft/textures"
mapping_tsv="$out/mapping-validation.tsv"
source_tsv="$out/source-material-coverage.tsv"

printf 'devtest_texture\tsource_asset\ttarget_exists\tsource_exists\tnormal_map_exists\tspecular_map_exists\theight_alpha_candidate\n' > "$mapping_tsv"
printf 'source_base_texture\tnormal_map_exists\tspecular_map_exists\theight_alpha_candidate\n' > "$source_tsv"

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
    "$specular_exists" "$height_candidate" >> "$mapping_tsv"
done < <(jq -r '.mappings[] | [.target, (.source_asset // "")] | @tsv' "$manifest")

# Report actual archive-wide companion-map coverage for every detected base image.
while IFS= read -r base_path; do
  [[ -n "$base_path" ]] || continue
  dir="$(dirname "$base_path")"
  leaf="$(basename "$base_path")"
  stem="${leaf%.*}"
  ext="${leaf##*.}"
  normal_path="$dir/${stem}_n.$ext"
  specular_path="$dir/${stem}_s.$ext"

  if grep -Fqx "$normal_path" "$archive_list"; then normal_exists=true; else normal_exists=false; fi
  if grep -Fqx "$specular_path" "$archive_list"; then specular_exists=true; else specular_exists=false; fi
  if grep -Fqx "$normal_path" "$height_list"; then height_candidate=true; else height_candidate=false; fi

  printf '%s\t%s\t%s\t%s\n' \
    "$base_path" "$normal_exists" "$specular_exists" "$height_candidate" >> "$source_tsv"
done < "$base_list"

awk -F '\t' '
  NR == 1 { next }
  {
    total++
    if ($3 == "true") target++
    if ($4 == "true") source++
    if ($3 == "true" && $4 == "true") target_source++
    if ($5 == "true") normal++
    if ($6 == "true") specular++
    if ($7 == "true") height++
    if ($3 != "true" || $4 != "true") unmapped++
    if ($4 == "true" && ($5 != "true" || $6 != "true")) maps_missing++
    if ($4 == "true" && $5 == "true" && $6 == "true") complete_pbr++
    if ($4 == "true" && $5 == "true" && $6 == "true" && $7 == "true") complete_pbr_height++
  }
  END {
    printf "manifest_rows=%d\ntargets_found=%d\nsource_assets_found=%d\ntarget_and_source_found=%d\nnormal_maps_found=%d\nspecular_maps_found=%d\nheight_alpha_candidates=%d\nunmapped_or_missing=%d\nsource_assets_missing_pbr_maps=%d\nsource_assets_with_complete_pbr_maps=%d\nsource_assets_with_complete_pbr_and_height_alpha=%d\n",
      total,target,source,target_source,normal,specular,height,unmapped,maps_missing,complete_pbr,complete_pbr_height
  }
' "$mapping_tsv" > "$out/mapping-summary.txt"

awk -F '\t' '
  NR == 1 { next }
  {
    total++
    if ($2 == "true") normal++
    if ($3 == "true") specular++
    if ($4 == "true") height++
    if ($2 != "true") missing_normal++
    if ($3 != "true") missing_specular++
    if ($4 != "true") missing_height++
    if ($2 == "true" && $3 == "true") paired++
    if ($2 == "true" && $3 == "true" && $4 == "true") paired_height++
  }
  END {
    printf "source_base_textures=%d\nsource_normal_maps=%d\nsource_specular_maps=%d\nsource_height_alpha_candidates=%d\nsource_missing_normal_maps=%d\nsource_missing_specular_maps=%d\nsource_missing_height_alpha=%d\nsource_complete_normal_specular_pairs=%d\nsource_complete_pbr_with_height_alpha=%d\n",
      total,normal,specular,height,missing_normal,missing_specular,missing_height,paired,paired_height
  }
' "$source_tsv" > "$out/source-coverage-summary.txt"

# Repeated targets are always a conflict. Repeated sources are reported
# separately because several Devtest targets can intentionally share an asset.
cut -f1 "$mapping_tsv" | tail -n +2 | LC_ALL=C sort | uniq -c |
  awk '$1 > 1 { print $2 "\t" $1 }' > "$out/duplicate-target-mappings.tsv"
cut -f2 "$mapping_tsv" | tail -n +2 | awk 'NF { print }' | LC_ALL=C sort | uniq -c |
  awk '$1 > 1 { print $2 "\t" $1 }' > "$out/duplicate-source-mappings.tsv"

# Every real Devtest basenodes image must have exactly one manifest row.
LC_ALL=C sort "$audit_dir/devtest-basenodes-textures.txt" > "$out/actual-basenodes-targets.txt"
cut -f1 "$mapping_tsv" | tail -n +2 | LC_ALL=C sort > "$out/mapped-basenodes-targets.txt"
comm -23 "$out/actual-basenodes-targets.txt" "$out/mapped-basenodes-targets.txt" > "$out/unlisted-basenodes-targets.txt"
comm -13 "$out/actual-basenodes-targets.txt" "$out/mapped-basenodes-targets.txt" > "$out/manifest-targets-not-in-game.txt"
{
  echo "basenodes_texture_images=$(wc -l < "$out/actual-basenodes-targets.txt")"
  echo "manifest_target_rows=$(wc -l < "$out/mapped-basenodes-targets.txt")"
  echo "unlisted_basenodes_targets=$(wc -l < "$out/unlisted-basenodes-targets.txt")"
  echo "manifest_targets_not_in_game=$(wc -l < "$out/manifest-targets-not-in-game.txt")"
} > "$out/target-coverage-summary.txt"

{
  echo "Manifest: $manifest"
  echo "Archive: $archive"
  echo "Status: filename/path validation only; candidate mappings need visual review."
  echo
  echo "=== Devtest target mapping summary ==="
  cat "$out/mapping-summary.txt"
  echo
  echo "=== Archive-wide PBR map coverage ==="
  cat "$out/source-coverage-summary.txt"
  echo
  echo "=== Devtest basenodes manifest coverage ==="
  cat "$out/target-coverage-summary.txt"
  echo "Unlisted Devtest targets:"
  cat "$out/unlisted-basenodes-targets.txt"
  echo "Manifest targets absent from Devtest:"
  cat "$out/manifest-targets-not-in-game.txt"
  echo
  echo "=== Duplicate target assignments (conflicts) ==="
  cat "$out/duplicate-target-mappings.tsv"
  echo
  echo "=== Duplicate source assignments (may be intentional) ==="
  cat "$out/duplicate-source-mappings.tsv"
  echo
  echo "Complete mapping validation TSV:"
  cat "$mapping_tsv"
} > "$out/report.txt"

cat "$out/report.txt"

if [[ -s "$out/duplicate-target-mappings.tsv" ]]; then
  echo "Conflicting Devtest target mappings found." >&2
  exit 1
fi
if [[ -s "$out/unlisted-basenodes-targets.txt" || -s "$out/manifest-targets-not-in-game.txt" ]]; then
  echo "Devtest basenodes texture manifest is out of sync with the game." >&2
  exit 1
fi
