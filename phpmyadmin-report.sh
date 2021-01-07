#!/bin/bash
##
# @author William Desportes <williamdes@wdes.fr>
##

set -e

PROJECTS='
{
    "github.com": [
        "phpmyadmin/phpmyadmin",
        "phpmyadmin/phpmyadmin-security",
        "phpmyadmin/docker",
        "phpmyadmin/website",
        "phpmyadmin/sql-parser",
        "phpmyadmin/motranslator",
        "phpmyadmin/private",
        "phpmyadmin/shapefile",
        "phpmyadmin/simple-math",
        "phpmyadmin/localized_docs",
        "phpmyadmin/error-reporting-server",
        "phpmyadmin/twig-i18n-extension"
    ],
    "gitlab.com": [],
    "salsa.debian.org": [
        "phpmyadmin-team/phpmyadmin",
        "phpmyadmin-team/twig-i18n-extension",
        "phpmyadmin-team/mariadb-mysql-kbs",
        "phpmyadmin-team/google-recaptcha",
        "phpmyadmin-team/motranslator",
        "phpmyadmin-team/sql-parser",
        "phpmyadmin-team/shapefile",
        "phpmyadmin-team/tcpdf"
    ]
}
'

DATA_STORE='{
    "providers": []
}'

# -- Functions -- #

checkBinary() {
	if ! command -v ${1} &> /dev/null
	then
		quitError "${1} could not be found"
	fi
}

quitError() {
	echo -e "\033[0;31m[ERROR] ${1}\033[0m" >&2
	exit ${2:-1}
}

logDebug() {
    if [ ${QUIET_MODE} -eq 1 ]; then
        return;
    fi
	echo -e "\033[1;35m[DEBUG] ${1}\033[0m" >&2
}

logInfo() {
    if [ ${QUIET_MODE} -eq 1 ]; then
        return;
    fi
	echo -e "\033[1;35m[INFO] ${1}\033[0m" >&2
}

checkBinaries() {
	checkBinary 'jq'
	checkBinary 'curl'
	checkBinary 'sed'
	checkBinary 'gawk'
	checkBinary 'date'
}

detectCheckConfig() {
    local filename="$1"
    if [ ! -f "${filename}" ]; then
        quitError "Missing config file at: ${filename}"
    fi
}

