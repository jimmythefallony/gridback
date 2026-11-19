#!/usr/bin/env bash
# Summarize GridBack open measurements from this Mac's log.
#
# Usage: ./scripts/perf-report.sh [window]
# window is how far back to look. The default is 1d. Examples: 12h, 30m, 7d.
#
# The summary is cold and warm open time (median and worst), idle CPU over
# the longer gaps, idle CPU over all gaps, average open CPU, and peak memory.
# CPU is a percent of one core. Memory is the physical footprint in megabytes.
# An even count of opens uses the mean of the two middle times.
#
# Closing the grid is part of the idle reading. A short gap is mostly that
# work, so the longer-gap average leaves it out. The all-gaps average keeps
# it. The first open in a run has no earlier close, so it has no idle CPU and
# no gap, and it is left out of both averages. An idle reading with no
# recorded length is kept in the all-gaps average and left out of the longer one.
#
# Pass --lines to summarize measurements on standard input instead of the log.
# ./scripts/perf-report.sh --lines 1d
set -euo pipefail

# Change this one number to move the cutoff. A gap this long, or longer, is
# counted in the longer-gap idle average. Shorter gaps stay in the all-gaps
# average only. The open summary uses this same number of seconds.
minimum_gap_seconds=60

measurement_re='open (cold|warm) ms=([0-9]+) idleCPU=(none|[0-9]+\.[0-9]%) openCPU=([0-9]+\.[0-9]%) memOpenMB=([0-9]+) memCloseMB=([0-9]+) trigger=([a-z]+)'

usage() {
  echo "Usage: ./scripts/perf-report.sh [window]" >&2
  echo "window is a duration such as 1d, 12h, or 30m. The default is 1d." >&2
}

# "6.2%" -> 62 tenths. The log already uses one decimal.
tenths() {
  local value="${1%\%}"
  local whole="${value%%.*}"
  local frac="${value##*.}"
  echo $((10#$whole * 10 + 10#$frac))
}

# Reads measurement lines on stdin. window is only the label in the sentences.
summarize() {
  local window="$1"
  local line idle_tenths open_tenths gap_seconds payload
  local temperature ms idle_field open_field mem_open mem_close
  local rows=""
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    if [[ "$line" =~ $measurement_re ]]; then
      temperature="${BASH_REMATCH[1]}"
      ms="${BASH_REMATCH[2]}"
      idle_field="${BASH_REMATCH[3]}"
      open_field="${BASH_REMATCH[4]}"
      mem_open="${BASH_REMATCH[5]}"
      mem_close="${BASH_REMATCH[6]}"
      idle_tenths="-"
      if [[ "$idle_field" != "none" ]]; then
        idle_tenths="$(tenths "$idle_field")"
      fi
      open_tenths="$(tenths "$open_field")"
      # The gap is part of the measurement, not of any text in front of it.
      payload="${line#*open ${temperature} }"
      gap_seconds="-"
      if [[ "$payload" =~ gapS=([0-9]+) ]]; then
        gap_seconds="${BASH_REMATCH[1]}"
      fi
      rows+="${temperature} ${ms} ${idle_tenths} ${open_tenths} ${mem_open} ${mem_close} ${gap_seconds}"$'\n'
    fi
  done

  printf '%s' "$rows" | awk -v window="$window" -v min_gap="$minimum_gap_seconds" '
    BEGIN { peak = 0 }

    function insert(sorted, n, value,    i) {
      i = n
      while (i >= 1 && sorted[i] > value) {
        sorted[i + 1] = sorted[i]
        i--
      }
      sorted[i + 1] = value
      return n + 1
    }

    function median_text(sorted, n,    mid, sum) {
      if (n % 2 == 1) return sorted[(n + 1) / 2]
      mid = n / 2
      sum = sorted[mid] + sorted[mid + 1]
      if (sum % 2 == 0) return sum / 2
      return int(sum / 2) ".5"
    }

    function timing_line(name, sorted, n) {
      if (n == 0) return name " open: none"
      return name " open: median " median_text(sorted, n) " ms, worst " sorted[n] " ms, count " n
    }

    function round_div(numerator, denominator) {
      return int((numerator * 2 + denominator) / (denominator * 2))
    }

    function format_tenths(tenths,    whole, frac) {
      whole = int(tenths / 10)
      frac = tenths - whole * 10
      return whole "." frac "%"
    }

    function idle_text(sum, n) {
      if (n + 0 == 0) return "none"
      return format_tenths(round_div(sum, n))
    }

    function gaps_text(n) {
      if (n == 1) return "1 gap"
      return n " gaps"
    }

    {
      temp = $1
      ms = $2 + 0
      if (temp == "cold") cold_n = insert(cold, cold_n + 0, ms)
      else if (temp == "warm") warm_n = insert(warm, warm_n + 0, ms)
      else next
      open_sum += $4 + 0
      open_n++
      if ($3 != "-") {
        idle_sum += $3 + 0
        idle_n++
        if ($7 != "-" && $7 + 0 >= min_gap + 0) {
          long_sum += $3 + 0
          long_n++
        }
      }
      if ($5 + 0 > peak) peak = $5 + 0
      if ($6 + 0 > peak) peak = $6 + 0
    }

    END {
      if (open_n + 0 == 0) {
        print "No GridBack open measurements in the last " window "."
        exit
      }
      print "GridBack open measurements, last " window
      print timing_line("cold", cold, cold_n + 0)
      print timing_line("warm", warm, warm_n + 0)
      print "average idle CPU, gaps of " min_gap "s or more: " idle_text(long_sum, long_n) " (" gaps_text(long_n + 0) ")"
      print "average idle CPU, all gaps: " idle_text(idle_sum, idle_n) " (" gaps_text(idle_n + 0) ")"
      print "average open CPU: " format_tenths(round_div(open_sum, open_n))
      print "peak memory: " peak " MB"
    }
  '
}

if [[ "${1:-}" == "--lines" ]]; then
  window="${2:-1d}"
  if [[ $# -gt 2 || ! "$window" =~ ^[0-9]+[smhd]$ ]]; then
    usage
    exit 1
  fi
  summarize "$window"
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

window="${1:-1d}"
if [[ ! "$window" =~ ^[0-9]+[smhd]$ ]]; then
  usage
  exit 1
fi

if ! command -v log >/dev/null 2>&1; then
  echo "The log command is not on this Mac, so there are no measurements to show." >&2
  exit 1
fi

# Notice lines are kept in the log. The predicate is this app and the perf category only.
if ! output=$(log show --last "$window" --style compact \
  --predicate 'subsystem == "com.jimmythefallony.GridBack" AND category == "perf"' 2>/dev/null); then
  echo "Could not read this Mac's log, so there are no measurements to show." >&2
  exit 1
fi

printf '%s\n' "$output" | summarize "$window"
