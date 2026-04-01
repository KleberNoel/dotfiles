# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend;

# For setting history length see HISTSIZE and HISTFILESIZE in bash(1)

# Eternal bash history.
# ---------------------
# Undocumented feature which sets the size to "unlimited".
# http://stackoverflow.com/questions/9457233/unlimited-bash-history
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "

# Change the file location because certain bash sessions truncate .bash_history file upon close.
# http://superuser.com/questions/575479/bash-history-truncated-to-500-lines-on-each-login
export HISTFILE="${HOME}/.bash_eternal_history"

# Force prompt to write history after every command.
# http://superuser.com/questions/20900/bash-history-loss
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

# activate colors
export TERM=xterm-256color

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s autocd 2> /dev/null;
shopt -s globstar 2> /dev/null;
shopt -s nocaseglob 2> /dev/null;

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ] && uname -a | grep -q "Debian\|Ubuntu" >/dev/null ; then
  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
elif [ "$color_prompt" = yes ] && uname -a | grep Darwin >/dev/null ; then
  PS1='\[\e]0;\u@\h: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
  TERM=xterm-color
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
GREP_OPTIONS='--color=auto' GREP_COLOR='1;32'

unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    #PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# >>> custom functions >>>
for file in $(ls -1 "$HOME/.bash_functions"); do
    source "$HOME/.bash_functions/$file"
done
# <<< custom functions <<<

# >>> conda initialize >>>
# Attempt finding first path found below root, with maxdepth=2 by default.
# Miniconda could be in a larger storage position (but it is usually kept close to root).
miniconda="$(find / -mindepth 1 -maxdepth 2 -iname "${USER}" -type d 2>/dev/null \
    -exec find {} -iname "miniconda*" -type d -maxdepth 1 \; | head -n1)"
__conda_setup="$("$miniconda/bin/conda" 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$miniconda/etc/profile.d/conda.sh" ]; then
        . "$miniconda/etc/profile.d/conda.sh"
    else
        export PATH="$miniconda/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

export PATH="${HOME}/.local/bin:${PATH}"

# >>> ripgrep init >>>
if type rg &> /dev/null; then
    export FZF_DEFAULT_COMMAND='rg --files'
    # gruvbox colorscheme
    export FZF_DEFAULT_OPTS='-m --height 50% --border --color=bg+:#3c3836,bg:#32302f,spinner:#fb4934,hl:#928374,fg:#ebdbb2,header:#928374,info:#8ec07c,pointer:#fb4934,marker:#fb4934,fg+:#ebdbb2,prompt:#fb4934,hl+:#fb4934'
fi
# <<< ripgrep init <<<

# >>> env files >>>
[ -f "$HOME/.env-vars" ] && "$HOME/.env-vars"
[ -f "$HOME/.env" ] && "$HOME/.env"
[ -f "$HOME/.dotfiles/variables.sh" ] && "$HOME/.dotfiles/variables.sh"
# <<< env files <<<

# fnm
FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="$FNM_PATH:$PATH"
  eval "`fnm env`"
fi

if [ -d "/usr/local/bin/" ]; then
  export PATH="/usr/local/bin/:$PATH"
fi

if [ -d "/home/linuxbrew/.linuxbrew/bin" ]; then
  export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
fi

for bash_file in $(find "$HOME/.dotfiles" -iname "*.bash" -type f); do
  if [ -f "$bash_file" ]; then
    source "$bash_file"
  fi
done

if [ -z $EDITOR ]; then  # (Requires linuxbrew or nvim / vim / vi to be in PATH)
  if which nvim >/dev/null; then
      export EDITOR="nvim" && export VISUAL="nvim"
  elif which vim >/dev/null; then
      export EDITOR="vim" && export VISUAL="vim"
  elif which vi >/dev/null; then
      export EDITOR="vi" && export VISUAL="vi"
  fi
fi

# >>> alias definitions >>> (Requires EDITOR)
if [ -f "$HOME/.bash_aliases" ]; then
    . "$HOME/.bash_aliases"
fi
# <<< alias definitions <<<


which kubectl >/dev/null && alias k=kubectl

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# opencode
export PATH=/home/kleber/.opencode/bin:$PATH
