#!/bin/bash

# - CONSTANTS -
readonly required_env_vars=('AUTH0_CLIENT_ID' 'AUTH0_CLIENT_SECRET' 'AUTH0_TENANT')
readonly required_pagination_resources=('clients' 'client_grants' 'grants' 'connections' 'device-credentials' 'resource-servers' 'rules' 'logs')


# - FUNCTIONS -
# Print help and exit. Exit code can be set by passing a numeric parameter
function _help() {
  cat <<EOF
${0} [ch] <target>

Back up an Auth0 tenant to a directory.

Flags:
-h  print help and exit
-c  attempt to create target directories as required
-w  wait for up to <n> seconds for the target directory to appear
`#-v  increase script verbosity`

Required environment variables:
EOF
  for var in "${required_env_vars[@]}"; do
    echo "- $var"
  done
  exit "${1:-1}"
}

# Show error if given variable is not defined
function req_undef() {
  missing=false
  for var in "$@"; do
    [ -n "${!var+x}" ] && continue
    echo "$var (required) was not provided" > /dev/stderr
    missing=true
  done
  if $missing; then
    # Insert newline
    echo
    exit 1
  fi
}

# Check if str is in array
# https://stackoverflow.com/a/8574392/1342445
function in_array() {
  local elem str="$1"
  shift
  for elem; do
    [[ "$elem" == "$str" ]] && return 0
  done
  return 1
}

# Print an error message and exit
function error_message() {
  echo "$1" > /dev/stderr
  exit 2
}

# Get a resource from the server
function get_resource() {

  url="https://$AUTH0_TENANT/$1"
  authorization="$token_type $token"

  curl  -sb --fail \
    --request GET \
    --url $url \
    --header "authorization: $authorization" \
    --header 'content-type: application/json'
}

# Backup all resources to the target
function backup_resources() {
  backup_filepath="$target/auth0-backup-$(date +%m-%d-%y)"
  mkdir -p $backup_filepath

  for rs in "$@"; do
    success=false
    page=0
    per_page=100
    url=""

    until [ $success = true ]
    do
      # set query line if resources requires pagination
      if in_array "${rs}" "${required_pagination_resources[@]}";
      then
        query="api/v2/$rs?page=$page&per_page=$per_page"
      else
        query="api/v2/$rs"
        success=true
      fi

      url="https://$AUTH0_TENANT/$query"

      # set filepaths for generated json
      filepath_temp="$backup_filepath/$rs-temp_pg-$page.json"
      filepath_backup="$backup_filepath/$rs.json"
  

      # query for auth0 objects and store in response variable
      response=$(get_resource $query | jq -SM '.')

      # parse response to json and push to temporary json file
      echo $response | jq . > $filepath_temp

      # check if response has results
      # if not, we have reached the end of resource results
      if [ "$(jq length $filepath_temp)" -lt 1 ];
      then
        rm $filepath_temp
        success=true
        break
      elif [ "$(jq length $filepath_temp)" -gt 0 ];
      then
        # put all aggregated json objects into one 
        jq . $filepath_temp >> $filepath_backup
        jq '.[]' $filepath_backup > $filepath_temp
        jq -s '.' $filepath_temp> $filepath_backup

        # clean out temporary files
        rm $filepath_temp

        let page++

        # there is a limitation to the # of logs you can query at a time/paginated
        # 1) 100 logs/query
        # 2) up to 1000 paginated logs
        if [ "$rs" = "logs" ] && [ "$page" -eq 10 ];
        then
          success=true
          break
        fi
      else
        # clean workspace if failed
        rm $filepath_temp
        rm $filepath_backup
        echo "Failed to get: api/v2/$rs, attempting try $i/3 in $((i**2)) seconds..."
        sleep $((i**2))
        break
      fi
    done

    if ! $success; then
      error_message "Failed to get $url"
    fi
  done
}


# - SCRIPT -
# Flags
verbose=false
create=false
wait_=0
while getopts 'hcvw:' flag; do
  case "${flag}" in
    h) _help 0 ;;
    c) create=true ;;
    v) verbose=true ;;
    w) wait_="${OPTARG}" ;;
    *) error "Unexpected option ${flag}" ;;
  esac
done
shift $((OPTIND-1))

readonly target="${1%/}"

if $verbose; then
  set -x
fi

if [ "$wait_" -gt 0 ]; then
  echo "waiting for target directory to appear..."
  now=$(date +%s);
  until [ -d "$target" ]; do
    if [ $((now-$(date +%s))) -gt "$wait_" ]; then
      echo "timed out waiting for target to appear"
      break
    fi
    sleep .2
  done
fi

if $create; then
  mkdir -p "$target"
else
  [ ! -d "$target" ] && {
    echo "Target directory ($target) does not exist!";
    echo
    _help
  }
fi

# Environment sanity checks
trap _help EXIT ERR
req_undef "${required_env_vars[@]}"
[ -n "${target+x}" ] || exit 1
trap - EXIT ERR

echo "Backing up Auth0 to: $target/"

if ! auth_json=$(curl -sbv \
  --fail \
  --request POST \
  --url "https://$AUTH0_TENANT/oauth/token" \
  --header 'content-type: application/json' \
  --data "{
    \"client_id\": \"$AUTH0_CLIENT_ID\",
    \"client_secret\": \"$AUTH0_CLIENT_SECRET\",
    \"audience\": \"https://$AUTH0_TENANT/api/v2/\",
    \"grant_type\": \"client_credentials\"
  }"); then
  error_message "unable to authenticate!"
fi

readonly token=$(echo "$auth_json" | jq -r '.access_token')
readonly token_type=$(echo "$auth_json" | jq -r '.token_type')

backup_resources 'clients' \
  'connections' \
  'rules' \
  'grants' \
  'resource-servers' \
  'rules-configs' \
  'logs'

