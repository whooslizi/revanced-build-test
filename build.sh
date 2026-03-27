#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

source utils.sh

trap "abort" INT

if [ "${1-}" = "clean" ]; then
	rm -rf "$TEMP_DIR" "$BUILD_DIR" build.md
	exit 0
fi

command -v jq >/dev/null || abort "'jq' is not installed"
command -v java >/dev/null || abort "'java' is not installed"
command -v zip >/dev/null || abort "'zip' is not installed"

set_prebuilts

vtf() {
	if ! isoneof "${1}" "true" "false"; then
		abort "ERROR: '${1}' is not valid for '${2}' (true/false only)"
	fi
}

CONFIG_FILE="${1:-config.toml}"
toml_prep "$CONFIG_FILE" || abort "Config not found: $CONFIG_FILE"

main_config_t=$(toml_get_table_main)

COMPRESSION_LEVEL=$(toml_get "$main_config_t" compression-level || echo "9")
PARALLEL_JOBS=$(toml_get "$main_config_t" parallel-jobs || echo "1")

DEF_PATCHES_VER=$(toml_get "$main_config_t" patches-version || echo "latest")
DEF_CLI_VER=$(toml_get "$main_config_t" cli-version || echo "latest")
DEF_PATCHES_SRC=$(toml_get "$main_config_t" patches-source || echo "ReVanced/revanced-patches")
DEF_CLI_SRC=$(toml_get "$main_config_t" cli-source || echo "ReVanced/revanced-cli")

mkdir -p "$TEMP_DIR" "$BUILD_DIR"

if [ "${2-}" = "--config-update" ]; then
	config_update
	exit 0
fi

: > build.md

mkdir -p module/bin/{arm64,arm,x86,x64}

gh_dl "module/bin/arm64/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-arm64-v8a"
gh_dl "module/bin/arm/cmpr"   "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-armeabi-v7a"
gh_dl "module/bin/x86/cmpr"   "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-x86"
gh_dl "module/bin/x64/cmpr"   "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-x86_64"

idx=0

for table_name in $(toml_get_table_names); do
	[ -z "$table_name" ] && continue

	t=$(toml_get_table "$table_name")

	enabled=$(toml_get "$t" enabled || echo true)
	vtf "$enabled" "enabled"
	[ "$enabled" = false ] && continue

	if (( idx >= PARALLEL_JOBS )); then
		wait -n
		idx=$((idx - 1))
	fi

	declare -A app_args

	patches_src=$(toml_get "$t" patches-source || echo "$DEF_PATCHES_SRC")
	patches_ver=$(toml_get "$t" patches-version || echo "$DEF_PATCHES_VER")
	cli_src=$(toml_get "$t" cli-source || echo "$DEF_CLI_SRC")
	cli_ver=$(toml_get "$t" cli-version || echo "$DEF_CLI_VER")

	PREBUILTS=$(get_prebuilts "$cli_src" "$cli_ver" "$patches_src" "$patches_ver") || {
		echo "Failed to fetch prebuilts"
		continue
	}

	read -r cli_jar patches_jar <<< "$PREBUILTS"

	app_args[cli]=$cli_jar
	app_args[ptjar]=$patches_jar
	app_args[app_name]=$(toml_get "$t" app-name || echo "$table_name")
	app_args[version]=$(toml_get "$t" version || echo "auto")
	app_args[table]=$table_name
	app_args[build_mode]=$(toml_get "$t" build-mode || echo "apk")

	for dl_from in apkmirror archive; do
		if url=$(toml_get "$t" "${dl_from}-dlurl"); then
			app_args[dlurl]=$url
			app_args[dl_from]=$dl_from
			break
		fi
	done

	[ -z "${app_args[dlurl]-}" ] && abort "No download URL for $table_name"

	idx=$((idx + 1))
	build_rv "$(declare -p app_args)" &
done

wait

rm -rf temp/tmp.*

if [ -z "$(ls -A "$BUILD_DIR" 2>/dev/null)" ]; then
	abort "All builds failed"
fi

echo "Build completed successfully"
