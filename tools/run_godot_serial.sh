#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 ]]; then
	printf 'usage: %s <godot arguments...>\n' "$0" >&2
	exit 64
fi

godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
watchdog_seconds="${GODOT_WATCHDOG_SECONDS:-35}"
max_concurrent="${GODOT_MAX_CONCURRENT:-4}"
slot_wait_seconds="${GODOT_SLOT_WAIT_SECONDS:-180}"
state_dir="${GODOT_RUNNER_STATE_DIR:-${TMPDIR:-/tmp}/riftline-godot-guard-${UID}}"
slots_dir="$state_dir/slots"
log_path=""
child_pid=""
slot_dir=""

if ! [[ "$max_concurrent" =~ ^[1-9][0-9]*$ ]]; then
	printf 'GODOT_MAX_CONCURRENT must be a positive integer, got %q.\n' "$max_concurrent" >&2
	exit 64
fi

if ! [[ "$slot_wait_seconds" =~ ^[1-9][0-9]*$ ]]; then
	printf 'GODOT_SLOT_WAIT_SECONDS must be a positive integer, got %q.\n' "$slot_wait_seconds" >&2
	exit 64
fi

log_path="$(mktemp -t riftline-godot.XXXXXX)"

reclaim_stale_slots() {
	local candidate=""
	local owner_pid=""
	local recorded_child_pid=""
	for candidate in "$slots_dir"/*; do
		[[ -d "$candidate" ]] || continue
		owner_pid="$(cat "$candidate/owner.pid" 2>/dev/null || true)"
		recorded_child_pid="$(cat "$candidate/child.pid" 2>/dev/null || true)"
		if [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
			continue
		fi
		# A killed supervisor must not free its permit while its Godot child is still alive.
		if [[ "$recorded_child_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$recorded_child_pid" 2>/dev/null; then
			continue
		fi
		rm -f "$candidate/owner.pid" "$candidate/child.pid"
		rmdir "$candidate" 2>/dev/null || true
	done
}

acquire_slot() {
	local index=0
	local candidate=""
	local started_at="$(date +%s)"
	umask 077
	mkdir -p "$slots_dir"
	while true; do
		reclaim_stale_slots
		for ((index = 1; index <= max_concurrent; index += 1)); do
			candidate="$slots_dir/$index"
			if mkdir "$candidate" 2>/dev/null; then
				slot_dir="$candidate"
				printf '%s\n' "$$" >"$slot_dir/owner.pid"
				return
			fi
		done
		if (( $(date +%s) - started_at >= slot_wait_seconds )); then
			printf 'Godot runner waited %ss for one of %s permits.\n' "$slot_wait_seconds" "$max_concurrent" >&2
			exit 75
		fi
		sleep 0.1
	done
}

release_slot() {
	if [[ -n "$slot_dir" && -d "$slot_dir" ]]; then
		rm -f "$slot_dir/owner.pid" "$slot_dir/child.pid"
		rmdir "$slot_dir" 2>/dev/null || true
	fi
	slot_dir=""
}

stop_tree() {
	local parent_pid="$1"
	local descendant_pid=""
	for descendant_pid in $(pgrep -P "$parent_pid" 2>/dev/null || true); do
		stop_tree "$descendant_pid"
		kill "$descendant_pid" 2>/dev/null || true
	done
}

cleanup() {
	if [[ -n "$child_pid" ]] && kill -0 "$child_pid" 2>/dev/null; then
		stop_tree "$child_pid"
		kill "$child_pid" 2>/dev/null || true
		for _ in 1 2 3 4 5; do
			if ! kill -0 "$child_pid" 2>/dev/null; then
				break
			fi
			sleep 0.2
		done
		if kill -0 "$child_pid" 2>/dev/null; then
			kill -KILL "$child_pid" 2>/dev/null || true
		fi
		wait "$child_pid" 2>/dev/null || true
	fi
	rm -f "$log_path"
	release_slot
}

trap cleanup EXIT INT TERM

acquire_slot
"$godot_bin" "$@" >"$log_path" 2>&1 &
child_pid=$!
printf '%s\n' "$child_pid" >"$slot_dir/child.pid"
started_at="$(date +%s)"
status=0
while kill -0 "$child_pid" 2>/dev/null; do
	if (( $(date +%s) - started_at >= watchdog_seconds )); then
		printf 'Godot watchdog stopped PID %s after %ss.\n' "$child_pid" "$watchdog_seconds" >&2
		status=124
		break
	fi
	sleep 0.2
done

if [[ "$status" -eq 0 ]]; then
	wait "$child_pid" || status=$?
else
	kill "$child_pid" 2>/dev/null || true
	wait "$child_pid" 2>/dev/null || true
fi

cat "$log_path"
exit "$status"
