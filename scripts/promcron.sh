#!/bin/bash

# The "promcron" script monitors the return code of an exited command

# Author: MesaGuy (https://github.com/mesaguy)
# Documentation: https://github.com/mesaguy/ansible-prometheus/blob/master/docs/promcron.md
# Source: https://github.com/mesaguy/ansible-prometheus/tree/master/scripts/promcron.sh
# License: MIT
# Version: 1.2 (2020-05-05)

TEXTFILE_DIRECTORY="/etc/prometheus/node_exporter_textfiles"
if which sponge > /dev/null 2>&1 ; then
    HAS_SPONGE=True
fi

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
    echo "                      [ -l label_name=LABEL_VALUE ] [ -s USERNAME ] NAME VALUE"
    echo
    echo NAME and VALUE are required and must be specified after arguments
    echo
    echo " Options:"
    echo '    -d "LONG DESCRIPTION"      Optional description'
    echo "    -D                         Enable dryrun mode"
    echo "    -h                         Print usage"
    echo "    -i IDENTIFIER              Output identifier, needed when multiple jobs"
    echo "                               have the same name, but have different labels"
    echo "    -l label_name=label_value  Optionally add specified labels to node_exporter"
    echo "                               textfile data (May be specified multiple times)"
    echo "    -s USERNAME                Optionally Setup textfile directory file"
    echo "                               permissions for specified username. Must be run"
    echo "                               as root. Run in dryrun mode to inspect changed"
    echo "    -t DIRECTORY               Specify a textfiles directory (Defaults"
    echo "                               to: $TEXTFILE_DIRECTORY)"
    echo "    -v                         Enable verbose mode"
    echo
    echo "Basic example creating $TEXTFILE_DIRECTORY/cron_ls_test.prom:"
    echo "* * * * *    ls ; $(basename $0) ls_test \$?"
    echo
    echo "Example with description and custom labels:"
    echo "* * * * *    ls ; $(basename $0) -l environment=\"Production Environment\" -l test=true -d \"ls command test\" ls_test \$?"
    echo
    exit 1
}

# read the option and store in the variable, $option
while getopts "d:Dhi:l:s:t:v" option; do
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

# Must gather NAME and VALUE after other options
NAME="${@:$OPTIND:1}"
VALUE="${@:$OPTIND+1:1}"

# Set USER variable if undefined
if [ -z "$USER" ] ; then
    USER=$(whoami)
fi

METRIC_NAME="cron_${@:$OPTIND:1}"
# Remove any prefixed ',' characters from $LABELS, add 'user' label
if [ -n "$LABELS" ] ; then
    LABELS="${LABELS#,},user=\"${USER}\""
else
    LABELS="user=\"${USER}\""
fi
TEXTFILE_PATH="${TEXTFILE_DIRECTORY}/cron_${NAME}${IDENTIFIER}.prom"

if [ -n "$DESCRIPTION" ] ; then
    LABELS="${LABELS},description=\"$DESCRIPTION\""
fi

if [ -z "$NAME" ] ; then
    echo "NAME must be defined" >&2
    exit 2
fi

if [ -n "$SETUP_USER" ] ; then
    if [ "$USER" != "root" ] && [ -z "$DRYRUN" ]; then
        echo "Command must be run as root" >&2
        exit 2
    fi
    if ! id $SETUP_USER > /dev/null 2>&1 ; then
        echo "No such user $SETUP_USER" >&2
        exit 2
    fi
    if [ "$HAS_SPONGE" == "True" ] ; then
        if [ -n "$DRYRUN" ] ; then
            echo "[DRYRUN] touch \"$TEXTFILE_PATH\" && chown $SETUP_USER \"$TEXTFILE_PATH\""
        else
            if [ -n "$VERBOSE" ] ; then
                echo "touch \"$TEXTFILE_PATH\" && chown $SETUP_USER \"$TEXTFILE_PATH\""
            fi
            touch "$TEXTFILE_PATH" && chown $SETUP_USER "$TEXTFILE_PATH"
        fi
    else
        if [ -n "$DRYRUN" ] ; then
            echo "[DRYRUN] touch \"$TEXTFILE_PATH\" \"${TEXTFILE_PATH}.tmp\" && chown $SETUP_USER \"$TEXTFILE_PATH\" \"${TEXTFILE_PATH}.tmp\""
        else
            if [ -n "$VERBOSE" ] ; then
                echo "touch \"$TEXTFILE_PATH\" \"${TEXTFILE_PATH}.tmp\" && chown $SETUP_USER \"$TEXTFILE_PATH\" \"${TEXTFILE_PATH}.tmp\""
            fi
            touch "$TEXTFILE_PATH" "${TEXTFILE_PATH}.tmp" && chown $SETUP_USER "$TEXTFILE_PATH" "${TEXTFILE_PATH}.tmp"
        fi
    fi
    exit 0
fi

if [ -z "$VALUE" ] ; then
    echo "NAME and VALUE must be defined" >&2
    exit 2
fi

if ! [[ "$VALUE" =~ ^[0-9]+$ ]] || [ "$VALUE" -gt "255" ] ; then
    echo "VALUE must be a return code (Integer between 0 and 255)" >&2
    exit 2
fi

if [[ ! $METRIC_NAME =~ $RE_METRIC_NAME ]] ; then
    echo "Metric name \"$METRIC_NAME\" must match regex: $RE_METRIC_NAME" >&2
    exit 2
fi

END_DATE=$(date +%s.%3N)
DATA="# HELP ${METRIC_NAME}_endtime Unix time in microseconds.
# TYPE ${METRIC_NAME}_endtime gauge
${METRIC_NAME}_endtime{$LABELS,promcron_name=\"${NAME}\",promcron=\"endtime\"} ${END_DATE}
# HELP ${METRIC_NAME} Process return code.
# TYPE ${METRIC_NAME} gauge
$METRIC_NAME{$LABELS,promcron_name=\"${NAME}\",promcron=\"value\"} $VALUE
"

if [ -n "$DRYRUN" ] ; then
    printf "$DATA" | sed 's/^/[DRYRUN] /g'
    if [ "$HAS_SPONGE" == "True" ] ; then
        echo "[DRYRUN] cp -fp \"${TEXTFILE_PATH}.tmp\" \"$TEXTFILE_PATH\""
    fi
    exit 0
elif [ -n "$VERBOSE" ] ; then
    printf "$DATA"
fi

if [ "$HAS_SPONGE" == "True" ] ; then
    printf "$DATA" | sponge "$TEXTFILE_PATH"
else
    printf "$DATA" > "${TEXTFILE_PATH}.tmp"
    if [ -n "$VERBOSE" ] ; then
        echo "cp -fp \"${TEXTFILE_PATH}.tmp\" \"$TEXTFILE_PATH\""
    fi
    cp -fp "${TEXTFILE_PATH}.tmp" "$TEXTFILE_PATH"
fi

# Return exit code that was given as argument
exit $VALUE
