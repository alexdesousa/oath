# # Oath zsh plugin
#
# Oath manages private keys securely in order to generate one-time 6 digit
# tokens.

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

# Add usage
function __oath_add_usage() {
  echo "Usage:

~ $ oath_add <key identifier>

Example:

~ $ oath_add twitter.com
Private key:
[SUCCESS] Key added for twitter.com"
}

# Delete usage
function __oath_delete_usage() {
  echo "Usage:

~ $ oath_delete <key identifier>

Example:

~ $ oath_delete twitter.com
[WARN]    Deleting $OATH_DIR/.oath/twitter.com/424184E122529120CC1821756759ADDD12CB6379.gpg
[WARN]    Deleting $OATH_DIR/.oath/twitter.com
[SUCCESS] Key deleted for twitter.com"
}

# Show usage
function __oath_usage() {
  echo "Usage:

~ $ oath <key identifier>

Example:

~ $ oath twitter.com
012345
[SUCCESS]  Code copied to clipboard"
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


##################
# Public functions

# Adds a new private key.
function oath_add() {
  local name="$1"
  local private_key=""
  local secret_dir=""
  local secret_filename=""

  secret_dir=$(__oath_secret_dir "$name")
  secret_filename=$(__oath_secret_filename "$name")

  # Parameters and pre-requisites

  if ! $(__oath_check_prerequisites)
  then
    return 1
  elif [ -z "$name" ]
  then
    __oath_warn "Missing key identifier"
    __oath_add_usage

    return 1
  elif [ "$name" = "help" ]
  then
    __oath_add_usage

    return 0
  elif [ -f "$secret_filename" ]
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
function oath_delete() {
  local name="$1"
  local secret_dir=""
  local secret_filename=""
  local private_key=""

  secret_dir=$(__oath_secret_dir "$name")
  secret_filename=$(__oath_secret_filename "$name")

  # Parameters and pre-requisites

  if ! $(__oath_check_prerequisites)
  then
    return 1
  elif [ -z "$name" ]
  then
    __oath_warn "Missing key identifier"
    __oath_delete_usage

    return 1
  elif [ "$name" = "help" ]
  then
    __oath_delete_usage

    return 0
  fi

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

  if [ -d "$secret_dir" ] && [ -z $(ls -A "$secret_dir") ]
  then
    __oath_warn "Deleting $secret_dir"
    rm -rf "$secret_dir"
  fi

  __oath_success "Key deleted for $name"

  return 0
}

# Show 6 digit number.
function oath() {
  local name="$1"
  local secret_dir=""
  local secret_filename=""
  local private_key=""
  local code=""

  secret_dir=$(__oath_secret_dir "$name")
  secret_filename=$(__oath_secret_filename "$name")

  # Parameters and pre-requisites

  if ! $(__oath_check_prerequisites)
  then
    return 1
  elif [ -z "$name" ]
  then
    __oath_warn "Missing key identifier"
    __oath_usage

    return 1
  elif [ "$name" = "help" ]
  then
    __oath_usage

    return 0
  fi

  # Functionality

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

# Updates oath plugin
function oath_update() {
  if [ -d "$ZSH_CUSTOM/plugins/oath/.git" ]
  then
    (
      cd "$ZSH_CUSTOM/plugins/oath" &&
      git pull origin master
    )
  fi
}
