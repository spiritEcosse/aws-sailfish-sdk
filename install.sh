#!/bin/bash

# builtin variables
RED='\033[0;31m'
BLUE='\033[1;36m'
SDK_VERSION='3.7.4'

function log_app_msg() {
	echo -ne "[${BLUE}INFO${NC}] $@\n"
}

function log_failure_msg() {
	echo -ne "[${RED}ERROR${NC}] $@\n"
}

function install_deps() {
	sudo apt update -y && sudo apt install -y libxcb1 libx11-xcb1 libxcb1 libxcb-glx0 libfontconfig1 libx11-data libx11-xcb1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libsm6 libxkbcommon-x11-0 libwayland-egl1 libegl-dev libxcomposite1 libwayland-cursor0 libharfbuzz-dev libxi-dev libtinfo5 ca-certificates curl gnupg lsb-release
}

function install_docker() {
	# install docker
	# https://docs.docker.com/engine/install/ubuntu/

	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	sudo apt-get update -y && \
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io
	log_app_msg "docker already installed."
}

function manage_docker_as_a_non_root_user() {
	sudo usermod -aG docker $USER 
	exec sudo su -l $USER
	newgrp docker
	log_app_msg "Manage Docker as a non-root user. Successfully."
}

function install_sailfish_sdk() {
	# install sailfish sdk
	curl -O https://releases.sailfishos.org/sdk/installers/${SDK_VERSION}/SailfishSDK-${SDK_VERSION}-linux64-offline.run
	chmod +x SailfishSDK-${SDK_VERSION}-linux64-offline.run
	./SailfishSDK-${SDK_VERSION}-linux64-offline.run
}

install_deps && install_docker && manage_docker_as_a_non_root_user && install_sailfish_sdk
