#!/bin/bash

# The "promrun" script runs and monitors a specified command

# "promrun" is a wrapper around the GNU 'time' command and principally
# returns statistics generated by 'time'

# Author: MesaGuy (https://github.com/mesaguy)
# Documentation: https://github.com/mesaguy/ansible-prometheus/blob/master/docs/promrun.md
# Source: https://github.com/mesaguy/ansible-prometheus/tree/master/scripts/promrun.sh
# License: MIT
# Version: 0.3 (2020-05-05)

GNU_TIME_COMMAND=/usr/bin/time
if which time > /dev/null 2>&1 ; then
    HAS_TIME=True
fi
TEXTFILE_DIRECTORY="/etc/prometheus/node_exporter_textfiles"

RE_LABEL_NAME="^[a-zA-Z_][a-zA-Z0-9_]*$"
RE_METRIC_NAME="^[a-zA-Z_:][a-zA-Z0-9_:]*$"

function add_label () {
    LABELS="$1"
    LABEL="$2"
    KEY=$(echo $LABEL | cut -d '=' -f 1)
    if [[ ! $KEY =~ $RE_LABEL_NAME ]] ; then
        echo "Label name \"$KEY\" must match regex: $RE_LABEL_NAME" >&2
        exit 2
    fi
    LABELS="$LABELS,$KEY=\"$(echo $LABEL | cut -d "=" -f 2-)\""
    echo "$LABELS"
}

function usage () {
    echo "Usage: $(basename $0) [ -Dhv ] [ -d DESCRIPTION ] [ -i IDENTIFIER ]"
    echo "                      [ -l label_name=LABEL_VALUE ] [ -n NAME ]"
    echo "                      [ -s USERNAME ] COMMAND"
    echo
    echo "NAME (-n) and COMMAND are required and must be specified after arguments"
    echo
    echo " Options:"
    echo '    -d "LONG DESCRIPTION"      Optional description'
    echo "    -D                         Enable dryrun mode"
    echo "    -h                         Print usage"
    echo "    -i IDENTIFIER              Output identifier, needed when multiple jobs"
    echo "                               have the same name, but have different labels"
    echo "    -l label_name=label_value  Optionally add specified labels to node_exporter"
    echo "                               textfile data (May be specified multiple times)"
    echo "    -n NAME                    Required metric name suffix, all metrics are"
    echo "                               prefixed with 'promrun_'"
    echo "    -s USERNAME                Optionally Setup textfile directory file"
    echo "                               permissions for specified username. Must be run"
    echo "                               as root. Run in dryrun mode to inspect changed"
    echo "    -t DIRECTORY               Specify a textfiles directory (Defaults"
    echo "                               to: $TEXTFILE_DIRECTORY)"
    echo "    -v                         Enable verbose mode"
    echo
    echo "Basic example creating $TEXTFILE_DIRECTORY/promrun_ls_test.prom:"
    echo "$(basename $0) -n ls_test ls"
    echo
    echo "Example with description and custom labels:"
    echo "$(basename $0) -n ls_test -l environment=\"Production Environment\" -l test=true -d \"ls command test\" ls"
    echo
    exit 1
}

function end_time_text () {
    printf "# HELP ${METRIC_NAME}_endtime End time in Unix time with microseconds.
# TYPE ${METRIC_NAME}_endtime gauge
${METRIC_NAME}_endtime{$LABELS,promrun_name=\"${NAME}\",promrun=\"endtime\"} $(date +%s.%3N)\n"
}

function start_time_text () {
    # The trailing hash here Comments out the error line left by 'time'
    # command if there is an error. node_exporter fails to parse the
    # error line. For instance:
    # Command exited with non-zero status 1
    printf "# HELP ${METRIC_NAME}_starttime Start time in Unix time with microseconds.
# TYPE ${METRIC_NAME}_starttime gauge
${METRIC_NAME}_starttime{$LABELS,promrun_name=\"${NAME}\",promrun=\"starttime\"} $(date +%s.%3N)\n#"
}

# read the option and store in the variable, $option
while getopts "d:Dhi:l:n:s:t:v" option; do
    case ${option} in
        d)
            DESCRIPTION="$OPTARG"
            ;;
        D)
            DRYRUN=1
            ;;
        h)
            usage
            ;;
        i)
            IDENTIFIER=".${OPTARG}"
            ;;
        l)
            LABELS=$(add_label "$LABELS" "$OPTARG")
            if [ "$?" -ne "0" ] ; then exit 2 ; fi
            ;;
        n)
            NAME="${OPTARG}"
            ;;
        s)
            SETUP_USER="$OPTARG"
            ;;
        t)
            TEXTFILE_DIRECTORY="${OPTARG}"
            ;;
        v)
            VERBOSE=1
            ;;
        \?)
            usage
            ;;
    esac
done

if [ -z "$NAME" ] ; then
    echo "NAME (-n) must be defined" >&2
    exit 2
fi

