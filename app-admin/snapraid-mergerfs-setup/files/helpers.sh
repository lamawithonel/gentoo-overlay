# Shared helpers for snapraid-* scripts.  Source this file with:
#   . /usr/local/lib/snapraid-helpers.sh
# Optional: gum (https://github.com/charmbracelet/gum) — when
# present, helpers render rich styled output and prompts.  When
# absent, the helpers fall back to plain printf so non-interactive
# scripts (e.g. snapraid-runner driven by systemd timers) keep
# working.  sr_confirm and any direct gum call sites still require
# gum and will exit non-zero with an install hint.

# Color constants for gum style.  256-color codes.
readonly _SR_HDR_FG='212'
readonly _SR_OK_FG='42'
readonly _SR_WARN_FG='214'
readonly _SR_ERR_FG='196'
readonly _SR_DIM_FG='244'

# Print a styled section header.  Usage: sr_header "Step 1: foo"
sr_header() {
	gum style \
		--foreground "$_SR_HDR_FG" \
		--border-foreground "$_SR_HDR_FG" \
		--border rounded \
		--margin '1 0' --padding '0 2' \
		--bold \
		"$1"
}

# Print a styled status line.  Usage: sr_ok "msg" / sr_warn "msg"
sr_ok()   { gum style --foreground "$_SR_OK_FG"   "OK:    $1"; }
sr_warn() { gum style --foreground "$_SR_WARN_FG" "WARN:  $1"; }
sr_err()  { gum style --foreground "$_SR_ERR_FG"  "ERROR: $1" >&2; }
sr_skip() { gum style --foreground "$_SR_DIM_FG"  "SKIP:  $1"; }
sr_info() { gum style --foreground "$_SR_HDR_FG"  "INFO:  $1"; }

# Render `ls -l` for a /dev/disk/by-id/ symlink so the operator can
# see which kernel device (e.g. /dev/sdc) it currently resolves to.
# Used to make destructive operations less opaque.
sr_show_byid() {
	if [ -e "$1" ]; then
		# shellcheck disable=SC2012
		# `ls -l` is intentional here: we want its symlink-target
		# display ("link -> target") which `find -printf` cannot
		# render as cleanly.
		gum style --foreground "$_SR_DIM_FG" --margin '0 4' \
			"$(ls -l --color=never "$1" 2>/dev/null)"
	else
		sr_err "missing by-id symlink: $1"
	fi
}

# Print a green/red test result.  Usage: sr_green / sr_red.
sr_green() { gum style --foreground "$_SR_OK_FG"  "GREEN: $1"; }
sr_red()   { gum style --foreground "$_SR_ERR_FG" "RED:   $1" >&2; }

# Show a multi-line block of commands with explanation, then prompt
# for confirmation.  Returns 0 on yes, 1 on any negative response
# (including Ctrl-C / SIGINT, which gum returns as 130).
#
# Usage:
#   sr_confirm "Title" "Explanation paragraph." \
#       "command 1" "command 2" "command 3"
sr_confirm() {
	_title="$1"; shift
	_why="$1"; shift

	gum style \
		--foreground "$_SR_WARN_FG" \
		--border-foreground "$_SR_WARN_FG" \
		--border thick \
		--margin '1 0' --padding '1 2' \
		--bold \
		"$_title"

	gum style --margin '0 2' "$_why"

	gum style --foreground "$_SR_DIM_FG" --margin '1 2' \
		'The following commands will run:'

	for _cmd in "$@"; do
		gum style --foreground "$_SR_HDR_FG" --margin '0 4' \
			"\$ $_cmd"
	done

	# Default to No so an absent-minded Enter does not destroy data.
	if gum confirm --default=false \
			--affirmative='Proceed' \
			--negative='Cancel' \
			'Proceed with these commands?'; then
		return 0
	else
		_rc=$?
		# 1 = user chose No, 130 = SIGINT (Ctrl-C).  Either way,
		# we stop gracefully.
		sr_warn "User cancelled (exit ${_rc}).  Stopping."
		return 1
	fi
}

# Idempotency guard: skip a block if a sentinel file exists.  The
# sentinel is created on success.  Use --force to ignore.
#
# Usage:
#   if sr_already_done /var/lib/snapraid/.formatted; then
#       sr_skip 'drives already formatted; pass --force to redo'
#       exit 0
#   fi
sr_already_done() {
	[ -f "$1" ] && [ "${SR_FORCE:-0}" != '1' ]
}

sr_mark_done() {
	mkdir -p "$(dirname "$1")"
	date -Iseconds > "$1"
}

# Parse a --force flag from argv and set SR_FORCE.  Returns the
# remaining args via $SR_REMAINING_ARGS (newline-separated).
sr_parse_force() {
	SR_FORCE=0
	SR_REMAINING_ARGS=''
	for _a in "$@"; do
		if [ "$_a" = '--force' ]; then
			SR_FORCE=1
		else
			SR_REMAINING_ARGS="${SR_REMAINING_ARGS}${_a}
"
		fi
	done
	export SR_FORCE
}

# Require root.
sr_require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		sr_err 'must run as root'
		exit 1
	fi
}

# Common paths and constants.  Sourced by snapraid-* scripts; the
# unused-variable warnings are intentional (this is a library).
# Glob for candidate drives.  Restricted to USB-attached block
# devices; final role assignment is driven by the user via
# snapraid-detect's interactive picker, not by the glob alone.
# shellcheck disable=SC2034
readonly SR_DRIVE_GLOB='/dev/disk/by-id/usb-*'
# shellcheck disable=SC2034
readonly SR_ROLES_FILE='/etc/snapraid-roles.conf'
# shellcheck disable=SC2034
readonly SR_STATE_DIR='/var/lib/snapraid-setup'
# shellcheck disable=SC2034
readonly SR_LOG_DIR='/var/log/snapraid'
# shellcheck disable=SC2034
readonly SR_CONF='/etc/snapraid.conf'
# shellcheck disable=SC2034
readonly SR_PARITY_COUNT=2
# shellcheck disable=SC2034
readonly SR_DATA_COUNT=3

# Plain-text fallbacks when gum is not installed.  These override
# the gum-using definitions above so the helpers themselves never
# fail; sr_confirm becomes a hard error because there is no safe
# non-gum confirmation path in a script that may destroy data.
if ! command -v gum >/dev/null 2>&1; then
	sr_header() { printf '\n=== %s ===\n\n' "$1"; }
	sr_ok()    { printf 'OK:    %s\n' "$1"; }
	sr_warn()  { printf 'WARN:  %s\n' "$1"; }
	sr_err()   { printf 'ERROR: %s\n' "$1" >&2; }
	sr_skip()  { printf 'SKIP:  %s\n' "$1"; }
	sr_info()  { printf 'INFO:  %s\n' "$1"; }
	sr_show_byid() {
		if [ -e "$1" ]; then
			# shellcheck disable=SC2012
			ls -l --color=never "$1" 2>/dev/null \
				| sed 's/^/    /'
		else
			printf 'ERROR: missing by-id symlink: %s\n' "$1" >&2
		fi
	}
	sr_green() { printf 'GREEN: %s\n' "$1"; }
	sr_red()   { printf 'RED:   %s\n' "$1" >&2; }
	sr_confirm() {
		printf 'ERROR: gum is required for interactive confirmation\n' >&2
		printf '       install from https://github.com/charmbracelet/gum\n' >&2
		return 1
	}
fi
