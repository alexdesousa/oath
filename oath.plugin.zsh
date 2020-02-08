# Oath manages private keys securely in order to generate one-time 6 digit
# tokens.

# shellcheck disable=SC2012
# shellcheck disable=SC2162
# shellcheck disable=SC2181
# shellcheck disable=SC2207

##################
# Global variables

export OATH_GNUPG="$HOME/.gnupg"
export OATH_DIR="$HOME/.oath"
[ ! -d "$OATH_DIR" ] && mkdir "$OATH_DIR"

###################
# Private functions

# Prints an error
function __oath_error() {
  local message="$1"

  (>&2 echo -e "\033[1;91m[ERROR]    $message\033[0;0m")
}

# Prints a warning
function __oath_warn() {
  local message="$1"

  (>&2 echo -e "\033[1;93m[WARN]     $message\033[0;0m")
}

# Prints a success message
function __oath_success() {
  local message="$1"

  (echo -e "\033[1;92m[SUCCESS]  $message\033[0;0m")
}

# Checks pre-requisites.
function __oath_check_prerequisites() {
  if [ -z "$OATH_EMAIL" ]
  then
    __oath_error "Missing \$OATH_EMAIL variable in $HOME/.zshrc"
    return 1
  fi

  if [ -z "$OATH_KEY" ]
  then
    __oath_error "Missing \$OATH_KEY variable in $HOME/.zshrc"
    return 1
  fi

  return 0
}

