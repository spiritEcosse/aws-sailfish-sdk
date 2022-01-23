#!/bin/bash

# builtin variables
RED='\033[0;31m'
BLUE='\033[1;36m'
SDK_VERSION='3.7.4'
SDK_FILE_NAME="SailfishSDK-${SDK_VERSION}-linux64-offline.run"
export LIBGL_ALWAYS_INDIRECT=1

function log_app_msg() {
	echo -ne "[${BLUE}INFO${NC}] $@\n"
}

function log_failure_msg() {
	echo -ne "[${RED}ERROR${NC}] $@\n"
}

function install_deps() {
	sudo apt update -y && \
	sudo apt install -y libxcb1 libx11-xcb1 libxcb1 libxcb-glx0 libfontconfig1 libx11-data libx11-xcb1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libsm6 libxkbcommon-x11-0 libwayland-egl1 libegl-dev libxcomposite1 libwayland-cursor0 libharfbuzz-dev libxi-dev libtinfo5 ca-certificates curl gnupg lsb-release mesa-utils libgl1-mesa-glx
}

function install_docker() {
	# install docker
	# https://docs.docker.com/engine/install/ubuntu/

	if [[ -x "$(docker -v)" ]]; then
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
		sudo apt-get update -y && \
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io

		sudo usermod -aG docker "$USER"
		newgrp docker
		log_app_msg "Manage Docker as a non-root user. Successfully."
	fi
	log_app_msg "docker already installed."
}

function download_sailfish_sdk() {
	if [ ! -f "${SDK_FILE_NAME}" ]; then
		curl -O https://releases.sailfishos.org/sdk/installers/${SDK_VERSION}/${SDK_FILE_NAME}
		chmod +x ${SDK_FILE_NAME}
		log_app_msg "Download ${SDK_FILE_NAME} has completed successfully."
	else
		log_app_msg "File ${SDK_FILE_NAME} already exists."
	fi
}

function run_sailfish_sdk() {
	if [[ -z ${DISPLAY} ]]; then
		./${SDK_FILE_NAME}
	fi
}

function theme_qtcreator() {
	if [ ! -d "qtcreator" ]; then
		git clone https://github.com/dracula/qtcreator.git
		cp qtcreator/dracula.xml /home/ubuntu/SailfishOS/share/qtcreator/styles/
		log_app_msg "File dracula.xml has copied successfully."
	fi
}

function bible_project() {
	if [ ! -d "bible" ]; then
		git clone https://github.com/spiritEcosse/bible.git
		log_app_msg "Project bible has downloaded successfully."
	fi
}

install_deps && \
install_docker && \
download_sailfish_sdk && \
theme_qtcreator && \
bible_project && \
run_sailfish_sdk
