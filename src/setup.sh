#!/usr/bin/env bash

SHELL_DIR="$HOME/src/github.com/kalindudc/shell"

usage() {
  echo "Usage: $0 [--silent|-s] [--stow]"
  exit 1
}

do_stow() {
  echo "Stowing $HOME..."
  stow home -d "$SHELL_DIR" -t $HOME --adopt
  echo "Done setting up $HOME"
}

silent_setup=false
while [ "$#" -gt 0 ]; do
  case $1 in
    --silent|-s)
      silent_setup=true
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

echo " "
echo "Installing oh-my-zsh plugins..."

rm -rf $HOME/.oh-my-zsh/
git clone https://github.com/ohmyzsh/ohmyzsh.git $HOME/.oh-my-zsh

# clean up plugins and re-clone
# rm -rf ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
rm -rf ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
rm -rf ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
rm -rf ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/evalcache
rm -rf ${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/enhancd
rm -rf ${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-completions

# git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/mroth/evalcache ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/evalcache
git clone https://github.com/b4b4r07/enhancd.git ${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/enhancd
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-completions

# kubectl completion
mkdir -p ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/kubectl-autocomplete/
kubectl completion zsh > ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/kubectl-autocomplete/kubectl-autocomplete.plugin.zsh

echo "Done instaling zsh plugins"

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

curl -fLo $HOME/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim > /dev/null 2>&1
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
if [ -z "$GIT_EMAIL" ] && [ "$silent_setup" = false ]; then
  # try to extract email from existing git config
  echo " "
  echo "GIT_EMAIL is not set..."
  read -p "$(echo ${GREEN}Please enter your email address:${NC}) " GIT_EMAIL
  export GIT_EMAIL
  echo " "
fi

# if GIT_NAME is not set, prompt for it
if [ -z "$GIT_NAME" ] && [ "$silent_setup" = false ]; then
  echo " "
  echo "GIT_NAME is not set"
  read -p "$(echo ${GREEN}Please enter your full name:${NC}) " GIT_NAME
  export GIT_NAME
  echo " "
fi

# if GIT_SIGNING_KEY is not set, prompt for it
if [ -z "$GIT_SIGNING_KEY" ] && [ "$silent_setup" = false ]; then
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

echo " "
echo "Setting up git and HOME..."

echo "All set, generating $HOME/.gitconfig..."
$SHELL_DIR/src/generate_tempate.rb -i $SHELL_DIR/src/templates/.gitconfig.erb -o $SHELL_DIR/home/.gitconfig
echo "Done generating $HOME/.gitconfig"

echo " "
do_stow

if  [ "$silent_setup" = false ]; then
  gh auth login
  gh auth setup-git
else
  echo "${RED}Do not forget to \`gh auth login && gh auth setup-git\` to authenticate with github${NC}"
fi
echo "Done setting up git and HOME"

if command -v gdate &>/dev/null; then
  echo "$(gdate)">$HOME/.shell_setup_complete
else
  echo "$(date)">$HOME/.shell_setup_complete
fi

echo " "
# echo "All done! Restart your shell and run \`p10k configure\` to configure powerlevel10k"
echo "All done!"
echo " "


