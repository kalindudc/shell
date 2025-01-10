#!/bin/sh

if [ "$SHELL" != "/usr/bin/zsh" ]; then
  echo "Zsh is not the default shell. Installing zsh..."
  sudo apt install -y zsh
  echo "Switching to zsh..."
  chsh -s $(which zsh)

  echo "Please reboot your machine and run this script again"
  exit 0
fi

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

prompt_for_yn() {
  local prompt="$1"
  local default="$2"
  local answer

  while true; do
    read -p "$prompt " answer
    answer=${answer:-$default}

    case "$answer" in
      [Yy]* ) return 0;;
      [Nn]* ) return 1;;
      * ) echo "Please answer y or N.";;
    esac
  done
}

GIT_CLONE_DIR="$HOME/src/github.com/kalindudc"
SHELL_DIR="$GIT_CLONE_DIR/shell"
SHELL_REMOTE="https://github.com/kalindudc/shell.git"

mkdir -p $GIT_CLONE_DIR

skip_package_install=false
# Function to display usage
usage() {
    echo "Usage: $0 [--skip-packages] [--stow] [--help]"
    exit 1
}

do_stow() {
  echo "Stowing $HOME..."
  stow home -d "$SHELL_DIR" -t $HOME --adopt
  echo "Done setting up $HOME"
}

# Parse options
while [ "$#" -gt 0 ]; do
  case $1 in
    --skip-packages)
      skip_package_install=true
      ;;
    -h|--help)
      usage
      ;;
    --stow)
      do_stow
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
  shift
done

if [ "$skip_package_install" = false ]; then
  sudo apt update && suto apt upgrade -y

  # Remove conflicting packages
  sudo apt remove neovim -y

  sudo apt install -y \
    coreutils \
    direnv \
    fd-find \
    fzf \
    fzy \
    gcc \
    gh \
    git \
    gnupg \
    neovim \
    openssl \
    pipx \
    libreadline-dev \
    ripgrep \
    ruby-build \
    sqlite3 \
    stow \
    tcl \
    tk \
    xz-utils \
    zlib1g-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    wget \
    curl \
    llvm \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libffi-dev \
    liblzma-dev \
    python3-openssl \
    xclip

  curl -s https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sudo bash

  curl -s https://api.github.com/repos/dandavison/delta/releases/latest \
    | jq -r '.assets[] | select(.name | test("git-delta.*deb")) | .browser_download_url' \
    | wget -O /tmp/git-delta.deb -i -
  sudo dpkg -i /tmp/git-delta.deb
  rm /tmp/git-delta.deb

  sudo snap install nvim --classic
  sudo snap install task --classic
  sudo snap install helm --classic
  sudo snap install kubectl --classic
  sudo snap install --classic code

  curl https://pyenv.run | bash

  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  #curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

  pipx install dunk

  sudo apt --fix-broken install -y

  echo "Done installing packages"
else
  echo "Skipping brew installation"
fi

echo " "
echo "Installing zsh plugins..."

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/mroth/evalcache ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/evalcache
git clone https://github.com/b4b4r07/enhancd.git ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/enhancd
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions

# kubectl completion
mkdir -p ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/kubectl-autocomplete/
kubectl completion zsh > ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/kubectl-autocomplete/kubectl-autocomplete.plugin.zsh

mkdir -p ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/op-autocomplete/
op completion zsh > ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/op-autocomplete/op-autocomplete.plugin.zsh

echo "Done instaling zsh plugins"

echo " "
echo "Setting up $SHELL_DIR..."

# Check if the directory exists
if [ -d "$SHELL_DIR" ]; then
  if prompt_for_yn "$(echo ${GREEN}$SHELL_DIR exists, do you want to overwrite the changes with upstream changes?${NC}) (y/N)" "N"; then
    echo "Directory exists. Navigating to $SHELL_DIR."
    cd "$SHELL_DIR" || exit

    # Discard any changes
    echo "Discarding any local changes."
    git reset --hard
    git clean -fd

    # Pull the latest changes
    echo "Pulling the latest changes."
    git pull origin main
  else
    echo "Skipping $SHELL_DIR"
  fi
