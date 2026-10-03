export LANG='en_US.UTF-8'
export LANGUAGE='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'
export TERM=xterm-256color

export ZSH=$HOME/.oh-my-zsh
export PATH=/opt/homebrew/bin:$PATH
export PATH=/opt/homebrew/sbin:$PATH
export PATH=$HOME/.local/bin:$PATH

alias tmux='env TERM=xterm-256color tmux'

alias tad='tmux at -d'

alias lg='lazygit'

alias hd='herdr'

unalias vi pvi onvi offvi 2>/dev/null || true
unfunction vi pvi 2>/dev/null || true

# FLASH is always the default; the package profile is selected explicitly.
alias vi='env NVIM_APPNAME=nvim nvim'
alias pvi='env NVIM_APPNAME=nvim-pack nvim'

alias neovide='NVIM_APPNAME=neovide-terminal neovide'

ZSH_THEME="robbyrussell"
ZSH_DISABLE_COMPFIX="true"

plugins=(
  git
  zsh-syntax-highlighting
  zsh-autosuggestions
  autojump
)

source $ZSH/oh-my-zsh.sh

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/homebrew/Caskroom/miniforge/base/bin/conda' 'shell.zsh' 'hook' 2>/dev/null)"
if [ $? -eq 0 ]; then
  eval "$__conda_setup"
else
  if [ -f "/opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.sh" ]; then
    . "/opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.sh"
  else
    export PATH="/opt/homebrew/Caskroom/miniforge/base/bin:$PATH"
  fi
fi
unset __conda_setup
# <<< conda initialize <<<
