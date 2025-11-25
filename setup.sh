#!/bin/bash
DOTFILES="$(dirname "$(realpath "$0")")"

if_exists_bak() {
    if [[ ! -L "${1}" && -f "${1}" ]]; then
        # Backup: In case where dotfile at location already exists
        if [[ ! -f "${1}.bak" ]]; then
            # Do not overwrite current bak
            mv "${1}"{,.bak}
        else
            # write a new bak suffix if more backups already exist
            count=1
            while true; do
                if [[ ! -f "${1}.${count}.bak" ]]; then
                    mv "${1}.${count}" "${1}.${count}.bak"
                    ((count++))
                    break 1
                fi
            done
        fi
        return 0
    elif [[ -L "${1}" ]]; then
        # symlink case
        echo "Symlink '${1}' -> '$(readlink -f $1)' already exists"
        return 1
    else
        printf "no file ${1} found\nAdding ${1}...\n"
        return 0
    fi
}


install_tmux_completion() {
    tmux -V > /dev/null 2>&1 || exit 1
    curl "https://raw.githubusercontent.com/Bash-it/bash-it/master/completion/available/tmux.completion.bash" \|
	    sed '1,10 s/^/#/' \|
		> "${DOTFILES}/tmux.completion.bash"
}


check_decision() {
    local _human_readable_message="$1" _command="$2"
    echo "Do you want to run \"$_command\" ?"
    printf "%s" "$_human_readable_message "
    read -rp " (y/n/q)? " y_n_q
    msg="option selected"
    case "$y_n_q" in
        y|Y|Yes|yes ) echo "'${y_n_q}' $msg'"; $_command ;;
        n|N|No|no ) echo "'${y_n_q}' $msg, skipping";;
        q|Q|Quit|quit ) echo "'${y_n_q}' $msg, quitting"; return;;
        * ) echo "invalid";;
    esac
}


prompt_to_install_conda() {
    os2kernel="$(uname -a | rev | cut -d ' ' -f1 | rev)"
    IFS=', ' read -r -a array <<< "$(curl "https://repo.anaconda.com/miniconda/" \
        | awk -F'</*td>' '$2{print $2}' \
        | xargs -n5 | grep "${os2kernel}" | grep "py310" \
        | sed 's/href=\([^>]*\).*/\1/g;s/<a//g')" # Using vanilla sed is safer

    if [ "${#array[@]}" -eq 0 ]; then
        echo "No conda installer found."
        exit 1
    fi
    # shellcheck disable=SC2145
    printf "Found conda installer: %s\n" "${array[@]}"
    url_conda_target="https://repo.continuum.io/miniconda/${array[0]}"
    curl -Lo "${array[0]}" "${url_conda_target}"
    chmod +x "${array[0]}" || sudo !!
    bash "${array[0]}" || exit 1
    rm "${array[0]}"
}


create_pynvim_conda_env() {
    echo
    echo "* Checking for conda environment location"
    environment_location="$(find / -mindepth 1 -maxdepth 3 -type d -iname "miniconda*" | head -n1)"
    if [ -d "$environment_location" ] && $_REINSTALL_CONDA; then
        human_readable_message="Do you want to remove ${environment_location} before reinstalling?"
        _command="rm -r \"${environment_location}\""
        check_decision "$human_readable_message" "$_command" || check_decision "$human_readable_message" "sudo ${_command}"
    fi

    if [ -d "${environment_location}/$(grep "name:" ./pynvim-env.yaml | awk '{print $2}')" ]; then
        conda env create -f pynvim-env.yaml -n pynvim
    else
        echo "* Assuming pynvim conda env already exists..."
        environment_location=$(conda env create -f pynvim-env.yaml -n pynvim 2>&1 | grep -v "^$" | sed 's/.*exists: //g')
        [ -n "$environment_location" ] && echo "* Found $environment_location" || echo "No conda environment location found"
        conda env update -f pynvim-env.yaml --prune
    fi
    export CONDA_PYNVIM_ENV_PYTHON_PATH="$environment_location/bin/python3"
}


install_tpm() {
    [ -d "${HOME}/.tmux/plugins" ] || mkdir -pv "${HOME}/.tmux/plugins"
    git clone "https://github.com/tmux-plugins/tpm" "${HOME}/.tmux/plugins/tpm"
}


install_gruvbox() {
    curl -Lo "Gruvbox.itermcolors" "https://raw.githubusercontent.com/runxel/gruvbox-iterm/84ca3c759ab9b9f2a2ede9a32446adb37f3761b6/Gruvbox.itermcolors"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # If this is being used as a script (e.g. `$ ./setup.sh`)
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    export PATH="$HOME/homebrew/bin:$PATH"

    brew bundle && echo '[[ -r "/usr/local/etc/profile.d/bash_completion.sh" ]] && . "/usr/local/etc/profile.d/bash_completion.sh"' >> "${HOME}/.bash_profile"

    for dotfile in bashrc bash_functions bash_aliases inputrc tmux.conf curlrc gitconfig hushlogin; do
        if_exists_bak "$HOME/.${dotfile}" && ln -sv "$DOTFILES/${dotfile}" "$HOME/.${dotfile}"
    done

    install_tmux_completion
    install_gruvbox

    if ! (which conda > /dev/null 2>&1); then
        prompt_to_install_conda
        echo "Please rerun the installation script after running\n. ${HOME}/.bashrc to ensure the base conda env is activated"
        rm ./Miniconda*.sh && exit 1
    else
	echo "* Skipping miniconda installation. A conda installation was found at $(realpath $(which conda))"
    fi
    if ! (which ollama > /dev/null 2>&1); then
        # Install Ollama
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    if [ -d $DOTFILES/vimrc ] && [ ! -d $DOTFILES/.config/nvim ]; then
        # Symlink neovim config submodule (at ~/.dotfiles/.gitmodules )
        ln -s "$DOTFILES/vimrc" "$HOME/.config/nvim"
    fi
    echo "Tip: Go to https://www.nerdfonts.com/font-downloads and download a nerdfont with glyphs for neovim"
fi