else
  # Clone the repository
  echo "$SHELL_DIR does not exist. Cloning the repository."
  git clone "$REPO_URL" "$SHELL_DIR"
fi

echo "Done setting up $SHELL_DIR"

echo " "
echo "Setting up $HOME..."

echo "Generating backups for current configs before replacing..."
[ -f $HOME/.zshrc ] && echo ".zshrc.bak" && cp $HOME/.zshrc $HOME/.zshrc.bak > /dev/null 2>&1
[ -f $HOME/.p10k.zsh ] && echo ".p10k.zsh.bak" && cp $HOME/.p10k.zsh $HOME/.p10k.zsh.bak > /dev/null 2>&1
[ -f $HOME/.config/direnv ] && echo ".direnv.bak" && cp $HOME/.config/direnv $HOME/.config/direnv.bak > /dev/null 2>&1
[ -f $HOME/.vim ] && echo ".vim.bak" && cp $HOME/.vim $HOME/.vim.bak > /dev/null 2>&1

echo " "
echo "Removing existing configs..."
rm -rf $HOME/.zshrc > /dev/null 2>&1
rm -rf $HOME/.zcompdump > /dev/null 2>&1
rm -rf $HOME/.p10k.zsh > /dev/null 2>&1
rm -rf $HOME/.config/direnv > /dev/null 2>&1
rm -rf $HOME/.vim > /dev/null 2>&1

curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim > /dev/null 2>&1
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' > /dev/null 2>&1

echo " "
echo "Generate $HOME/.zshrc..."
$SHELL_DIR/src/generate_zshrc.rb
echo "Done generating $HOME/.zshrc"

echo " "
echo "Generate $HOME/.gitconfig..."

export GIT_EMAIL=$(git config --global user.email)
export GIT_NAME=$(git config --global user.name)
export GIT_SIGNING_KEY=$(git config --global user.signingkey)

# if GIT_EMAIL is not set, prompt for it
if [ -z "$GIT_EMAIL" ]; then
  # try to extract email from existing git config
  echo " "
  echo "GIT_EMAIL is not set..."
  read -p "$(echo ${GREEN}Please enter your email address:${NC}) " GIT_EMAIL
  export GIT_EMAIL
  echo " "
fi

# if GIT_NAME is not set, prompt for it
if [ -z "$GIT_NAME" ]; then
  echo " "
  echo "GIT_NAME is not set"
  read -p "$(echo ${GREEN}Please enter your full name:${NC}) " GIT_NAME
  export GIT_NAME
  echo " "
fi

# if GIT_SIGNING_KEY is not set, prompt for it
if [ -z "$GIT_SIGNING_KEY" ]; then
  # ask if user wants to generate a new key
  if prompt_for_yn "$(echo ${GREEN}GIT signing key does not exit, do you want to generate a new signing key?${NC}) (y/N)" "N"; then
    echo "${RED}Generating GPG key...${NC}"
    gpg --full-generate-key

    echo "Listing GPG keys..."
    gpg --list-secret-keys --keyid-format LONG
    read -p "$(echo ${GREEN}please enter the GPG key ID from the above list:${NC}) " GIT_SIGNING_KEY

    echo " "
    echo "${RED}Do not forget to add your key to github, https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key${NC}"
  else
    echo " "
    echo "GIT_SIGNING_KEY is not set, listing GPG keys..."
    gpg --list-secret-keys --keyid-format LONG
    read -p "$(echo ${GREEN}please enter your GPG key ID:${NC}) " GIT_SIGNING_KEY
  fi

  export GIT_SIGNING_KEY
  echo " "
fi

echo "All set, generating $HOME/.gitconfig..."
$SHELL_DIR/src/generate_tempate.rb -i $SHELL_DIR/src/templates/.gitconfig.erb -o $SHELL_DIR/home/.gitconfig
echo "Done generating $HOME/.gitconfig"

echo " "
do_stow

echo " "
echo "Setting up git..."

gh auth login
gh auth setup-git

echo "Done setting up git"

echo " "
echo "All done! Restart your shell and run \`p10k configure\` to configure powerlevel10k"
echo " "
