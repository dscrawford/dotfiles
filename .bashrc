#
# ~/.bashrc
#

# personal stuff
export TERMINFO=/usr/share/terminfo

alias ls='ls --color=auto'
PS1='[\u@\h \W]\$ '

export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/cuda-8.0/lib64:/usr/local/cuda-8.0/extras/CUPTI/lib64:/usr/local/cuda-8.0/targets/x86_64-linux/lib/"
alias ls='ls --color=auto'
alias copy='xclip -selection clipboard'
alias ll='ls --color=auto -al'

export PATH=$PATH:/home/daniel/.local/share/JetBrains/Toolbox/apps/PyCharm-P/ch-0/202.7660.27/bin/:/home/daniel/Games:/home/daniel/.local/bin

# pyenv init 
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"    # if `pyenv` is not already on PATH
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
