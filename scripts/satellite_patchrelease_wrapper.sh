#!/bin/bash

short_usage() {
    #
    # Usage
    #
    echo
    echo "OPTIONS:"
    echo "  -h, --help              Print this help text."
    echo
    echo "  -s, --sync-repos        Sync all repositories on the Satellite."
    echo
    echo "  -p, --publish-cv        Publish a new version of Content View. All filters will"
    echo "                            be deleted before publishing."
    echo "                            Specivy \"--keep-filter\" to keep the filter(s)."
    echo
    echo "  -P, --promote-le        Promote lifecyclt to the latest version."
    echo "                            WIP: add ability to specify version"
    echo
    echo "  -o, --organization-id   [MANDATORY] Organization id."
    echo
    echo "  -l, --lifecycle         Lifecycle Environment. Required to promote Lifecycle."
    echo "                            Specify multiple by seperating them with \",\""
    echo
    echo "  -c, --content-view      Specify Content View. Required for publishing Content"
    echo "                            View and promoting Lifecycle Environment."
    echo "                            Specify multiple by seperating them with \",\""
    echo
    echo "      --force             Force \"Publish Content-View\" or \"Promote Lifecycle\""
    echo "                            to run even if pre-task checks failed."
    echo "                            ONLY work with -p|--publish-cv and -P|--promote-le"
    echo
    echo "      --keep-filter       Specify to keep Content view filters when publishing"
    echo "                            Content Views"
    echo "                            By default don't use filter, but could be useful for"
    echo "                            testing purpose."
    echo
    echo "  -g, --logging           This is to enable logging. Output path is mandatory"
    echo "                            when enabling logging option."
    echo
}

usage() {
    #
    # Usage
    #
    echo
    echo "________________________________________________________________________________"
    echo "Bash script to sync Repositories, publish Content Views and promote Lifecycles." 
    echo
    echo "ALLOWED HOST:"

    printf "  %s\n" "${allowed_host[@]}"

    echo "USAGE:"
    echo "  $(basename $0) sync_repo --organization \"ORGANIZATION_LABEL\" [OPTIONS]"
    echo "  $(basename $0) publish_cv -o \"ORGANIZATION_LABEL\" [OPTIONS] -c \"[CONTENT-VIEW]...\""
    echo "  $(basename $0) promote_le -o \"ORGANIZATION_LABEL\" [OPTIONS] -c \"[CONTENT-VIEW]...\""
    echo

    short_usage

    echo
    echo "EXAMPLES:"
    echo "  Sync all available repositories:"
    echo "  $(basename $0) --sync-repos --organization-id \"1\""
    echo "  $(basename $0) -s -o \"2\""
    echo "  $(basename $0) -so \"3\" -g \"/tmp/job.log\""
    echo
    echo "  Publish new version of Content View:"
    echo "  $(basename $0) --publish-cv --organization-id \"1\" --content-view CV1,CV2,CV3"
    echo "  $(basename $0) -p -o \"2\" -c CV4,CV5,CV6"
    echo "  $(basename $0) -po \"3\" -c CV7,CV8,CV9 -g \"/tmp/job.log\""
    echo
    echo "  Promote Lifecycle Environment to the latest:"
    echo "  $(basename $0) --promote-le --organization-id \"1\" --content-view CV1,CV2 --lifecycle DEV,UAT"
    echo "  $(basename $0) -P -o \"2\" -c CV3,CV4 -l SIT,PROD"
    echo "  $(basename $0) -Po \"3\" -c CV5,CV6 -l DR,DEV -g \"/tmp/job.log\""
    echo
    echo "Exit codes:"
    echo "  1  Pre-main errors, such as missing vars, missing args etc"
    echo "  2  Pre-check function error, such as check repo sync state, check filter state etc"
    echo "  3  Main task error, such as repo sync, publish cv, or promote le."
    echo "________________________________________________________________________________"
    echo
    echo

    if [ "${#warn[@]}" -gt 0 ]; then
        echo "${#warn[@]} Warning(s) but won't hinder this script."
        printf "  -  %s\n" "${warn[@]}"
    fi
    echo

    if [ "${#err[@]}" -gt 0 ]; then
        echo "${#err[@]} Error(s), fix them and try running this script again."
        printf "  -  %s\n" "${err[@]}"
    fi
    echo

    exit 1
}

log() {
    #
    # Format output
    #
    local time=""
    local state=""
    local message=""

    case $1 in
        t) time="$(TZ=Asia/Kuala_Lumpur date +'%Y-%m+%d %H:%M:%S')"; shift;;
    esac
    case $1 in
        ok)   state="[ OK ]"; shift;;
        ng)   state="[ NG ]"; shift;;
        info) state="[INFO]"; shift;;
        warn) state="[WARN]"; shift;;
        crit) state="[CRIT]"; shift;;
    esac
    message=$@
    shift $((OPTIND-1))

    printf " %s %s %s\n" "$time" "$state" "$message"
}

