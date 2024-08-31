#!/bin/bash
# Copyright (c) 2023 Qualcomm Innovation Center, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause-Clear

set -o errexit
set -o pipefail

readonly DEFAULT_TARGET=pineapple
readonly DEFAULT_BRANCH=android14-6.1
readonly ACK_PROJECT=kernel/common
readonly ACK_REPO="https://android.googlesource.com/${ACK_PROJECT}"
readonly SYMBOL_LIST=android/abi_gki_aarch64_qcom

ROOT_DIR="$(readlink -f "$(dirname "$0")/../..")"
readonly ROOT_DIR

print_usage() {
	name=$(basename "$0")
	cat << EOF
$name - update the msm-kernel ABI symbol list

This script will pull down the latest symbol list from upstream ACK, update
the list with the latest symbols from the msm-kernel build, then create a
commit suitable for pushing back to ACK.

Usage: $name [-s <SHORT DESCRIPTION>] [-l <LONG DESCRIPTION>] [-b <BUG>]
             [-B <BRANCH>] [-t <TARGET>] [-a SYMBOLS] [-p] [-L] [-u <SHA>]

Options:
    -s SHORT_DESC  Short change description for use in commit message
    -l LONG_DESC   Long change description for use in commit message
    -b BUG         Bug number for use in commit message
    -B BRANCH      ACK branch to target (default $DEFAULT_BRANCH)
    -t TARGET      Target to build for (default $DEFAULT_TARGET)
    -a SYMBOLS     Manually add SYMBOLS to the list (comma-separated)
    -p             Push the commit to ACK automatically
    -L             Do not get the latest list from ACK - just update the
                   list in msm-kernel directly.
    -u             Pass upstream commit SHA into commit message (for use
                   with -L mode). NOTE: this commit must be merged into
                   upstream ACK!

Note: if -s, -l, or -b are omitted, the commit will be done in interactive mode.
EOF
}

tree_has_changes() {
	if git diff --quiet; then
		return 1
	else
		return 0
	fi
}

# Save the current git tree state, stashing if needed
save_tree_state() {
	printf "Saving current tree state... "
	current_ref="$(git rev-parse HEAD)"
	readonly current_ref
	if tree_has_changes; then
		unstash="true"
		git stash push --quiet
	fi
	printf "OK\n"
}

# Restore the git tree state, unstashing if needed
restore_tree_state() {
	if [ -z "$current_ref" ]; then
		return 0
	fi

	printf "Restoring current tree state... "
	git checkout --quiet "$current_ref"
	if [ "$unstash" = "true" ]; then
		git stash pop --quiet
		unstash="false"
	fi
	printf "OK\n"
}

get_remote() {
	git remote -v | awk "\$2==\"$ACK_REPO\" {print \$1; exit}"
}

add_remote() {
	# Get the remote name or create the remote if it's not already there
	if ! remote=$(get_remote) || [ -z "$remote" ]
	then
		remote="ack"
		git remote add "$remote" "$ACK_REPO"
	fi

	printf "Fetching references from upstream ACK...\n"
	git fetch "$remote" -a
}

get_ack_list() {
	branch="$1"

	add_remote
	remote="$(get_remote)"

	save_tree_state
	trap 'restore_tree_state' EXIT

	# Update our symbol list to the ACK tip
	if ! git show "${remote}/${branch}:${SYMBOL_LIST}" > "$SYMBOL_LIST"; then
		git checkout "$SYMBOL_LIST"
		exit 1
	fi

	if tree_has_changes; then
		git commit --quiet -m 'Temporary ACK sync' "$SYMBOL_LIST"
	fi
}

update_stg() {
	target="$1"

	cd "${ROOT_DIR}"

	# Temporarily add the abi_definition_stg option for STG update
	opt='            abi_definition_stg = "android/abi_gki_aarch64.stg"'
	sed -i -e "s|kmi_symbol_list_add_only = True,|&\n${opt},|" msm-kernel/msm_kernel_la.bzl

	./tools/bazel run \
		"//msm-kernel:${target}_gki_abi_nodiff_update" && ret="$?" || ret="$?"

	git -C msm-kernel checkout msm_kernel_la.bzl

	cd "$OLDPWD"
	return "$ret"
}

