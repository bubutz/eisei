#!/bin/bash

[ "$(id -u)" -ne 0 ] && {
    echo "[ NG ] Please run this scrip as root." 1>&2
    exit 1
}

currhost="$(hostname -s | tr '[:lower:]' '[:upper:]')"
today="$(TZ=Asia/Kuala_Lumpur date +'%Y/%m/%d %H:%M:%S')"

if [ -f "/etc/os-release" ]
    then source /etc/os-release
    else PRETTY_NAME="UNKNOWN"
         VERSION_ID="UNKNOWN"
fi
if [ -z "$1" ]
    then subscription="UNKNOWN"
    else subscription="$1"
fi
if [ -z "$2" ]
    then region="UNKNOWN"
    else region="$2"
fi

if sub="$(subscription-manager identity 2>/dev/null)"; then
    org_name="$(awk -F: '/^org name/ {print $NF}' <<< $sub)"
    envi="$(awk -F: '/^environment name/ {print $NF}' <<< $sub)"
    release_lock="$(subscription-manager release --show 2>/dev/null)"
    release_lock_num="$(awk -F: '{print $NF}' <<< $release_lock | tr -d ' ')"
else
    org_name="UNKNOWN"
    envi="UNKNOWN"
    release_lock="UNKNOWN"
    release_lock_num="UNKNOWN"
fi

if [ -f "/etc/rhsm/rhsm.conf" ]; then
    capsule="$(awk -F= '/^hostname *=/ {print $NF}' /etc/rhsm/rhsm.conf | tr -d ' ')"
    base_url="$(awk -F= '/^baseurl *=/ {print $NF}' /etc/rhsm/rhsm.conf | tr -d ' ')"
    manage_repos="$(awk -F= '/^manage_repos *=/ {print $NF}' /etc/rhsm/rhsm.conf | tr -d ' ')"
else
    capsule="UNKNOWN"
    base_url="UNKNOWN"
    manage_repos="UNKNOWN"
fi

printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s",\n' \
    "$today" \
    "$currhost" \
    "$subcription" \
    "$region" \
    "$PRETTY_NAME" \
    "$VERSION_ID" \
    "$release_lock" \
    "$release_lock_num" \
    "$org_name" \
    "$envi" \
    "$capsule" \
    "$base_url" \
    "$manage_repos
