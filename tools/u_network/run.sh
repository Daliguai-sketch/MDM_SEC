#!/usr/bin/env bash
# U-network VCS/Verdi entry point. Inputs are generated outside the U network.
# No Makefile, Python or network access is used by this script.

# Internal job mode: the marker is written only after the actual VCS/simv
# process exits. A submit-only batch wrapper must not masquerade as success.
if [[ ${1:-} == --_execute-job ]]; then
    set +e
    if (( $# < 3 )); then
        echo 'Internal job invocation requires a status file and command.' >&2
        exit 2
    fi
    job_status=$2
    shift 2
    "$@"
    rc=$?
    printf '%s\n' "$rc" > "$job_status" || exit 1
    exit "$rc"
fi

# Older Bash releases on EDA hosts treat an empty array as unbound under -u.
# Inputs are validated explicitly; keep -e and pipefail without that pitfall.
set +u
set -eo pipefail

usage() {
    cat <<'EOF'
Usage: ./run.sh [--check-files | --help]

Default: run 2641 prebuilt packet vectors without a wave, 20 directed packet
cases with native Verdi FSDB (waves.fsdb), and 8 AES blocks with AES FSDB.
Each invocation writes to a new directory under tb/runs/.

Environment overrides:
  VCS                 VCS executable (default: $VCS_HOME/bin/vcs or vcs)
  VERDI_HOME          Verdi installation, used to find novas.tab and pli.a
  NOVAS_HOME          Alternative to VERDI_HOME
  VERDI_PLI_DIR       Explicit PLI directory; or set VERDI_TAB and VERDI_PLI
  BSUB_CMD            Blocking launcher and options, e.g. 'bsub -K -q QUEUE';
                      an empty value means direct. If unset, bsub_cmd is used
                      when available, otherwise execution is direct.
  AES_LOW_AREA        1 (default, 50 cycles), 0 (fast, 5 cycles), or
                      2 (balanced, 5 cycles)
  AES_INTEGRITY_TIMING_OPT  1 (default) uses the integrity timing candidate
                      when AES_LOW_AREA=2; 0 compares the original balanced design
  RUN_FULL            1 (default) runs 2641 packets; 0 skips that regression
  RUN_AES             1 (default) runs AES block test; 0 skips it
  AES_BLOCKS          AES block count for RUN_AES=1, 2..515 (default 8)
  FSDB_FULL           0 (default); 1 also records the full packet regression
  FSDB_MDA            0 (default) or 1 to dump packet buffer memory arrays
  RUN_ROOT            Parent for fresh per-invocation output directories
  VCS_EXTRA_FLAGS     Additional whitespace-separated VCS compilation flags

--check-files checks required files are readable and nonempty, without
launching VCS or checking their contents.
The batch wrapper must wait for the job to finish, propagate its status and
preserve the current working directory on a shared filesystem.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if (( $# > 1 )); then usage >&2; exit 2; fi
case ${1:-} in
    --help|-h) usage; exit 0 ;;
    ''|--check-files) ;;
    *) usage >&2; exit 2 ;;
esac

START_DIR=$(pwd -P)
absolute_from_start() {
    case $1 in
        /*) printf '%s\n' "$1" ;;
        *)  printf '%s/%s\n' "$START_DIR" "$1" ;;
    esac
}
TB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
DESIGN_DIR=$(cd -- "$TB_DIR/.." && pwd -P)
VC_DIR="$DESIGN_DIR/vc"
VECTORS="$TB_DIR/vectors"
[[ -d $VC_DIR ]] || die "Expected vc/ and tb/ under $DESIGN_DIR"

AES_LOW_AREA=${AES_LOW_AREA:-1}
AES_INTEGRITY_TIMING_OPT=${AES_INTEGRITY_TIMING_OPT:-1}
RUN_FULL=${RUN_FULL:-1}
RUN_AES=${RUN_AES:-1}
FSDB_FULL=${FSDB_FULL:-0}
FSDB_MDA=${FSDB_MDA:-0}
AES_BLOCKS=${AES_BLOCKS:-8}
[[ $AES_LOW_AREA == 0 || $AES_LOW_AREA == 1 || $AES_LOW_AREA == 2 ]] ||
    die 'AES_LOW_AREA must be 0, 1 or 2'
for name in AES_INTEGRITY_TIMING_OPT RUN_FULL RUN_AES FSDB_FULL FSDB_MDA; do
    value=${!name}
    [[ $value == 0 || $value == 1 ]] || die "$name must be 0 or 1"
done
[[ $RUN_FULL == 1 || $FSDB_FULL == 0 ]] || die 'FSDB_FULL=1 requires RUN_FULL=1'
[[ $AES_BLOCKS =~ ^[0-9]{1,3}$ ]] || die 'AES_BLOCKS must be 2..515'
AES_BLOCKS=$((10#$AES_BLOCKS))
(( AES_BLOCKS >= 2 && AES_BLOCKS <= 515 )) || die 'AES_BLOCKS must be 2..515'

# Check only the inputs needed by the selected tests. These checks detect
# missing/empty files, not altered contents or mixed versions.
require_file() {
    [[ -f $1 && -r $1 && -s $1 ]] || die "Required file missing, unreadable or empty: $1"
}
echo '=== Check required input files ==='
require_file "$TB_DIR/filelist.f"
require_file "$TB_DIR/tb_mdm_sec.sv"
require_file "$VC_DIR/mdm_sec_rtl.vc"
require_file "$VC_DIR/mdm_sboxes.vh"
require_file "$VC_DIR/mdm_aes_sbox.vh"
require_file "$VC_DIR/mdm_aes_mix_balanced.vh"
while IFS= read -r rtl_path || [[ -n $rtl_path ]]; do
    case $rtl_path in
        ../vc/*.v) require_file "$VC_DIR/${rtl_path#../vc/}" ;;
    esac
done < "$VC_DIR/mdm_sec_rtl.vc"
require_file "$VECTORS/wave_vectors.txt"
if [[ $RUN_FULL == 1 ]]; then require_file "$VECTORS/packet_vectors.txt"; fi
if [[ $RUN_AES == 1 ]]; then
    require_file "$TB_DIR/filelist_aes.f"
    require_file "$TB_DIR/tb_aes_random.sv"
    require_file "$VECTORS/aes_vectors.txt"
fi
if [[ ${1:-} == --check-files ]]; then
    echo 'PASS required files present; contents not checked'
    exit 0
fi

VCS_EXE=${VCS:-}
if [[ -z $VCS_EXE ]]; then
    if [[ -n ${VCS_HOME:-} && -x ${VCS_HOME}/bin/vcs ]]; then
        VCS_EXE=${VCS_HOME}/bin/vcs
    else
        VCS_EXE=vcs
    fi
fi
vcs_resolved=$(command -v "$VCS_EXE") || die "VCS not found: $VCS_EXE"
# Resolve relative executable paths before changing into the fresh run folder.
[[ $vcs_resolved != */* ]] || VCS_EXE=$(absolute_from_start "$vcs_resolved")

pli_dir=${VERDI_PLI_DIR:-}
if [[ -z $pli_dir ]]; then
    for root in "${VERDI_HOME:-}" "${NOVAS_HOME:-}"; do
        [[ -n $root ]] || continue
        for case_dir in LINUX64 linux64; do
            candidate="$root/share/PLI/VCS/$case_dir"
            if [[ -r $candidate/novas.tab && -r $candidate/pli.a ]]; then
                pli_dir=$candidate
                break 2
            fi
        done
    done
fi
VERDI_TAB=${VERDI_TAB:-${pli_dir:+$pli_dir/novas.tab}}
VERDI_PLI=${VERDI_PLI:-${pli_dir:+$pli_dir/pli.a}}
[[ -n $VERDI_TAB && -r $VERDI_TAB && -n $VERDI_PLI && -r $VERDI_PLI ]] ||
    die 'Verdi PLI not found: set VERDI_HOME, VERDI_PLI_DIR, or both VERDI_TAB and VERDI_PLI.'
VERDI_TAB=$(absolute_from_start "$VERDI_TAB")
VERDI_PLI=$(absolute_from_start "$VERDI_PLI")

# A local bsub_cmd, when present, mirrors the user's normal invocation. Sites
# that submit asynchronously should use a synchronous wrapper or bsub -K.
declare -a launcher=()
if [[ ${BSUB_CMD+x} ]]; then
    read -r -a launcher <<< "$BSUB_CMD"
elif command -v bsub_cmd >/dev/null 2>&1; then
    launcher=(bsub_cmd)
fi
if (( ${#launcher[@]} > 0 )); then
    launcher_resolved=$(command -v "${launcher[0]}") || die "Batch launcher not found: ${launcher[0]}"
    # Exported Bash functions have no path; executables need a stable path.
    [[ $launcher_resolved != */* ]] || launcher[0]=$(absolute_from_start "$launcher_resolved")
    printf 'Blocking launcher: '
    printf '%q ' "${launcher[@]}"
    printf '\n'
else
    echo 'Launcher: direct execution'
fi

declare -a extra_flags=()
read -r -a extra_flags <<< "${VCS_EXTRA_FLAGS:-}"
RUN_ROOT=${RUN_ROOT:-$TB_DIR/runs}
mkdir -p -- "$RUN_ROOT"
RUN_ROOT=$(cd -- "$RUN_ROOT" && pwd -P)
RUN_DIR=$(mktemp -d "$RUN_ROOT/mdm_sec_XXXXXXXX")
printf 'Fresh output directory: %s\n' "$RUN_DIR"
trap 'rc=$?; if (( rc != 0 )); then printf "FAILED (exit %s); inspect %s. Partial logs/FSDB are not a pass.\n" "$rc" "$RUN_DIR" >&2; fi' EXIT

# filelist.f uses ../vc from the compilation working directory. These links
# recreate the vc/tb layout in an isolated output directory without rewriting
# the user's filelist or reusing any old simv or waveform.
ln -s -- "$VC_DIR" "$RUN_DIR/vc"
mkdir -- "$RUN_DIR/tb"
ln -s -- "$TB_DIR/tb_mdm_sec.sv" "$RUN_DIR/tb/tb_mdm_sec.sv"

run_job() {
    local label=$1 rc=0 marker="$RUN_DIR/$1.status"
    shift
    printf '\n=== %s ===\n' "$label"
    printf '+ '
    if (( ${#launcher[@]} > 0 )); then printf '%q ' "${launcher[@]}"; fi
    printf '%q ' "$@"
    printf '\n'
    if (( ${#launcher[@]} > 0 )); then
        "${launcher[@]}" "$TB_DIR/run.sh" --_execute-job "$marker" "$@" || rc=$?
    else
        "$TB_DIR/run.sh" --_execute-job "$marker" "$@" || rc=$?
    fi
    (( rc == 0 )) || die "$label command failed with exit $rc"
    [[ -f $marker ]] || die "$label returned before the actual job finished; use a blocking bsub_cmd or bsub -K. The submitted job may still be running."
    [[ $(< "$marker") == 0 ]] || die "$label job failed; inspect its log"
}

cd "$RUN_DIR/tb"
run_job compile "$VCS_EXE" -full64 -sverilog -debug_access+all -kdb -lca +memcbk \
    -timescale=1ns/1ps +define+MDM_SEC_FSDB "${extra_flags[@]}" \
    -P "$VERDI_TAB" "$VERDI_PLI" -top tb_mdm_sec \
    -pvalue+tb_mdm_sec.TEST_MAX_BYTES=2048 \
    "-pvalue+tb_mdm_sec.TEST_AES_LOW_AREA=$AES_LOW_AREA" \
    "-pvalue+tb_mdm_sec.TEST_AES_INTEGRITY_TIMING_OPT=$AES_INTEGRITY_TIMING_OPT" \
    -f "$TB_DIR/filelist.f" -o simv -l compile.log
[[ -x ./simv ]] || die 'VCS did not produce simv; inspect compile.log.'

declare -a mda=() full_wave=()
[[ $FSDB_MDA == 0 ]] || mda=(+FSDB_MDA)
if [[ $FSDB_FULL == 1 ]]; then
    full_wave=("+FSDB=$RUN_DIR/tb/regression.fsdb" "${mda[@]}" +CASE_LOG +fsdb+autoflush)
    echo 'Full-regression FSDB enabled; ensure sufficient disk space.'
fi
if [[ $RUN_FULL == 1 ]]; then
    run_job packet_regression ./simv "+VECTORS=$VECTORS/packet_vectors.txt" \
        +REQUIRE_PARALLEL_COVERAGE "${full_wave[@]}" -no_save -l regression.log
    grep -Fq 'PASS simultaneous transfers by mode 2/3/4/5:' regression.log ||
        die 'Packet parallel-coverage self-check is missing; inspect regression.log.'
    grep -Fq 'PASS 2641 packet vectors (MAX_BYTES=2048)' regression.log ||
        die '2641-packet self-check did not pass; inspect regression.log.'
    [[ $FSDB_FULL == 0 || -s regression.fsdb ]] ||
        die 'regression.fsdb is missing or empty; inspect regression.log.'
else
    echo 'Skipping full packet regression because RUN_FULL=0.'
fi

run_job packet_wave ./simv "+VECTORS=$VECTORS/wave_vectors.txt" \
    +DIRECTED_COVERAGE +CASE_LOG "+FSDB=$RUN_DIR/tb/waves.fsdb" "${mda[@]}" \
    +fsdb+autoflush -no_save -l sim.log
grep -Fxq "DIRECTED configuration MAX_BYTES=2048 AES_LOW_AREA=$AES_LOW_AREA AES_INTEGRITY_TIMING_OPT=$AES_INTEGRITY_TIMING_OPT" sim.log ||
    die 'Packet testbench parameter mismatch; inspect sim.log.'
grep -Fq 'PASS directed waveform cases:' sim.log || die 'Directed coverage failed; inspect sim.log.'
grep -Fq 'PASS 20 packet vectors (MAX_BYTES=2048)' sim.log || die 'Wave cases failed; inspect sim.log.'
[[ -s waves.fsdb ]] || die 'waves.fsdb is missing or empty; check the Verdi PLI and sim.log.'

aes_cycles=50
[[ $AES_LOW_AREA == 1 ]] || aes_cycles=5
if [[ $RUN_AES == 1 ]]; then
    mkdir -- "$RUN_DIR/aes"
    ln -s -- "$TB_DIR/tb_aes_random.sv" "$RUN_DIR/aes/tb_aes_random.sv"
    cd "$RUN_DIR/aes"
    run_job aes_compile "$VCS_EXE" -full64 -sverilog -debug_access+all -kdb -lca +memcbk \
        -timescale=1ns/1ps +define+MDM_SEC_FSDB "${extra_flags[@]}" \
        -P "$VERDI_TAB" "$VERDI_PLI" -top tb_aes_random \
        "-pvalue+tb_aes_random.TEST_AES_LOW_AREA=$AES_LOW_AREA" \
        "-pvalue+tb_aes_random.TEST_BALANCED_TIMING_OPT=$AES_INTEGRITY_TIMING_OPT" \
        -f "$TB_DIR/filelist_aes.f" -o simv -l compile.log
    [[ -x ./simv ]] || die 'VCS did not produce AES simv; inspect aes/compile.log.'
    run_job aes_regression ./simv "+VECTORS=$VECTORS/aes_vectors.txt" \
        "+LIMIT=$AES_BLOCKS" +CASE_LOG "+FSDB=$RUN_DIR/aes/aes_waves.fsdb" \
        +fsdb+autoflush -no_save -l sim.log
    grep -Fxq "AES configuration AES_LOW_AREA=$AES_LOW_AREA BALANCED_TIMING_OPT=$AES_INTEGRITY_TIMING_OPT" sim.log ||
        die 'AES testbench parameter mismatch; inspect aes/sim.log.'
    grep -Fq "PASS $AES_BLOCKS AES blocks, $aes_cycles-cycle latency/II," sim.log ||
        die 'AES self-check/parameter mismatch; inspect aes/sim.log.'
    [[ -s aes_waves.fsdb ]] || die 'AES FSDB is missing or empty; inspect aes/sim.log.'
fi

printf '\nPASS: packet self-check, directed coverage and nonempty FSDB.\n'
printf 'Packet compile log: %s/tb/compile.log\n' "$RUN_DIR"
if [[ $RUN_FULL == 1 ]]; then printf 'Packet regression:  %s/tb/regression.log\n' "$RUN_DIR"; fi
if [[ $FSDB_FULL == 1 ]]; then printf 'Regression FSDB:    %s/tb/regression.fsdb\n' "$RUN_DIR"; fi
printf 'Packet wave log:    %s/tb/sim.log\n' "$RUN_DIR"
printf 'Packet FSDB:        %s/tb/waves.fsdb\n' "$RUN_DIR"
printf 'Packet VCS database: %s/tb/simv.daidir\n' "$RUN_DIR"
if [[ $RUN_AES == 1 ]]; then
    printf 'PASS: %s AES blocks and nonempty AES FSDB.\n' "$AES_BLOCKS"
    printf 'AES log / FSDB:     %s/aes/sim.log  %s/aes/aes_waves.fsdb\n' "$RUN_DIR" "$RUN_DIR"
    printf 'AES VCS database:   %s/aes/simv.daidir\n' "$RUN_DIR"
fi
printf 'Nonempty FSDB alone is not an event/content check; open it in Verdi.\n'