sync_repo() {
    #
    # Sync all repo in Satellite
    #
    local sync_err=0
    declare -A repos
    local repo=""
    local repo_id=""
    local repo_name=""
    local repo_key=""

    log t info "Start repositories sync."

    while read repo; do
        repo_id="$(awk -F, '{print $1}' <<< $repo)"
        repo_name="$(awk -F, '{print $2}' <<< $repo)"
        repos["${repo_id}"]="${repo_name}"
    done < <(hammer --csv --no-headers repository list --fields id,name --organization-id $ORG_ID)

    for repo_key in "${!repos[@]}"; do
        hammer repository synchronize --async --organization-id "$ORG_ID" --id "$repo_key" >/dev/null 2>&1
        if [ "$?" -eq 0 ]; then
            log t ok "${repos["$repo_key"]} sync started."
        else
            log t ng "${repos["$repo_key"]} sync failed to start."
            ((sync_err++))
        fi
    done

    if [ "$sync_err" -gt 0 ]; then
        log t crit "Sync repo failed to complete."
        exit 2
    fi

    log t info "Sync repo task completed."
}

verify_repo_sync_state() {
    #
    # Verify if repos are sync status are successful
    #
    local sync_issue=0
    local repo_sync_state=""
    local repo_id=""

    if [ "$force" = "yes" ]; then
        log t warn " **Force -F is enabled. Will ignore sync issues."
    fi

    log t info "Start verifying all repos sync state"

    while read repo_id; do
        repo_sync_state=$(hammer --output csv --no-headers repository info \
            --fields "Id","Label","Content label","Sync/status","Sync/last sync date" \
            --id "$repo_id")
        if grep --quiet ',Success,' <<< $repo_sync_state; then
            log t ok "$(awk -F, '{print $4,$2}' <<< $repo_sync_state)"
        else
            log t ng "$(awk -F, '{print $4,$2}' <<< $repo_sync_state)"
            [ "$force" != "yes" ] && ((sync_issue++))
        fi
    done < <(hammer --csv --no-headers repository list --fields id --organization-id $ORG_ID)

    if [ "$sync_issue" -gt 0 ]; then
        log t crit "Repo sync status check failed."
        exit 2
    fi

    log t info "Repo sync state task completed."
}

verify_filter_state() {
    #
    # Verify if any filter is set for the Content View
    #
    local CV=""
    local filterid=""
    local filter_issue=0
    local filterids=( $(hammer --csv --no-headers content-view filter list --fields "Filter id" \
            --organization-id $ORG_ID --content-view "$CV") )

    if [ "$keep_filter" = "yes" ]; then
        log t warn " ** --keep-filter is enabled. Will ignore filters and won't delete them."
    fi
    if [ "$force" = "yes" ]; then
        log t warn " **Force -F is enabled. Will ignore filters issues."
    fi

    log t info "Start verifying if filters are set for ${CVS[*]}."

    for CV in "${CVS[@]}"; do

        if [ "$(tr -d '[[:space:]]' <<< ${filterids[@]})" = "" ]; then
            log t ok "$CV doesn't have filter."
            continue
        fi

        if [ "$keep_filter" = "yes" ]; then
            log t warn "$CV has filter ${filterids[*]}."
            continue
        fi

        log t warn "$CV : Detected filter, deleting the filters now \"Filter ID: $filterid\"."
        for filterid in "${filterids[@]}"; do
            hammer content-view filter delete --content-view "$CV" --id "$filterid" >/dev/null 2>&1
            if [ "$?" -eq 0 ]; then
                log t ok "$CV filter $filterid deleted."
            else
                log t ng "$CV filter $filterid delete failed."
                if [ "$force" != "yes" ]; then
                    ((filter_issue++))
                fi
            fi
        done
    done

    if [ "$filter_issue" -gt 0 ]; then
        log t crit "Verify filters task failed."
        exit 2
    fi

    log t info "Verify filters task completed."
}

publish_cv() {
    #
    # Publish new version for the Content Views
    #
    local publish_issue=0
    local CV=""
    local cv_cnt="${#CVS[@]}"

    log info "Start publishing ${CVS[*]}."

    verify_repo_sync_state
    verify_filter_state

    publish_issue=()

    for CV in "${CVS[@]}"; do
        hammer content-view publish --async --organization-label "$ORG_LABEL" \
            --name "$CV" --description "$publish_description" >/dev/null 2>&1
        if [ "$?" -eq 0 ]; then
            log t ok "$CV publish started."
        else
            log t ng "$CV publish failed to start."
            ((publish_issue++))
        fi

        ((cv_cnt--))
        if [ "$cv_cnt" -gt 0 ]; then
            log t info "Sleeping for 90 seconds."
            sleep 90
        fi
    done

    if [ "$publish_issue" -gt 0 ]; then
        log t crit "Publish CV task failed."
        exit 3
    fi

    log t info "Publish CV task completed."
}