# Set USER variable if undefined
if [ -z "$USER" ] ; then
    USER=$(whoami)
fi

# Remove any prefixed ',' characters from $LABELS, add 'user' label
if [ -n "$LABELS" ] ; then
    LABELS="${LABELS#,},user=\"${USER}\""
else
    LABELS="user=\"${USER}\""
fi
TEXTFILE_PATH="${TEXTFILE_DIRECTORY}/promrun_${NAME}${IDENTIFIER}.prom"
METRIC_NAME="promrun_${NAME}"

if [ -n "$SETUP_USER" ] ; then
    if [ "$USER" != "root" ] && [ -z "$DRYRUN" ]; then
        echo "Command must be run as root" >&2
        exit 2
    fi
    if ! id $SETUP_USER > /dev/null 2>&1 ; then
        echo "No such user $SETUP_USER" >&2
        exit 2
    fi
    if [ -n "$DRYRUN" ] ; then
        echo "[DRYRUN] touch \"$TEXTFILE_PATH\" \"${TEXTFILE_PATH}.tmp\" && chown $SETUP_USER \"$TEXTFILE_PATH\" \"${TEXTFILE_PATH}.tmp\""
    else
        if [ -n "$VERBOSE" ] ; then
            echo "touch \"$TEXTFILE_PATH\" \"${TEXTFILE_PATH}.tmp\" && chown $SETUP_USER \"$TEXTFILE_PATH\" \"${TEXTFILE_PATH}.tmp\""
        fi
        touch "$TEXTFILE_PATH" "${TEXTFILE_PATH}.tmp" && chown $SETUP_USER "$TEXTFILE_PATH" "${TEXTFILE_PATH}.tmp"
    fi
    exit 0
fi

if [ -z "${@:$OPTIND:1}" ] ; then
    echo "A command to run must be specified" >&2
    exit 2
fi

if [ -z "$HAS_TIME" ] ; then
    echo "GNU 'time' command must be in PATH" >&2
    exit 2
fi

if [ -n "$DESCRIPTION" ] ; then
    LABELS="${LABELS},description=\"$DESCRIPTION\""
fi

if [[ ! $METRIC_NAME =~ $RE_METRIC_NAME ]] ; then
    echo "Metric name \"$METRIC_NAME\" must match regex: $RE_METRIC_NAME" >&2
    exit 2
fi

