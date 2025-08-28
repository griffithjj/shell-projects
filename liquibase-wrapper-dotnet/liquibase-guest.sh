#!/bin/bash
#Filename: liquibase-guest
#Description: Pulls Liquibase config values from dotnet user secrets and runs liquibase command

if [ $# -lt 1 ]; then
  cat << EOF

Missing required subcommand
Usage: $0 [GLOBAL OPTIONS] [COMMAND] [COMMAND OPTIONS]
Command-specific help: "$0 <command-name> --help"

EOF
  exit 1
fi

#################################################
# Functions
#################################################

function getFilter {
  # shellcheck disable=SC2001
  data=$(echo "$1" | sed 's/=/ /g')
  read -r -a data_array <<< "$data"

  echo "${data_array[1]}"
}

function executeScript {
  argArray=("$@")
  subArray=("${argArray[@]:1}")
  liquibase --defaults-file="liquibase.${argArray[0]}.properties" "${subArray[@]}"
  return 0
}

#################################################
# end Functions
#################################################

#################################################
# Variables
#################################################
contextFilter="local"
username="null"
password="null"
url="null"

# Set variables if it was passed to script
for i in "$@"
do
  if [[ "$i" == "--context-filter"* ]]; then
    contextFilter=$(getFilter "$i")
  elif [[ "$i" == "--username"* ]]; then
    username=$(getFilter "$i")
  elif [[ "$i" == "--password"* ]]; then
    password=$(getFilter "$i")
  elif [[ "$i" == "--url"* ]]; then
    url=$(getFilter "$i")
  elif [[ "$i" == "--help" ]]; then
    liquibase "$@"
    exit 0
  fi
done

if [[ "$username" != "null" && "$password" != "null" && "$url" != "null" ]]; then
  executeScript "$contextFilter" "$@";
  exit 0
fi

project="../GuestExperience.Store.Postgres.csproj"

secretsFile="liquibase.$contextFilter.secrets"

regexp="^\/\/[[:alpha:]]*"

noSecretsFileMessage=$(cat << EOF
No user secrets configured for this application.

Please configure Liquibase username and password in $secretsFile before running this script again. e.g.,

{
  "liquibase": {
    "$contextFilter": {
      "url": "<url>"
      "username": "<username>",
      "password": "<password>"
    }
  }
}

Where <url> is the jdbc string for the database connection and <username> and <password> are the credentials for the target database.
EOF
)

setSecretsMessage=$(cat << EOF
Configure your liquibase secrets in $secretsFile and run the command below:

dotnet user-secrets -p $project set < ./$secretsFile
EOF
)

#################################################
# end Variables
#################################################

# Pull dotnet user secret in json format
test=$(dotnet user-secrets -p $project list --json) > /dev/null 2>&1

# Create UserSecretsId if not set up yet
if [[ "$test" == "" ]] ; then
  cat << EOF

Initiating dotnet user secrets ...

EOF
  dotnet user-secrets -p $project init
  test=$(dotnet user-secrets -p $project list --json) > /dev/null 2>&1
fi

# shellcheck disable=SC2001
test_secrets=$(echo "$test" | sed "s/$regexp//g")

# Save Liquibase secrets to dotnet user secrets if not found
if echo "$test_secrets" | jq -e 'length == 0' >/dev/null ; then
  cat << EOF

Saving Liquibase secrets to dotnet user secrets ...

EOF
  if [ -e "./$secretsFile" ]; then
    dotnet user-secrets -p $project set < ./"$secretsFile"
  else
    echo "$secretsFile does not exist"
    exit 1
  fi

fi

json=$(dotnet user-secrets -p $project list --json) > /dev/null 2>&1
# shellcheck disable=SC2001
secrets=$(echo "$json" | sed "s/$regexp//g")

if echo "$secrets" | jq -e 'length == 0' >/dev/null; then
  printf "\n\n%s\n\n" "$noSecretsFileMessage"
  exit 1
fi

reqArgs=3
givenArgs=3
usernameArg=""
passwordArg=""
urlArg=""

# Check for username
username=$(echo "$secrets" | jq -r '.["liquibase:'"$contextFilter"':username"]')

if [[ "$username" == "null" ]] ; then
  printf "\n\t* No username secret for target database\n"
  (( givenArgs-- ))
else
  usernameArg="--username=$username"
fi

# Check for password
password=$(echo "$secrets" | jq -r '.["liquibase:'"$contextFilter"':password"]')

if [[ "$password" == "null" ]]; then
  printf "\n\t* No password secret for target database\n"
  (( givenArgs-- ))
else
  passwordArg="--password=$password"
fi

# Check for password
url=$(echo "$secrets" | jq -r '.["liquibase:'"$contextFilter"':url"]')

if [[ "$url" == "null" ]]; then
  printf "\n\t* No url secret for target database\n"
  (( givenArgs-- ))
else
  urlArg="--url=$url"
fi

if [ "$reqArgs" -ne "$givenArgs" ] ; then
  printf "\n\n%s\n\n" "$setSecretsMessage"
  printf "\n\n\tFalling back to liquibase.%s.properties\n\n" "$contextFilter"
  printf "\n\nMake sure you have you connection properties set in liquibase.%s.properties if you do not use dotnet user secrets\n\n" "$contextFilter"
fi

# shellcheck disable=SC2086
executeScript "$contextFilter" $urlArg $usernameArg $passwordArg "$@"