verify_published_state() {
    #
    # Verify Content View publishing status
    #
    local CV=""
    local msg_state=""
    local lifecycle=""
    local today="$(TZ=Asia/Kuala_Lumpur date +%Y/%m/%d)"
    local published_date=""
    local CV_details=""
    local latest_ver=""
    local publish_issue=0

    if [ "$force" = "yes" ]; then
        log t warn " **Force -F is enabled. Will ignore publish state issues."
    fi

    log t info "Start verifying publish state for ${CVS[*]}."

    for CV in "${CVS[@]}"; do
        CV_details="$(hammer --output csv --no-headers content-view version list \
            --content-view $CV --organization-id $ORG_ID | sort -r 2>/dev/null)"

        latest_ver="$(head -1 <<< $CV_details | awk -F, '{print $1}' 2>/dev/null)"

        published_date="$(hammer content-view info --name $CV --organization-id $ORG_ID |
            grep -E -A2 "Id: *$latest_ver" | awk '/Published:/ {gsub(/ *Published: */,""); print $1}' 2>/dev/null)"

        if [ "$published_date" -ne "$today" ]; then
            if [ "$force" = "yes" ]; then
                msg_state="warn"
            else
                msg_state="ng"
                ((publish_issue++))
            fi
            log t $msg_state "$CV latest version was published on $published_date, not today."
        fi

        for lifecycle in "${lifecycles[@]}"; do
            if grep -E --quiet ",\"$lifecycle(,|\"|$)" <<< $latest_ver; then
                log t ng "$CV : $lifecycle already at the latest version, can't proceed."
                log t ng "$latest_ver"
                ((publish_issue++))
            else
                log t ok "$CV : $lifecycle check ok."
            fi
        done
    done

    if [ "$publish_issue" -gt 0 ]; then
        log t crit "Verify published task failed."
        exit 2
    fi

    log t info "Verify published task completed."
}

promote_le() {
    #
    # Promote lifecycle environments
    #
    local lifecycle=""
    local le_cnt="${#lifecycles[@]}"
    local promote_issue=0
    local msg=""

    verify_published_state

    for lifecycle in "${lifecycles[@]}"; do

        for CV in ${CVS[@]}; do

            local CV_details="$(hammer --output csv --no-headers content-view version list \
                --content-view $CV --organization-id $ORG_ID | sort -r)"
            local latest_ver="$(head -1 <<< $CV_details | awk -F, '{print $1}')"

            hammer content-view version promote \
                --force \
                --organization-id "$ORG_ID" \
                --content-view $CV --id "$latest_ver" \
                --to-lifecycle-environment "$lifecycle" \
                --description "$task_description"

            if [ "$?" -eq 0 ]; then
                log t ok "$CV : $lifecycle promoted."
            else
                log t ng "$CV : $lifecycle failed to promote."
                ((promote_issue++))
            fi

            unset CV_details latest_ver
        done

        ((le_cnt--))
        if [ "$le_cnt" -gt 0 ]; then
            log t info "Sleep for 90 seconds."
            sleep 90
        fi
    done

    if [ "$promote_issue" -gt 0 ]; then
        log t crit "Promote lifecycle task failed."
        exit 3
    fi

    log t crit "Promote lifecycle task completed."
}

#
# Variables
#
allowed_host=(
    "satellite1.example.com"
    "satellite2.example.com"
    "satellite3.example.com"
    )
curhost="$(hostname -f | tr '[:upper:]' '[:lower:]')"
cur_year_mnt="$(TZ=Asia/Kuala_Lumpur date +'%Y %B')"
err=()

ORG=""
ORG_LABEL=""
ORG_ID=""
CVS=()
lifecycles=()
force="no"
task=""
task_description="AUTO: $cur_year_mnt publish RPMs."
delete_filter="no"
savelog="no"
logpath=""
skip_check="no"

#
# Pre-checks
#
[ "$(id -u)" = "0" ] || {
    err+=( "USER: Script not executed as root." )
    skip_check="yes"
}

# printf:
#   \0 - delimited by null instead of newline
# grep:
#   -z/--null-data - Lines are terminated by a zero byte instead of a newline.
#   -F/--fixed-strings - Interpret PATTERNS as fixed strings, not regular expressions.
#   -x/--line-regexp - Select only those matches that exactly match the whole line.
#   --    - marks the end of command-line options, making Grep process "myvalue"
#           as a non-option argument even if it starts with a dash
printf "%s\0" "${allowed_host[@]}" | grep --quiet --fixed-strings --line-regexp --null-data -- '$curhost' || { 
    err+=( "HOST: Script not ran in allowed Satellite server." )
    skip_check="yes"
}