# Start with a newline in case the command doesn't return a '0' and 'time'
# adds an error line. See comment in the 'start_time_text' function
TIME_FORMAT="
# HELP ${METRIC_NAME}_cpu_kernel_mode_seconds Total number of CPU-seconds that the process spent in kernel mode.
# TYPE ${METRIC_NAME}_cpu_kernel_mode_seconds gauge
${METRIC_NAME}_cpu_kernel_mode_seconds{$LABELS} %S
# HELP ${METRIC_NAME}_elapsed_seconds Elapsed real time (in seconds).
# TYPE ${METRIC_NAME}_elapsed_seconds gauge
${METRIC_NAME}_elapsed_seconds{$LABELS} %e
# HELP ${METRIC_NAME}_cpu_user_mode_seconds Total number of CPU-seconds that the process spent in user mode.
# TYPE ${METRIC_NAME}_cpu_user_mode_seconds gauge
${METRIC_NAME}_cpu_user_mode_seconds{$LABELS} %U
# HELP ${METRIC_NAME}_max_resident_memory_kb Maximum resident set size of the process during its lifetime, in Kbytes.
# TYPE ${METRIC_NAME}_max_resident_memory_kb gauge
${METRIC_NAME}_max_resident_memory_kb{$LABELS} %M
# HELP ${METRIC_NAME}_avg_total_memory_kb Average total (data+stack+text) memory use of the process, in Kbytes.
# TYPE ${METRIC_NAME}_avg_total_memory_kb gauge
${METRIC_NAME}_avg_total_memory_kb{$LABELS} %K
# HELP ${METRIC_NAME}_swapped_from_main_memory_count Number of times the process was swapped out of main memory.
# TYPE ${METRIC_NAME}_swapped_from_main_memory_count gauge
${METRIC_NAME}_swapped_from_main_memory_count{$LABELS} %W
# HELP ${METRIC_NAME}_signals_delivered_to_process_count Number of signals delivered to the process.
# TYPE ${METRIC_NAME}_signals_delivered_to_process_count gauge
${METRIC_NAME}_signals_delivered_to_process_count{$LABELS} %k
# HELP ${METRIC_NAME}_context_switch_count_involuntary_count Number of times the process was context-switched involuntarily (because the time slice expired).
# TYPE ${METRIC_NAME}_context_switch_count_involuntary_count gauge
${METRIC_NAME}_context_switch_count_involuntary_count{$LABELS} %c
# HELP ${METRIC_NAME}_context_switch_count_voluntary_count Number of waits, times that the program was context-switched voluntarily, for instance while waiting for an I/O operation to complete.
# TYPE ${METRIC_NAME}_context_switch_count_voluntary_count gauge
${METRIC_NAME}_context_switch_count_voluntary_count{$LABELS} %w
# HELP ${METRIC_NAME}_filesystem_inputs_count Number of filesystem inputs by the process.
# TYPE ${METRIC_NAME}_filesystem_inputs_count gauge
${METRIC_NAME}_filesystem_inputs_count{$LABELS} %I
# HELP ${METRIC_NAME}_filesystem_outputs_count Number of filesystem outputs by the process.
# TYPE ${METRIC_NAME}_filesystem_outputs_count gauge
${METRIC_NAME}_filesystem_outputs_count{$LABELS} %O
# HELP ${METRIC_NAME}_socket_messages_received_count Number of socket messages received by the process.
# TYPE ${METRIC_NAME}_socket_messages_received_count gauge
${METRIC_NAME}_socket_messages_received_count{$LABELS} %r
# HELP ${METRIC_NAME}_socket_messages_sent_count Number of socket messages sent by the process.
# TYPE ${METRIC_NAME}_socket_messages_sent_count gauge
${METRIC_NAME}_socket_messages_sent_count{$LABELS} %s
# HELP ${METRIC_NAME}_exit_status Exit status of the command.
# TYPE ${METRIC_NAME}_exit_status gauge
${METRIC_NAME}_exit_status{$LABELS,promrun_name=\"${NAME}\",promrun=\"exit\"} %x
# HELP ${METRIC_NAME}_process_avg_size_resident_set_kb Average resident set size of the process, in Kbytes.
# TYPE ${METRIC_NAME}_process_avg_size_resident_set_kb gauge
${METRIC_NAME}_process_avg_size_resident_set_kb{$LABELS} %t
# HELP ${METRIC_NAME}_process_avg_size_unshared_data_area_kb Average size of the process's unshared data area, in Kbytes.
# TYPE ${METRIC_NAME}_process_avg_size_unshared_data_area_kb gauge
${METRIC_NAME}_process_avg_size_unshared_data_area_kb{$LABELS} %D
# HELP ${METRIC_NAME}_process_avg_size_unshared_stack_space_kb Average size of the process's unshared stack space, in Kbytes.
# TYPE ${METRIC_NAME}_process_avg_size_unshared_stack_space_kb gauge
${METRIC_NAME}_process_avg_size_unshared_stack_space_kb{$LABELS} %p
# HELP ${METRIC_NAME}_process_avg_size_shared_text_space_kb Average size of the process's shared text space, in Kbytes.
# TYPE ${METRIC_NAME}_process_avg_size_shared_text_space_kb gauge
${METRIC_NAME}_process_avg_size_shared_text_space_kb{$LABELS} %X
# HELP ${METRIC_NAME}_major_page_fault_count Number of major page faults that occurred while the process was running. These are faults where the page has to be read in from disk.
# TYPE ${METRIC_NAME}_major_page_fault_count gauge
${METRIC_NAME}_major_page_fault_count{$LABELS} %F
# HELP ${METRIC_NAME}_minor_page_fault_count Number of minor, or recoverable, page faults. These are faults for pages that are not valid but which have not yet been claimed by other virtual pages. Thus the data in the page is still valid but the system tables must be updated.
# TYPE ${METRIC_NAME}_minor_page_fault_count gauge
${METRIC_NAME}_minor_page_fault_count{$LABELS} %R
# HELP ${METRIC_NAME}_command Name and command-line arguments of the command being timed. See Label.
# TYPE ${METRIC_NAME}_command gauge
${METRIC_NAME}_command{$LABELS,command=\"%C\"} 1"

if [ -z "$DRYRUN" ] ; then
    start_time_text > "${TEXTFILE_PATH}.tmp"
    $GNU_TIME_COMMAND --append --output="${TEXTFILE_PATH}.tmp" --format="$TIME_FORMAT" ${@:$OPTIND}
    EXIT=$?
    end_time_text >> "${TEXTFILE_PATH}.tmp"
    # Copy contents of temporary file to permanent path
    cp -fp "${TEXTFILE_PATH}.tmp" "$TEXTFILE_PATH"
    if [ -n "$VERBOSE" ] ; then
        cat "${TEXTFILE_PATH}.tmp"
    fi
else
    start_time_text | sed 's/^/\[DRYRUN\] /g' >&2
    TIME_FORMAT=$(echo -e "$TIME_FORMAT" | sed 's/^/\[DRYRUN\] /g')
    $GNU_TIME_COMMAND --format="$TIME_FORMAT" ${@:$OPTIND}
    EXIT=$?
    echo $EXIT > "${TEXTFILE_PATH}.tmp.exit"
    echo "[DRYRUN] cp -fp \"${TEXTFILE_PATH}.tmp\" \"$TEXTFILE_PATH\"" >&2
    end_time_text | sed 's/^/\[DRYRUN\] /g' >&2
fi

# Return same exit signal of subprocess
exit $EXIT
