#!/bin/bash
# Ralph loop wrapper - autonomous iteration with context rotation
# Detects available agent CLI, runs the ralph-loop pattern until all criteria pass.
# State persists in files and git between iterations. See the ralph-loop skill.

RALPH_DEFAULT_MAX_ITERATIONS=10
RALPH_DEFAULT_TASK_FILE="RALPH_TASK.md"
RALPH_STATE_DIR=".ralph"

_ralph_detect_agent() {
	# Priority: opencode > claude > cursor-agent
	if command -v opencode &>/dev/null; then
		echo "opencode"
	elif command -v claude &>/dev/null; then
		echo "claude"
	elif command -v cursor-agent &>/dev/null; then
		echo "cursor-agent"
	else
		echo ""
	fi
}

_ralph_count_remaining() {
	local task_file="$1"
	grep -c '\[ \]' "$task_file" 2>/dev/null || echo 0
}

_ralph_run_iteration() {
	local agent="$1"
	local task_file="$2"
	local iteration="$3"
	local prompt="Read the ralph-loop skill. Read ${task_file} and execute the next iteration of the loop. This is iteration ${iteration}."

	case "$agent" in
		opencode)
			opencode -p "$prompt" --output-format stream-json 2>&1
			;;
		claude)
			claude -p "$prompt" --output-format stream-json 2>&1
			;;
		cursor-agent)
			cursor-agent -p "$prompt" 2>&1
			;;
	esac
}

ralph() {
	local task_file="${1:-$RALPH_DEFAULT_TASK_FILE}"
	local max_iterations="${2:-$RALPH_DEFAULT_MAX_ITERATIONS}"

	# Validate task file exists
	if [ ! -f "$task_file" ]; then
		echo "Error: Task file '$task_file' not found."
		echo ""
		echo "Usage: ralph [TASK_FILE] [MAX_ITERATIONS]"
		echo "  TASK_FILE       Path to task file (default: RALPH_TASK.md)"
		echo "  MAX_ITERATIONS  Maximum iterations (default: 10)"
		echo ""
		echo "Create a task file with checkboxes:"
		echo "  ## Success Criteria"
		echo "  1. [ ] First criterion"
		echo "  2. [ ] Second criterion"
		return 1
	fi

	# Detect agent
	local agent
	agent="$(_ralph_detect_agent)"
	if [ -z "$agent" ]; then
		echo "Error: No agent CLI found. Install one of: opencode, claude, cursor-agent"
		return 1
	fi

	# Ensure state directory exists
	mkdir -p "$RALPH_STATE_DIR"
	touch "$RALPH_STATE_DIR/progress.md"
	touch "$RALPH_STATE_DIR/guardrails.md"

	local remaining
	remaining="$(_ralph_count_remaining "$task_file")"
	if [ "$remaining" -eq 0 ]; then
		echo "All criteria already complete in $task_file"
		return 0
	fi

	echo "ralph: starting loop"
	echo "  agent:      $agent"
	echo "  task file:  $task_file"
	echo "  remaining:  $remaining criteria"
	echo "  max iter:   $max_iterations"
	echo ""

	local logfile="$RALPH_STATE_DIR/activity.log"

	for i in $(seq 1 "$max_iterations"); do
		remaining="$(_ralph_count_remaining "$task_file")"
		if [ "$remaining" -eq 0 ]; then
			echo "ralph: all criteria complete after $((i - 1)) iterations"
			echo "$(date -Iseconds) COMPLETE after $((i - 1)) iterations" >> "$logfile"
			return 0
		fi

		echo "=== Iteration $i/$max_iterations ($remaining remaining) ==="
		echo "$(date -Iseconds) START iteration=$i remaining=$remaining agent=$agent" >> "$logfile"

		_ralph_run_iteration "$agent" "$task_file" "$i"
		local exit_code=$?

		echo "$(date -Iseconds) END iteration=$i exit_code=$exit_code" >> "$logfile"

		if [ $exit_code -ne 0 ]; then
			echo "ralph: agent exited with code $exit_code on iteration $i"
			echo "$(date -Iseconds) ERROR iteration=$i exit_code=$exit_code" >> "$logfile"
			# Continue to next iteration (fresh context may help)
		fi

		# Brief pause between iterations to avoid rate limits
		sleep 2
	done

	remaining="$(_ralph_count_remaining "$task_file")"
	if [ "$remaining" -eq 0 ]; then
		echo "ralph: all criteria complete after $max_iterations iterations"
		return 0
	else
		echo "ralph: reached max iterations ($max_iterations). $remaining criteria still unchecked."
		echo "$(date -Iseconds) MAX_ITERATIONS reached remaining=$remaining" >> "$logfile"
		return 1
	fi
}

ralph_status() {
	# Quick status check for the current ralph loop
	local task_file="${1:-$RALPH_DEFAULT_TASK_FILE}"

	if [ ! -f "$task_file" ]; then
		echo "No task file found at $task_file"
		return 1
	fi

	local total done remaining
	total=$(grep -cE '\[(x| )\]' "$task_file" 2>/dev/null || echo 0)
	done=$(grep -c '\[x\]' "$task_file" 2>/dev/null || echo 0)
	remaining=$(grep -c '\[ \]' "$task_file" 2>/dev/null || echo 0)

	echo "ralph status: $done/$total complete ($remaining remaining)"

	if [ -f "$RALPH_STATE_DIR/progress.md" ]; then
		local iterations
		iterations=$(grep -c '^## Iteration' "$RALPH_STATE_DIR/progress.md" 2>/dev/null || echo 0)
		echo "iterations:   $iterations recorded"
	fi

	if [ -f "$RALPH_STATE_DIR/guardrails.md" ]; then
		local rules
		rules=$(grep -c '^- ' "$RALPH_STATE_DIR/guardrails.md" 2>/dev/null || echo 0)
		echo "guardrails:   $rules rules"
	fi

	echo ""
	echo "Remaining criteria:"
	grep '\[ \]' "$task_file" | sed 's/^/  /'
}