script_name="$(basename $0)"
short_opt="hspPo:l:c:g:"
long_opt="help,sync-repos,publish-cv,promote-le,force,organization-id:,lifecycle:,content-view:,keep-filter,logging:"
opts=$(getopt --options "$short_opt" --longoptions "$long_opt" --name "$script_name" -- "$@") || {
    short_usage
    exit 1
}
eval set -- "$opts"
while true; do
    case "$1" in
        -h | --help)
            usage
            ;;
        -s | --sync-repos)
            task="sync_repo"
            shift 1
            ;;
        -p | --publish-cv)
            task="publish_cv"
            shift 1
            ;;
        -P | --promote-le)
            task="promote_le"
            shift 1
            ;;
        --force)
            force="yes"
            shift 1
            ;;
        -o | --organization-id)
            ORG_ID="$2"
            shift 2
            ;;
        -l | --lifecycle)
            lifecycles+=( $(tr ',' ' ' <<< $2) )  ## TODO: Need more testing, what if name has ' '
            shift 2
            ;;
        -c | --content-view)
            CVS+=( $(tr ',' ' ' <<< $2) ) ## TODO: Need more testing, what if name has ' '
            shift 2
            ;;
        --keep-filter)
            keep_filter="yes"
            shift 1
            ;;
        -g | --logging)
            savelog="yes"
            logpath="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            err+=( "OPTION: Unknown arg in getops \"$1\"" )
            break
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "$task" ]; then
    err+=( "OPTION: No task specified. Needto specify of of the task below:
    -s, --sync-repos
    -p, --publish-cv
    -P, --promote-le" )
else
    case "$task" in
        sync_repo)
            [ "${#CVS[@]}" -gt 0 ] && warn+=( "OPTION: --sync-repo can't use --content-view." )
            [ "${#lifecycles[@]}" -gt 0 ] && warn+=( "OPTION: --sync-repo can't use --lifecycle." )
            [ "$force" = "yes" ] && warn+=( "OPTION: --sync-repo can't use --force." )
            ;;
        publish_cv)
            [ "${#CVS[@]}" -lt 1 ] && err+=( "OPTION: --publish-cv requires --content-view but is not set." )
            [ "${#lifecycles[@]}" -gt 0 ] && warn+=( "OPTION: publish-cv can't --lifecycle." )
            ;;
        promote_le)
            [ "${#CVS[@]}" -lt 1 ] && err+=( "OPTION: --publish-cv requires --content-view but is not set." )
            [ "${#lifecycles[@]}" -lt 1 ] && err+=( "OPTION: --publish-cv requires --lifecycle but is not set." )
            ;;
        *)  err+=( "OPTION: --task \"$task\" is unknown." );;
    esac
fi

if [ -z "$ORG_ID" ]; then
    err+=( "OPTION: --organization-id is compulsory but is not supplied." )
else
    if [ "$skip_check" = "yes" ]; then
        err+=( "OPTION: --organization-id \"$ORG_ID\" is not checked because not on Satellite or is root." )
    else
        org_tmp=$(hammer --no-headers --csv org list --fields "id,label" | grep -E "^${ORG_ID}," 2>/dev/null)
        if [ "$?" -eq 0 ]; then
            ORG_LABEL="$(awk -F, '{print $2}' <<< $org_tmp)"
        else
            err+=( "OPTION: --organization-id \"$ORG_ID\" is invalid." )
        fi
    fi
fi

if [ "$savelog" = "yes" ]; then
    (echo >> "$logpath") 2>/dev/null
    [ "$?" = 0 ] || err+=( "OPTION: --logging unable to access logfile \"$logpath\"." )
fi

[ "${#err[@]}" -gt 0 ] && usage
[ "${#warn[@]}" -gt 0 ] && {
    echo "________________________________________________________________________________"
    echo "${#warn[@]} Warning(s) exists, but won't stop this script from running."
    printf "  -  %s\n" "${warn[@]}"
    echo "________________________________________________________________________________"
}

log t info "Completed pre-checks."
log t info " > Satellite:   $(hostname)"
log t info " > Organiztion:   ${ORG_LABEL}"
log t info " > Organization ID:   ${ORG_ID}"
log t info " > Tasks:   ${task}"
log t info " > Content Views:   ${CVS[*]}"
log t info " > Lifecycles:   ${lifecycles[*]}"

case $savelog in
    no)
        eval $task
        ;;
    yes)
        eval $task 2>&1 | tee -a $logpath
        ;;
    *)
        log t crit "EVAL TASK: savelog variable unexpected value \"$savelog\"."
        exit 2
        ;;
esac

log t info "Script completed."
