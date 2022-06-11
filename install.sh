#!/bin/bash

# builtin variables
RED='\033[0;31m'
BLUE='\033[1;36m'
SDK_VERSION='3.9.6'
SDK_FILE_NAME="SailfishSDK-${SDK_VERSION}-linux64-offline.run"
BIBLE_GIT_BRANCH=support_mac_m1
GITHUB_USER="spiritEcosse"
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
	echo -ne "[${BLUE}INFO${NC}] $@\n"
}

function log_failure_msg() {
	echo -ne "[${RED}ERROR${NC}] $@\n"
}

function install_tzdata() {
	lib=tzdata
	if [[ ! $(dpkg -s ${lib}) ]]
	then
		echo "============================================= install ${lib} ===================================================="
		sudo apt-get install -y ${lib}
		debconf-set-selections \
			tzdata tzdata/Areas select Europe \
			tzdata tzdata/Zones/Europe select Ukraine
	fi
}

function install_deps() {
	system_prepare_ubuntu
	programs=()
	install_for_ubuntu tzdata libxcb1 libx11-xcb1 libxcb1 libxcb-glx0 libfontconfig1 libx11-data libx11-xcb1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libsm6 libxkbcommon-x11-0 libwayland-egl1 libegl-dev libxcomposite1 libwayland-cursor0 libharfbuzz-dev libxi-dev libtinfo5 ca-certificates curl gnupg lsb-release mesa-utils libgl1-mesa-glx micro lsb-release sudo
	if [[ $programs ]]
    then
        log_app_msg "Installed programs: "
        echo -e ${programs[@]}
    fi
	return 0
}

function install_virtualbox() {
	sudo apt-get install -y virtualbox
	log_app_msg "virtualbox has installed successfully."
}

function install_docker() {
	# install docker
	# https://docs.docker.com/engine/install/ubuntu/
	docker -v

	if [[ $? -ne 0 ]]; then
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
		sudo apt-get update -y && \
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io && \
		sudo usermod -aG docker "$USER"
		log_app_msg "Manage Docker as a non-root user. Successfully."
		exit 1
	fi
	log_app_msg "docker already installed."
	return 0
}

function download_sailfish_sdk() {
	if [ ! -f "${SDK_FILE_NAME}" ]; then
		curl -O https://releases.sailfishos.org/sdk/installers/${SDK_VERSION}/${SDK_FILE_NAME} && \
		chmod +x ${SDK_FILE_NAME}
		log_app_msg "Download ${SDK_FILE_NAME} has completed successfully."
	else
		log_app_msg "File ${SDK_FILE_NAME} already exists."
	fi
	return 0
}

function run_sailfish_sdk() {
	if [[ ! -z ${DISPLAY} ]]; then
		./${SDK_FILE_NAME}
		return $?
	fi
	log_app_msg "Variable DISPLAY has value '${DISPLAY}'."
	return 1
}

function theme_qtcreator() {
	if [ ! -d "qtcreator" ]; then
		git clone https://github.com/dracula/qtcreator.git && \
		cp qtcreator/dracula.xml /home/ubuntu/SailfishOS/share/qtcreator/styles/
		log_app_msg "File dracula.xml has copied successfully."
	else
		log_app_msg "File dracula.xml already copied."
	fi
	return 0
}

function bible_project() {
	if [ ! -d "bible" ]; then
		git clone https://github.com/spiritEcosse/bible.git  && \
		cd bible && \
		git switch -c ${BIBLE_GIT_BRANCH} && \
		git branch --set-upstream-to=origin/${BIBLE_GIT_BRANCH} ${BIBLE_GIT_BRANCH} && \
		git pull && \
		cd ~/
		log_app_msg "Project bible has downloaded successfully."
	else
		log_app_msg "Project bible already exists."
	fi
	return 0
}

function set_envs() {
	echo "LIBGL_ALWAYS_INDIRECT=1" >> ~/.bashrc
	return 0
}

function git_aliases() {
	git config --global alias.co checkout                                                                                                                                        ─╯
	git config --global alias.ci commit
	git config --global alias.st status
	git config --global alias.br branch
	git config --global alias.hist "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short"
	git config --global alias.type 'cat-file -t'
	git config --global alias.dump 'cat-file -p'
	return 0
}

#read -p 'GITHUB_TOKEN: ' GITHUB_TOKEN &&
install_deps && \
install_docker && \
download_sailfish_sdk && \
git_aliases && \
bible_project && \
set_envs && \
theme_qtcreator && \
run_sailfish_sdk