check_commit_is_merged_in_ack() {
	local -r commit="$1"
	local -r branch="$2"

	add_remote
	remote="$(get_remote)"

	if ! git merge-base --is-ancestor "$commit" "${remote}/${branch}"; then
		printf "error - %s is not merged in ACK!\n" "$commit"
		exit 1
	fi
}

main() {
	while getopts "hs:l:b:p:t:B:a:Lu:" opt; do
		case $opt in
		h)
			print_usage
			exit 0
			;;
		s)
			short_desc="$OPTARG"
			;;
		l)
			long_desc="$OPTARG"
			;;
		b)
			bug="$OPTARG"
			;;
		p)
			push="true"
			;;
		B)
			branch="$OPTARG"
			;;
		t)
			target="$OPTARG"
			;;
		a)
			manual_additions="$OPTARG"
			;;
		L)
			local_list="true"
			;;
		u)
			upstream_commit="$OPTARG"
			;;
		*)
			print_usage
			exit 1
			;;
		esac
	done

	if [ "$local_list" = "true" ]; then
		if [ -z "$upstream_commit" ]; then
			echo error - for local modifications, please pass \
			     the _merged_ ACK commit SHA where the modifications \
			     are completed upstream \(e.g -u \<SHA\>\) | fmt
			exit 1
		fi
	fi

	branch="${branch:-$DEFAULT_BRANCH}"
	target="${target:-$DEFAULT_TARGET}"

	cd "${ROOT_DIR}/msm-kernel"

	if [ "$local_list" != "true" ]; then
		get_ack_list "$branch"
	else
		check_commit_is_merged_in_ack "$upstream_commit" "$branch"
	fi

	# Add any additional symbols passed in by the user (sorting/dedup will
	# be taken care of later by Bazel)
	for s in $(echo "$manual_additions" | tr ',' ' '); do
		printf "  %s\n" "$s" >> android/abi_gki_aarch64_qcom
	done

	# Add new symbols from our build
	(
		cd ..
		./tools/bazel run \
			"//msm-kernel:${target}_gki_abi_update_symbol_list"
	)

	if [ "$local_list" = "true" ]; then
		update_stg "$target"
	fi

	if ! tree_has_changes; then
		printf "No new ABI symbols to add!\n"
		exit 0
	fi

	# Commit our changes
	local -r commit_msg="$(mktemp)"
	cat << EOF > "$commit_msg"
ANDROID: $(basename "$SYMBOL_LIST"): ${short_desc:-<SHORT DESCRIPTION>}

$(printf "%s\n" "${long_desc:-<DESCRIPTION>}" | fmt)

Symbols added:
$(git diff "$SYMBOL_LIST" | grep '^\+ ' | tr '+' ' ')

Bug: ${bug:-<BUG>}
EOF
	if [ "$local_list" = "true" ] && [ -n "$upstream_commit" ]; then
		printf "(cherry picked from commit %s)\n" "$upstream_commit" \
			>> "$commit_msg"
	fi

	if [ -z "$short_desc" ] || [ -z "$long_desc" ] || [ -z "$bug" ]; then
		git commit -e -a -s -F "$commit_msg"
	else
		git commit -a -s -F "$commit_msg"
	fi

	rm -f "$commit_msg"

	# Store a reference to the sync
	local -r sync_commit="$(git rev-parse HEAD)"

	if [ "$local_list" = "true" ]; then
		printf "Ready to push local ABI list modification!\n"
		exit 0
	else
		# Check out the latest from ACK
		git checkout "${remote}/${branch}"

		# Cherry-pick the commit which updated the list
		git cherry-pick "$sync_commit"
		if [ "$push" = "true" ]; then
			git push "$remote" "HEAD:refs/for/${branch}"
			exit 0
		fi

		local -r commit_to_push="$(git rev-parse HEAD)"

		printf "\n\n===========================\n"
		printf "Commit ready to push: %s\n" "$commit_to_push"
		printf "Please double-check it and run the following to push to ACK:\n"
		printf "  git push %s %s:refs/for/%s\n" "$remote" "$commit_to_push" "$branch"
		printf "===========================\n"
	fi
}

main "$@"
