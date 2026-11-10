#!/usr/bin/env bash
# Exercise the real Devtest node-material path with every optional-map combination.
set -euo pipefail

archive="Parallax PBR 64x v2.5.zip"
asset_root="Parallax PBR 64x v2.5/assets/minecraft/textures/block"
texture_dir="games/devtest/mods/basenodes/textures"
asset_dir="build/pbr-gl3-assets"
log_dir="build/pbr-gl3-logs"
mkdir -p "$asset_dir" "$log_dir"

for suffix in .png _n.png _s.png; do
  unzip -p "$archive" "$asset_root/stone$suffix" > "$asset_dir/stone$suffix"
  test -s "$asset_dir/stone$suffix"
done

client_config=$'video_driver=opengl3\nenable_pbr=true\nenable_pbr_parallax=true\npbr_parallax_samples=32\npbr_parallax_height_scale=0.05'

run_case() {
  local name="$1"
  local expected="$2"
  local log="$log_dir/$name.log"

  cp "$asset_dir/stone.png" "$texture_dir/default_stone.png"
  rm -f "$texture_dir/default_stone_n.png" "$texture_dir/default_stone_s.png"

  case "$name" in
    full)
      cp "$asset_dir/stone_n.png" "$texture_dir/default_stone_n.png"
      cp "$asset_dir/stone_s.png" "$texture_dir/default_stone_s.png"
      ;;
    normal_only)
      cp "$asset_dir/stone_n.png" "$texture_dir/default_stone_n.png"
      ;;
    specular_only)
      cp "$asset_dir/stone_s.png" "$texture_dir/default_stone_s.png"
      ;;
    no_maps)
      ;;
    *)
      echo "Unknown PBR test case: $name" >&2
      return 2
      ;;
  esac

  echo "=== PBR GL3 CASE: $name ==="
  set +e
  clientconf="$client_config" xvfb-run ./util/test_singleplayer.sh 2>&1 | tee "$log"
  local runtime_status=${PIPESTATUS[0]}
  set -e
  if [[ "$runtime_status" -ne 0 ]]; then
    echo "Devtest singleplayer smoke test failed for $name (exit $runtime_status)." >&2
    return "$runtime_status"
  fi

  # Irrlicht may fall back to a default material after a shader error; fail
  # explicitly if the PBR shader generator reports a compile/link failure.
  if grep -Eiq 'generateShader\(\): failed to generate shaders for .*PBR_(NORMAL|SPECULAR|POM)|Failed to compile the .*PBR_(NORMAL|SPECULAR|POM)' "$log"; then
    echo "PBR/POM GLSL compilation or link failure detected in $name." >&2
    return 1
  fi

  case "$expected" in
    full)
      grep -Eq 'Compiling shaders for .*PBR_NORMAL' "$log"
      grep -Eq 'Compiling shaders for .*PBR_SPECULAR' "$log"
      grep -Eq 'Compiling shaders for .*PBR_POM' "$log"
      ;;
    normal_only)
      grep -Eq 'Compiling shaders for .*PBR_NORMAL' "$log"
      grep -Eq 'Compiling shaders for .*PBR_POM' "$log"
      if grep -Eq 'Compiling shaders for .*PBR_SPECULAR' "$log"; then
        echo "Unexpected specular-map shader in normal-only case." >&2
        return 1
      fi
      ;;
    specular_only)
      grep -Eq 'Compiling shaders for .*PBR_SPECULAR' "$log"
      if grep -Eq 'Compiling shaders for .*PBR_NORMAL|Compiling shaders for .*PBR_POM' "$log"; then
        echo "Unexpected normal/POM shader in specular-only case." >&2
        return 1
      fi
      ;;
    no_maps)
      if grep -Eq 'Compiling shaders for .*PBR_(NORMAL|SPECULAR|POM)' "$log"; then
        echo "Unexpected PBR shader with both maps missing." >&2
        return 1
      fi
      ;;
  esac
  echo "PBR_GL3_CASE=$name PASSED"
}

run_case full full
run_case normal_only normal_only
run_case specular_only specular_only
run_case no_maps no_maps
echo "PBR_GL3_OPTIONAL_MAP_MATRIX=passed"
