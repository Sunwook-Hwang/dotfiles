# C shell / tcsh counterpart of the Zsh command setup.
setenv LANG en_US.UTF-8
setenv LANGUAGE en_US.UTF-8
setenv LC_ALL en_US.UTF-8
# Keep the terminal application's advertised capabilities.
if (! $?TERM) setenv TERM xterm-256color

if (-d /opt/homebrew/bin) set path = ( /opt/homebrew/bin $path:q )
if (-d /opt/homebrew/sbin) set path = ( /opt/homebrew/sbin $path:q )
set path = ( "$HOME/.local/bin" $path:q )

alias tmux 'env TERM=xterm-256color tmux'
alias tad 'tmux at -d'
alias lg 'lazygit'
unalias vi 'env NVIM_APPNAME=nvim nvim'
alias pvi 'env NVIM_APPNAME=nvim-pack nvim'
alias neovide 'env NVIM_APPNAME=neovide-terminal neovide'

# tcsh supplies native history, completion and a prompt; Zsh plugins do not load here.
if ($?prompt) then
  set history = 10000
  if ($?tcsh) then
    set savehist = ( 10000 merge )
    set histfile = "$HOME/.tcsh_history"
    set autolist
    set complete = enhance
    set prompt = '%n@%m:%~ %# '
    bindkey -e
  endif
endif

# Match the optional Miniforge installation used by the macOS Zsh setup.
if (-f /opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.csh) then
  source /opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.csh
endif

# Load private overrides after the shared configuration.
if (-f "$HOME/.cshrc.local") then
  source "$HOME/.cshrc.local"
endif