# Show usage
function __oath_usage() {
  echo "\033[1;1mUsage:\033[0;0m

    ~ $ oath [add | delete | show | list | update | help] <key identifier>

\033[1;1mExamples:\033[0;0m

\033[1;1m1. \033[0;0m Adding a key:

    ~ $ oath add twitter.com
    Private key:
    $(__oath_success "Key added for twitter.com")

\033[1;1m2. \033[0;0m Deleting a key:

    ~ $ oath delete twitter.com
    $(__oath_success "Key deleted for twitter.com")

\033[1;1m3. \033[0;0m Showing and copying a 6 digit code for a key:

    ~ $ oath twitter.com
    012345
    $(__oath_success "Code copied to clipboard")

\033[1;1m4. \033[0;0m Listing keys:

    ~ $ oath list
    twitter.com
    github.com

\033[1;1m5. \033[0;0m Updating oath:

    ~ $ oath update
    From https://github.com/alexdesousa/oath
     * branch            master     -> FETCH_HEAD
    Already up to date."
}

# Gets secret dir.
function __oath_secret_dir() {
  local name="$1"
  local secret_dir="$OATH_DIR/$name"

  echo "$secret_dir"
}

# Gets secret filename.
function __oath_secret_filename() {
  local name="$1"
  local secret_dir=""
  local secret_filename=""

  secret_dir=$(__oath_secret_dir "$name")
  secret_filename="$secret_dir/$OATH_KEY.gpg"

  echo "$secret_filename"
}

# Gets private key.
function __oath_get_private_key() {
  local name="$1"
  local secret_filename=""
  local private_key=""

  secret_filename=$(__oath_secret_filename "$name")
  private_key=$(
    gpg2 --quiet -u "$OATH_KEY" -r "$OATH_EMAIL" --decrypt "$secret_filename"
  )

  if [ $? -ne 0 ] || [ -z "$private_key" ]
  then
    __oath_error "Cannot retrieve private key for $name"

    return 1
  fi

  echo "$private_key"
}

# Adds a new private key.
function __oath_add() {
  local name="$1"
  local private_key=""
  local secret_dir=""
  local secret_filename=""

  secret_dir=$(__oath_secret_dir "$name")
  secret_filename=$(__oath_secret_filename "$name")

  # Parameters and pre-requisites

  if [ -f "$secret_filename" ]
  then
    __oath_warn "File $secret_filename already exists"

    return 1
  fi

  # Functionality

  echo -n "Private key: " && read -s private_key
  echo ""

  if [ -z "$private_key" ]
  then
    __oath_warn "Private key cannot be empty"

    return 1
  fi

  mkdir -p "$secret_dir" 2> /dev/null
  gpg2 -u "$OATH_KEY" -r "$OATH_EMAIL" --encrypt -o "$secret_filename" <(echo "$private_key")

  if [ $? -ne 0 ]
  then
    __oath_error "Cannot add key due to a problem"

    return 1
  fi

  __oath_success "Key created for $name"

  return 0
}

# Deletes a private key.
function __oath_delete() {
  local name="$1"
  local secret_dir=""
  local secret_filename=""
  local private_key=""

  secret_dir=$(__oath_secret_dir "$name")
  secret_filename=$(__oath_secret_filename "$name")

  # Functionality

  private_key=$(__oath_get_private_key "$name")
  if [ $? -ne 0 ] || [ -z "$private_key" ]
  then
    __oath_error "Cannot delete key due to a problem"

    return 1
  fi

  if [ -f "$secret_filename" ]
  then
    __oath_warn "Deleting $secret_filename"
    rm "$secret_filename"
  fi

  if [ -d "$secret_dir" ] && [ -z "$(ls -A "$secret_dir")" ]
  then
    __oath_warn "Deleting $secret_dir"
    rm -rf "$secret_dir"
  fi

  __oath_success "Key deleted for $name"

  return 0
}

# Shows 6 digit code.
function __oath_show() {
  local name="$1"
  local private_key=""
  local code=""

  private_key=$(__oath_get_private_key "$name")
  if [ $? -ne 0 ] || [ -z "$private_key" ]
  then
    __oath_error "Cannot get the private key for $name"

    return 1
  fi

  code=$(oathtool -b --totp "$private_key")
  if [ $? -ne 0 ] || [ -z "$code" ]
  then
    __oath_error "Cannot get code for $name"

    return 1
  fi

  echo "$code"

  xclip -sel clip <(echo -n "$code")
  if [ $? -ne 0 ] || [ -z "$code" ]
  then
    __oath_error "Cannot copy code to clipboard"

    return 1
  fi

  __oath_success "Code copied to clipboard"

  return 0
}

# Lists keys.
function __oath_list() {
  local keys=""

  keys=$(
    ls -A "$OATH_DIR"/**/"$OATH_KEY".gpg |
    sed 's#^'"$OATH_DIR"'/\(.*\)/'"$OATH_KEY"'\.gpg$#\1#g'
  )

  echo "$keys"
}

# Updates Oath.
function __oath_update() {
  if [ -d "$ZSH_CUSTOM/plugins/oath/.git" ]
  then
    (
      cd "$ZSH_CUSTOM/plugins/oath" &&
      git pull origin master
    )
  fi
}

# Oath Completions.
function __oath() {
  local current=""
  local previous=""
  local cmd=""
  local cmds="add delete show list update help"
  local keys=""

  if ! __oath_check_prerequisites
  then
    return 1
  fi

  COMPREPLY=()
  keys=$(__oath_list | tr '\n' ' ')
  current="${COMP_WORDS[COMP_CWORD]}"
  previous="${COMP_WORDS[COMP_CWORD - 1]}"

  if [ "$COMP_CWORD" -eq 1 ]
  then
    case "$current" in
      add | update | list | help)
        ;;
      show | delete)
        COMPREPLY=($(compgen -W "$keys" -- "$current"))
        ;;
      *)
        COMPREPLY=($(compgen -W "$cmds $keys" -- "$current"))
        ;;
    esac
  elif [ "$COMP_CWORD" -eq 2 ]
  then
    case "$previous" in
      show | delete)
        COMPREPLY=($(compgen -W "$keys" -- "$current"))
        ;;
      *)
        ;;
    esac
  fi

  return 0
}

##################
# Public functions

# Oath command.
function oath() {
  local cmd="$1"
  local name="$2"
  local secret_dir=""
  local secret_filename=""
  local private_key=""
  local code=""

  # Check commands

  if ! __oath_check_prerequisites
  then
    return 1
  fi

  case "$cmd" in
    add | delete | show)
      if [ -z "$name" ]
      then
        __oath_warn "Missing key identifier"
        __oath_usage

        return 1
      fi
      ;;
    list | update | help)
      ;;
    *)
      if [ -z "$name" ]
      then
        name="$cmd"
        cmd="show"
      fi
      ;;
  esac

  secret_dir=$(__oath_secret_dir "$name")
  secret_filename=$(__oath_secret_filename "$name")

  # Functionality

  case "$cmd" in
    show)
      __oath_show "$name"
      ;;
    add)
      __oath_add "$name"
      ;;
    delete)
      __oath_delete "$name"
      ;;
    list)
      __oath_list
      ;;
    update)
      __oath_update
      ;;
    help)
      __oath_usage
      ;;
  esac

  return $?
}

# Completions
complete -F __oath oath
