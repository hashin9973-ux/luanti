#!/bin/bash
# Runs a singleplayer session with software-rendering.

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
gameid=${gameid:-devtest}
executable=$dir/../bin/luanti
testspath=$dir/../tests
conf_client=$testspath/client.conf
worldpath=$testspath/world

[ -e "$executable" ] || { echo "executable $executable missing"; exit 1; }

rm -rf "$worldpath"
mkdir -p "$worldpath/worldmods"

# enable a lot of visual effects so we can catch shader errors and other obvious bugs
opts=(
	screen_w=384 screen_h=256 fps_max=5
	active_block_range=1 viewing_range=40 helper_mode=devtest
	opengl_debug=true mip_map=true enable_waving_{leaves,plants,water}=true
	antialiasing=ssaa node_highlighting=halo
	enable_{auto_exposure,bloom,dynamic_shadows,translucent_foliage,volumetric_lighting,water_reflections}=true
	shadow_map_color=true
)
printf '%s\n' "${opts[@]}" "${clientconf:-}" >"$conf_client"

ln -s "$dir/helper_mod" "$worldpath/worldmods/"

export ALSOFT_DRIVERS=null
export LIBGL_ALWAYS_SOFTWARE=true
export MESA_DEBUG=1
if [[ -n "${LUANTI_VISUAL_CAPTURE:-}" ]]; then
	mkdir -p "$(dirname "$LUANTI_VISUAL_CAPTURE")"
	rm -f "$worldpath/pbr_visual_ready" "$worldpath/pbr_visual_capture_done" "$worldpath/pbr_visual_error"
	timeout 25 "$executable" --config "$conf_client" --go --world "$worldpath" --gameid "$gameid" --info &
	game_pid=$!
	ready=0
	for _ in {1..100}; do
		if [[ -f "$worldpath/pbr_visual_ready" ]]; then
			ready=1
			break
		fi
		if [[ -f "$worldpath/pbr_visual_error" ]] || ! kill -0 "$game_pid" 2>/dev/null; then
			break
		fi
		sleep 0.2
	done
	if [[ "$ready" -ne 1 ]]; then
		echo "PBR visual test scene did not become ready."
		kill "$game_pid" 2>/dev/null || true
		wait "$game_pid" 2>/dev/null || true
		exit 1
	fi
	sleep 1
	if ! import -window root "$LUANTI_VISUAL_CAPTURE"; then
		echo "Unable to capture the PBR visual test framebuffer."
		kill "$game_pid" 2>/dev/null || true
		wait "$game_pid" 2>/dev/null || true
		exit 1
	fi
	touch "$worldpath/pbr_visual_capture_done"
	wait "$game_pid"
	r=$?
else
	timeout 25 "$executable" --config "$conf_client" --go --world "$worldpath" --gameid "$gameid" --info
	r=$?
fi
echo "Exit status: $r"
[ $r -eq 124 ] && echo "(timed out)"
[ $r -ne 0 ] && exit 1

echo "Success"
exit 0
