#!/bin/bash

set -e

FILE_AUTHORIZED_KEYS="/home/git/.ssh/authorized_keys"
FILE_GITOLITERC="/home/git/.gitolite.rc"
FILE_KEYS="/home/git/.ssh/keys"

SERVER_NAME=${SERVER_NAME:-"localhost"}
SERVER_PORT=${SERVER_PORT:-"80"}
SERVER_SECURE_PORT=${SERVER_SECURE_PORT:-"443"}
SERVER_SSH=${SERVER_SSH:-"3268"}

REPOSITORY_PATH="/home/git/repositories"

TZ=${TZ:-"America/Fortaleza"}

fix-admin-rollback() {
  DIR="/tmp/$(date +"%Y%m%d%H%M%S")"

  mkdir -p "$DIR"
  git clone /home/git/repositories/gitolite-admin.git "$DIR" > /dev/null 2>&1
  cd "$DIR"

  COMMIT=$(git log --pretty=format:%s | head -n 1)
  if [[ $COMMIT =~ ^gitolite[[:space:]]setup.*$ ]]; then
    git reset --hard HEAD^                                   > /dev/null 2>&1
    chown git.git $DIR                                       > /dev/null 2>&1
    su git -c "/home/git/bin/gitolite push -f"               > /dev/null 2>&1
  fi

  cd /tmp
  rm -rf "$DIR"
}

fix-perms() {
  OIFS="$IFS"
  IFS=$'\n'
  for directory in `find /home/git -maxdepth 1`
  do
    rep=$(echo $directory | sed 's/.*\///')
    if [[ -n "$directory" && "$rep" != "repositories" ]]; then
      chown git.git $directory
    fi
  done
  IFS="$OIFS"
}

fix-timezone() {
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
  echo $TZ > /etc/timezone
}

git-admin-count() {
  local count="0"

  if [[ -d "$REPOSITORY_PATH/gitolite-admin.git" ]]; then
    count=$(su git -c "cd $REPOSITORY_PATH/gitolite-admin.git && git rev-list HEAD --count")
  fi

  echo $count
}

gitolite-compile() {
  su git -c '/home/git/bin/gitolite compile'
}

gitolite-setup-hooks() {
  su git -c '/home/git/bin/gitolite setup --hooks-only'
}

gitolite-trigger-post-compile() {
  su git -c '/home/git/bin/gitolite trigger POST_COMPILE'
}

setup-config-variables() {
  sed "s/%%SERVER_NAME%%/$SERVER_NAME/"               -i /etc/cgitrc
  sed "s/%%SERVER_SSH%%/$SERVER_SSH/"                 -i /etc/cgitrc
  sed "s/%%SERVER_NAME%%/$SERVER_NAME/"               -i /etc/h2o/h2o.conf
  sed "s/%%SERVER_PORT%%/$SERVER_PORT/"               -i /etc/h2o/h2o.conf
  sed "s/%%SERVER_SECURE_PORT%%/$SERVER_SECURE_PORT/" -i /etc/h2o/h2o.conf
}

setup-gitolite() {
  local commits_before="0" commits_after="0"

  commits_before=$(git-admin-count)
  su git -c '/home/git/bin/gitolite setup -pk /tmp/key.pub'
  commits_after=$(git-admin-count)

  if [[ $commits_after -gt $commits_before ]]; then
    INCREASED_COMMIT_ADMIN_REPOSITORY="y"
  else
    INCREASED_COMMIT_ADMIN_REPOSITORY="n"
  fi
}

setup-migrate-repositories() {
  gitolite-compile
  gitolite-setup-hooks
  gitolite-trigger-post-compile
}

setup-key() {
  if [ -n "$PUB_KEY" ]; then
    echo "$PUB_KEY" > /tmp/key.pub
  else
    echo ":: cant setup or resume without define admin key"
    exit 13
  fi
}

setup-permit-description() {
  su git -c "sed \"s/\# 'cgit/'cgit/\"                                 -i ${FILE_GITOLITERC}"
  su git -c "sed \"s/'gitweb/\# 'gitweb/\"                             -i ${FILE_GITOLITERC}"
  su git -c "sed '/);/i \ \ \ \ WRITER_CAN_UPDATE_DESC          => 1,' -i ${FILE_GITOLITERC}"
  gitolite-compile
  gitolite-trigger-post-compile
}

### usage: Help
# Arguments:
#   none)
# Return: Help text
usage() { local RC="${1:-0}"
    echo "Usage: ${0##*/} [-opt] [command]
Options (fields in '[]' are optional, '<>' are required):
    -h          This help
    -d          Enable permission to add description to repository 
                \$ ssh git@host desc <repo> <description string>
    -i          Will proceed with the import of migrated repositories
    -p \"<action;path>[;username;password]\"
                Configure a share
                required arg: \"<action>;<path>\"
                <action> available actions: add (a), delete (d)
                <path> path to share relative to repositories dir
                NOTE: for the default value, just leave blank
                [username] the username
                [password] the password

The 'command' (if provided and valid) will be run instead of git server
" >&2
    exit $RC
}

if [[ -d "/home/git/repositories/gitolite-admin.git" ]]; then
  EXIST_ADMIN_REPOSITORY="y"
else
  EXIST_ADMIN_REPOSITORY="n"
fi

if [ -s $FILE_AUTHORIZED_KEYS ]; then
  EXIST_AUTHORIZED_KEYS="y"
else
  EXIST_AUTHORIZED_KEYS="n"
fi

if [[ -f $FILE_KEYS ]]; then
  SHOULD_REPLACE_KEYS="y"
else
  SHOULD_REPLACE_KEYS="n"
fi

if [[ $EXIST_ADMIN_REPOSITORY =~ "n" || $SHOULD_REPLACE_KEYS =~ "y" ]]; then
  setup-key
  setup-gitolite
  [[ -f "$FILE_KEYS" ]] && rm "$FILE_KEYS"
else
  setup-key
  setup-gitolite
  [[ "${INCREASED_COMMIT_ADMIN_REPOSITORY:-""}" == "y" ]] && fix-admin-rollback
  [[ -f "$FILE_KEYS" ]] && rm "$FILE_KEYS"
fi

[[ "${USERID:-""}" =~ ^[0-9]+$ ]] && usermod -u $USERID -o git
[[ "${GROUPID:-""}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o git

fix-timezone
fix-perms
setup-config-variables

while getopts ":di" opt; do
    case "$opt" in
        d) ALLOW_WRITE_DESCRIPTION="true" ;;
        i) MIGRATE_REPOSITORIES="true" ;;
        "?") echo "Unknown option: -$OPTARG"; usage 1 ;;
        ":") echo "No argument value for option: -$OPTARG"; usage 2 ;;
    esac
done
shift $(( OPTIND - 1 ))

[[ "${ALLOW_WRITE_DESCRIPTION:-""}" ]] && setup-permit-description
[[ "${MIGRATE_REPOSITORIES:-""}" ]] && setup-migrate-repositories

if [[ $# -ge 1 && -x $(which $1 2>&-) ]]; then
    exec "$@"
elif [[ $# -ge 1 ]]; then
    echo "ERROR: command not found: $1"
    exit 13
else
    /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
fi