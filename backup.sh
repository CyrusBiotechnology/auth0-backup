#!/bin/bash

# - CONSTANTS -
readonly required_env_vars=('AUTH0_CLIENT_ID' 'AUTH0_CLIENT_SECRET' 'AUTH0_TENANT')


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

# Print an error message and exit
function error_message() {
  echo "$1" > /dev/stderr
  exit 2
}

# Get a resource from the server
function get_resource() {
  curl --fail \
    --request GET \
    --url "https://$AUTH0_TENANT/$1" \
    --header "authorization: $token_type $token" \
    --header 'content-type: application/json'
}

# Backup all resources to the target
function backup_resources() {
  for rs in "$@"; do
    success=false
    for i in {1..3}; do
      if get_resource "api/v2/$rs" | jq -SM . > "$target/$rs.json"; then
        success=true
        break
      else
        echo "Failed to get: api/v2/$rs, attempting try $i/3 in $((i**2)) seconds..."
        sleep $((i**2))
      fi
    done

    if ! $success; then
      error_message "Failed to get api/v2/$rs!"
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

if ! auth_json=$(curl -v \
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
  'logs' \
  'resource-servers' \
  'rules-configs'