readConfig() {
    local filename="$1"
    local callback="$2"
    local config=$(gawk -F= '{
                if ($1 ~ /^\[/)
                    section=tolower(gensub(/\[(.+)\]/,"\\1",1,$1))
                else if ($1 !~ /^$/ && $1 !~ /^;/) {
                    gsub(/^[ \t]+|[ \t]+$/, "", $1);
                    gsub(/[\[\]]/, "", $1);
                    gsub(/^[ \t]+|[ \t]+$/, "", $2);
                    if (configuration[section][$1] == "")
                        configuration[section][$1]=$2
                    else
                        configuration[section][$1]=configuration[section][$1]" "$2}
                }
                END {
                    ORS=""
                    for (section_name in configuration) {
                        printf "{\"name\": \"%s\"",section_name
                        for (key in configuration[section_name]) {
                            printf ",\"%s\": \"%s\"",key,configuration[section_name][key];
                        }
                        print "}"
                        print "!----!"
                    }
                }' "${filename}")
    local IFS="!----!"
    for configBlock in $config; do
        $callback "$configBlock"
    done
}

getBlockName() {
   jq -r -c '.name' <<< "${1}"
}

getBlockType() {
   jq -r -c '.type' <<< "${1}"
}

getBlockToken() {
   jq -r -c '.token' <<< "${1}"
}

getBlockHost() {
   # https://github.com/stedolan/jq/issues/354#issuecomment-46641827
   jq -r -c '.host | select (.!=null)' <<< "${1}"
}

getBlockUser() {
   jq -r -c '.user' <<< "${1}"
}

getBlockAuthorEmail() {
   jq -r -c '.authorEmail' <<< "${1}"
}

urlEncode() {
    local data="$1"
    jq -rn --arg x "${data}" '$x|@uri'
}

getGitLabHost() {
    local host="$1"
    if [ -z "${host}" ]; then
        # Default GitLab host
        host="gitlab.com"
    fi
    echo "${host}"
}

processConfigBlock() {
    local configBlockIn="$1"
    local blockName="$(getBlockName "$configBlockIn")"
    local blockType="$(getBlockType "$configBlockIn")"
    if [[ $blockName == "gitlab" ]] || [[ $blockType == "gitlab" ]]; then
        processGitLab "$configBlockIn"
    fi
    if [[ $blockName == "github" ]] || [[ $blockType == "github" ]]; then
        processGitHub "$configBlockIn"
    fi
}

processGitLab() {
    logDebug "Processing GitLab projects..."
    local configBlockIn="$1"
    local host="$(getGitLabHost $(getBlockHost "$configBlockIn"))"
    while read -r projectSlug; do
        processGitLabProject "$configBlockIn" "$projectSlug"
    done< <(jq -c -r ".[\"${host}\"] | .[]" <<< "${PROJECTS}")
    logDebug "Processing GitLab projects done."
}

processGitHub() {
    logDebug "Processing GitHub projects..."
    local configBlockIn="$1"
    while read -r projectSlug; do
        processGitHubProject "$configBlockIn" "$projectSlug"
    done< <(jq -c -r '.["github.com"] | .[]' <<< "${PROJECTS}")
    logDebug "Processing GitHub projects done."
}

callGitHubApi() {
    local configBlockIn="$1"
    local path="$2"
    local token="$(getBlockToken "$configBlockIn")"
    curl -H "Authorization: token ${token}" -Ss "https://api.github.com/${path}"
}

callGitLabApi() {
    local configBlockIn="$1"
    local path="$2"
    local token="$(getBlockToken "$configBlockIn")"
    local host="$(getGitLabHost $(getBlockHost "$configBlockIn"))"
    curl -H "Authorization: Bearer ${token}" -Ss "https://${host}/api/${path}"
}

processGitLabProject() {
    local configBlockIn="$1"
    local projectSlug="$2"
    local projectSlugUrl="$(urlEncode "${projectSlug}")"
    local authorEmail="$(getBlockAuthorEmail "$configBlockIn")"
    logDebug "Processing GitLab project: ${projectSlug}"
    local commits=$(callGitLabApi "$configBlockIn" "v4/projects/${projectSlugUrl}/repository/commits?since=${START_DATE}&until=${END_DATE}")
    commits="$(jq -c "map(. | select(.author_email==\"${authorEmail}\"))" <<< "${commits}")"
    gitLabCommitsToStorage "${commits}" "${projectSlug}"
}

processGitHubProject() {
    local configBlockIn="$1"
    local projectSlug="$2"
    local username="$(getBlockUser "$configBlockIn")"
    logDebug "Processing GitHub project: ${projectSlug}"
    local commits=$(callGitHubApi "$configBlockIn" "repos/${projectSlug}/commits?author=${username}&per_page=100&since=${START_DATE}&until=${END_DATE}")
    gitHubCommitsToStorage "${commits}" "${projectSlug}"
}

gitHubCommitsToStorage() {
    local commits="$1"
    local projectSlug="$2"
    mergeData "$(jq -c "map({sha: .sha, message: .commit.message | split(\"\\n\")[0], html_url: .html_url, cdate: .commit.committer.date }) | {type: \"GitHub\", slug: \"${projectSlug}\", data: . }" <<< "${commits}")"
    # | map("- [" + .sha + "](" + .html_url + "): " + .message + " (" + .cdate + ")") | .[]' <<< "${commits}"
}

gitLabCommitsToStorage() {
    local commits="$1"
    local projectSlug="$2"

    mergeData "$(jq -c "map({sha: .id, message: .title, html_url: .web_url, cdate: .committed_date }) | {type: \"GitLab\", slug: \"${projectSlug}\", data: . }" <<< "${commits}")"
}

mergeData() {
    local dataIn="$1"
    echo "$DATA_STORE" > ~data-main.json
    if [ "$(jq -c '.data | length' <<< "$dataIn" )" == "0" ]; then
        # Do not merge empty datasets
        return
    fi
    jq -c '{providers: [.]}' <<< "$dataIn" > ~data.json
    DATA_STORE="$(jq -c -s '[.[].providers[]] | {providers: .}' ~data-main.json ~data.json)"
    rm ~data.json ~data-main.json
}

printFinalData() {
    logDebug "Data count: $(echo "${DATA_STORE}" | jq '.providers | length')"
    echo "${DATA_STORE}" | jq
}

renderFinalData() {
    printf '# Commit list\n'
    while read -r provider; do
        local slug="$(jq -r -c '.slug' <<< "${provider}")"
        local type="$(jq -r -c '.type' <<< "${provider}")"
        printf '\n## %s (%s)\n\n' "${slug}" "${type}"
        while read -r dataEntry; do
            local message="$(jq -r '.message' <<< "${dataEntry}")"
            if [[ "${message}" =~ "Translated using Weblate" ]]; then
                continue;
            fi

            local sha="$(jq -r '.sha' <<< "${dataEntry}")"
            jq --arg sha "${sha:0:10}" -r '"- [" + $sha + " - " + .message + "](" + .html_url + ")"' <<< "${dataEntry}"
        done< <(jq -c '.data[]' <<< "${provider}")
    done< <(jq -c '.providers[]' <<< "${DATA_STORE}")
}

loadDates() {
    if [ "${MONTH_MODE}" == "none" ]; then
        quitError "You need to specify a month mode, using cli: --{current,last,next}-month"
    fi

    logDebug "Using month mode: ${MONTH_MODE}"

    # Source: http://databobjr.blogspot.com/2011/06/get-first-and-last-day-of-month-in-bash.html

    # Dates use format: YYYY-MM-DDTHH:MM:SSZ

    if [ "${MONTH_MODE}" == "last" ]; then
        # Source: https://stackoverflow.com/a/67101078/5155484
        # Example (current date: 04/july(07)/2021 23:27): 2021-06-01T00:00:00Z
        START_DATE="$(date -d "-1 month -$(($(date +%d)-1)) days" +"%Y-%m-%dT00:00:00Z")"
        # Example (current date: 04/july(07)/2021 23:27): 2021-06-30T00:00:00Z
        END_DATE="$(date -d "-$(date +%d) days -0 month" +"%Y-%m-%dT23:59:59Z")"
    fi

    if [ "${MONTH_MODE}" == "current" ]; then
        # Source: https://stackoverflow.com/a/67101078/5155484
        # Example (current date: 04/july(07)/2021 23:27): 2021-07-01T00:00:00Z
        START_DATE="$(date -d "-0 month -$(($(date +%d)-1)) days" +"%Y-%m-%dT00:00:00Z")"
        # Example (current date: 04/july(07)/2021 23:27): 2021-07-31T00:00:00Z
        END_DATE="$(date -d "-$(date +%d) days +1 month" +"%Y-%m-%dT23:59:59Z")"
    fi

    if [ "${MONTH_MODE}" == "next" ]; then
        # Source: https://stackoverflow.com/a/67101078/5155484
        # Example (current date: 04/july(07)/2021 23:27): 2021-08-01T00:00:00Z
        START_DATE="$(date -d "+1 month -$(($(date +%d)-1)) days" +"%Y-%m-%dT00:00:00Z")"
        # Example (current date: 04/july(07)/2021 23:27): 2021-08-31T00:00:00Z
        END_DATE="$(date -d "-$(date +%d) days +2 month" +"%Y-%m-%dT23:59:59Z")"
    fi

    if [ "${MONTH_MODE}" == "custom" ]; then
        START_DATE="${START_DATE}T00:00:00Z"
        END_DATE="${END_DATE}T23:59:59Z"
    fi

    logDebug "Start date (Y-m-d): ${START_DATE}"
    logDebug "End date (Y-m-d): ${END_DATE}"
}

# -- Init -- #

checkBinaries

# -- Default values -- #

OUTPUT_JSON_DATA="/dev/null"
OUTPUT_RENDER="/dev/stdout"
MONTH_MODE="none"
QUIET_MODE="0"
# Tilde expansion: https://unix.stackexchange.com/a/151852/155610
CONFIG_FILE=~/.config/phpmyadmin

# -- Load values from CLI args -- #

# Source: https://stackoverflow.com/a/31024664/5155484
while [[ $# > 0 ]]
do
    key="$1"
    while [[ ${key+x} ]]
    do
        case $key in
            --last-month)
                MONTH_MODE="last"
                ;;
            --current-month)
                MONTH_MODE="current"
                ;;
            --next-month)
                MONTH_MODE="next"
                ;;
            --next-month)
                MONTH_MODE="next"
                ;;
            --start-date)
                MONTH_MODE="custom"
                START_DATE="$2"
                shift # option has parameter
                ;;
            --end-date)
                MONTH_MODE="custom"
                END_DATE="$2"
                shift # option has parameter
                ;;
            -q|--quiet)
                QUIET_MODE="1"
                ;;
            --config)
                CONFIG_FILE="$2"
                shift # option has parameter
                ;;
            --output)
                OUTPUT_RENDER="$2"
                shift # option has parameter
                ;;
            --output-json)
                OUTPUT_JSON_DATA="$2"
                shift # option has parameter
                ;;
            -h|--help)
                echo 'Usage:'
                echo '  Help: ./phpmyadmin-report.sh -h'
                echo '  Help: ./phpmyadmin-report.sh --help'
                echo '  Turn off debug: ./phpmyadmin-report.sh --quiet'
                echo '  Turn off debug: ./phpmyadmin-report.sh -q'
                echo '  Custom config: ./phpmyadmin-report.sh --config /home/user/report-config.conf'
                echo '  Custom output: ./phpmyadmin-report.sh --output /home/user/report-output.md'
                echo '  Store json data: ./phpmyadmin-report.sh --output-json /home/user/report-data.json'
                echo '  Last month: ./phpmyadmin-report.sh --last-month'
                echo '  Current month: ./phpmyadmin-report.sh --current-month'
                echo '  Next month: ./phpmyadmin-report.sh --next-month'
                echo '  Custom dates: ./phpmyadmin-report.sh --start-date 2021-05-03 --end-date 2021-06-27'
                exit
                ;;
            *)
                # unknown option
                echo "Unknown option: $key" #1>&2
                exit 10
                ;;
        esac
        # prepare for next option in this key, if any
        [[ "$key" = -? || "$key" == --* ]] && unset key || key="${key/#-?/-}"
    done
    shift # option(s) fully processed, proceed to next input argument
done

# -- Continue process -- #

detectCheckConfig "${CONFIG_FILE}"
loadDates
readConfig "${CONFIG_FILE}" "processConfigBlock"

printFinalData > "${OUTPUT_JSON_DATA}"
renderFinalData > "${OUTPUT_RENDER}"
