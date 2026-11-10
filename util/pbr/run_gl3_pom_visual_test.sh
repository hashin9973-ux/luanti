#!/usr/bin/env bash
# Compare a deterministic Devtest stone-room render with POM disabled/enabled.
set -euo pipefail

archive="Parallax PBR 64x v2.5.zip"
asset_root="Parallax PBR 64x v2.5/assets/minecraft/textures/block"
texture_dir="games/devtest/mods/basenodes/textures"
asset_dir="build/pbr-gl3-assets"
log_dir="build/pbr-gl3-logs"
mkdir -p "$asset_dir" "$log_dir"

command -v import >/dev/null || { echo "ImageMagick import is required." >&2; exit 1; }
command -v compare >/dev/null || { echo "ImageMagick compare is required." >&2; exit 1; }

for suffix in .png _n.png _s.png; do
  unzip -p "$archive" "$asset_root/stone$suffix" > "$asset_dir/stone$suffix"
  test -s "$asset_dir/stone$suffix"
done

cp "$asset_dir/stone.png" "$texture_dir/default_stone.png"
cp "$asset_dir/stone_n.png" "$texture_dir/default_stone_n.png"
cp "$asset_dir/stone_s.png" "$texture_dir/default_stone_s.png"

capture_scene() {
  local parallax="$1"
  local output="$2"
  local name="$3"
  local client_config
  client_config=$(printf 'video_driver=opengl3\nenable_pbr=true\nenable_pbr_parallax=%s\npbr_parallax_samples=32\npbr_parallax_height_scale=0.1\nenable_dynamic_shadows=false\nenable_auto_exposure=false\nenable_bloom=false\nenable_volumetric_lighting=false\nenable_water_reflections=false\nantialiasing=none\nnode_highlighting=none\nhelper_mode=pbr_visual' "$parallax")

  echo "=== PBR POM visual capture: $name ==="
  LUANTI_VISUAL_CAPTURE="$output" clientconf="$client_config" xvfb-run -a ./util/test_singleplayer.sh 2>&1 | tee "$log_dir/pom-visual-$name.log"
}

capture_scene false "$log_dir/pom-disabled.png" disabled
capture_scene true "$log_dir/pom-enabled.png" enabled

# Ignore the HUD/window border and compare the central stone-wall region only.
# ImageMagick compare exits 1 for different images; that is the expected result.
set +e
metric_output=$(compare -metric AE -extract 448x320+96+80 \
  "$log_dir/pom-disabled.png" "$log_dir/pom-enabled.png" \
  "$log_dir/pom-difference.png" 2>&1)
compare_status=$?
set -e

if [[ "$compare_status" -gt 1 ]]; then
  echo "ImageMagick compare failed: $metric_output" >&2
  exit 1
fi

changed_pixels=$(printf '%s\n' "$metric_output" | awk 'NR == 1 {print $1}')
if ! [[ "$changed_pixels" =~ ^[0-9]+$ ]]; then
  echo "Unable to parse image-difference metric: $metric_output" >&2
  exit 1
fi
if (( changed_pixels < 10 )); then
  echo "POM visual test failed: only $changed_pixels pixels differ." >&2
  exit 1
fi

echo "PBR_POM_VISUAL_DIFF_PIXELS=$changed_pixels"
echo "PBR_POM_VISUAL_COMPARISON=passed"
