#!/bin/bash

# e - script stops on error (return != 0)
# u - error if undefined variable
# o pipefail - script fails if one of piped command fails
# x - output each line (debug)
set -euox pipefail


# builtin variables
RED='\033[0;31m'
BLUE='\033[1;36m'
SDK_VERSION='3.9.6'
SDK_FILE_NAME="SailfishSDK-${SDK_VERSION}-linux64-offline.run"
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

function system_prepare_ubuntu {
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get dist-upgrade -y
    # sudo dpkg --configure -a
}

function install_for_ubuntu {
    for lib in "$@"
    do
        if [[ ! $(dpkg -s ${lib}) ]]
        then
            echo "============================================= install ${lib} ===================================================="
            sudo apt-get install -y ${lib}
        fi

        programs+=("${lib}: `dpkg -s ${lib} | grep Status && dpkg -s ${lib} | grep Version || echo 'Not installed'`\n")
    done
}

function log_app_msg() {
	echo -ne "[${BLUE}INFO] $@\n"
}

function log_failure_msg() {
	echo -ne "[${RED}ERROR] $@\n"
}

function set_tz() {
	sudo timedatectl list-timezones | grep Europe
	sudo timedatectl set-timezone Europe/Madrid
	timedatectl
}

function install_deps() {
	system_prepare_ubuntu
	programs=()
	install_for_ubuntu sudo systemd libxcb1 libx11-xcb1 libxcb1 libxcb-glx0 libfontconfig1 libx11-data libx11-xcb1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libsm6 libxkbcommon-x11-0 libwayland-egl1 libegl-dev libxcomposite1 libwayland-cursor0 libharfbuzz-dev libxi-dev libtinfo5 ca-certificates curl gnupg lsb-release mesa-utils libgl1-mesa-glx micro lsb-release sudo zsh git
	if [[ $programs ]]
    then
        log_app_msg "Installed programs: "
        echo -e ${programs[@]}
    fi
}

function install_virtualbox() {
	sudo apt-get install -y virtualbox
	log_app_msg "virtualbox has installed successfully."
}

function install_docker() {
	# install docker
	# https://docs.docker.com/engine/install/ubuntu/

	if ! which docker; then
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
		sudo apt-get update -y && \
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io && \
		sudo usermod -aG docker "$USER"
		log_app_msg "Manage Docker as a non-root user. Successfully."
		exit 1
	fi
	log_app_msg "docker already installed."
}

function sfdk_download() {
	if [ ! -f "${SDK_FILE_NAME}" ]; then
		curl -O https://releases.sailfishos.org/sdk/installers/${SDK_VERSION}/${SDK_FILE_NAME} && \
		chmod +x ${SDK_FILE_NAME}
		log_app_msg "Download ${SDK_FILE_NAME} has completed successfully."
	else
		log_app_msg "File ${SDK_FILE_NAME} already exists."
	fi
}

function sfdk_install() {
  if [[ ! -d "SailfishOS" ]]; then
	  QT_QPA_PLATFORM=minimal ./${SDK_FILE_NAME} --verbose non-interactive=1 accept-licenses=1 build-engine-type=docker
	else
	  log_app_msg "Folder SailfishOS already exists."
	fi
}

function set_envs() {
	LIBGL_ALWAYS_INDIRECT="LIBGL_ALWAYS_INDIRECT=1"
	if ! grep "$LIBGL_ALWAYS_INDIRECT" ~/.bashrc; then
		echo "$LIBGL_ALWAYS_INDIRECT" >> ~/.bashrc
	fi
	if ! grep "$LIBGL_ALWAYS_INDIRECT" ~/.zshrc; then
		echo "$LIBGL_ALWAYS_INDIRECT" >> ~/.zshrc
	fi
	PATH_="/home/ubuntu/bin:${PATH}"
	if ! grep "$PATH_" ~/.bashrc; then
		echo "$PATH_" >> ~/.bashrc
	fi
	if ! grep "$PATH_" ~/.zshrc; then
		echo "$PATH_" >> ~/.zshrc
	fi
}

function git_aliases() {
	git config --global alias.co checkout                                                                                                                                        ─╯
	git config --global alias.ci commit
	git config --global alias.st status
	git config --global alias.br branch
	git config --global alias.hist "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short"
	git config --global alias.type 'cat-file -t'
	git config --global alias.dump 'cat-file -p'
}

function set_zsh_by_default() {
	sudo chsh -s $(which zsh) $(whoami)
}

create_spec_dirs() {
	mkdir -p ~/build-bible-SailfishOS_4_4_0_58_armv7hl_in_sailfish_sdk_build_engine_ubuntu-Debug
}

install_ohmyzsh() {
	if [ ! -d ".oh-my-zsh" ]; then
		sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	fi
}

sfdk_put_to_bin() {
  mkdir -p ~/bin
  echo '#!/bin/sh
exec ~/SailfishOS/bin/sfdk "$@"' > ~/bin/sfdk
  chmod +x ~/bin/sfdk
  sfdk --help
}

sfdk_tools_lis() {
  sfdk tools list
}

set_envs
install_deps
install_docker
install_ohmyzsh
set_tz
set_zsh_by_default
git_aliases
sfdk_download
sfdk_install
sfdk_put_to_bin
sfdk_tools_lis
