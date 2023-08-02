#!/bin/bash

# TODO: create mock tests https://poisel.info/posts/2022-05-10-shell-unit-tests/

PS4='Line ${LINENO}: '

get_name_platform() {
  if uname -a | grep -i "GNU/Linux" >/dev/null
  then
    awk -F= '$1=="ID" { print $2 ;}' /etc/os-release
  elif uname -a | grep -i "darwin" >/dev/null
  then
    echo "darwin"
#  elif [[ "$OSTYPE" == "cygwin" ]]; then
#          # POSIX compatibility layer and Linux environment emulation for Windows
#  elif [[ "$OSTYPE" == "msys" ]]; then
#          # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
#  elif [[ "$OSTYPE" == "win32" ]]; then
#          # I'm not sure this can happen.
#  elif [[ "$OSTYPE" == "freebsd"* ]]; then
#          # ...
#  else
#          # Unknown.
  fi
}

add_flags() {
  # e - script stops on error (return != 0)
  # u - error if undefined variable
  # o pipefail - script fails if one of piped command fails
  # x - output each line (debug)

  set -euox pipefail
}

add_flags

get_sony_xperia_10_password() {
  PASSWORD=$(aws secretsmanager get-secret-value --secret-id sony_xperia_10 --query 'SecretString' --output text | grep -o '"PASSWORD":"[^"]*' |  grep -o '[^"]*$')
}

prepare_device() {
  echo "${PASSWORD}" | devel-su pkcon -y --allow-reinstall install gcc sudo make
  echo "${PASSWORD}" | devel-su bash -c 'echo "# User rules for nemo
nemo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/rules-for-user-nemo'
}

run_sshd_on_device() {
  devel-su systemctl restart sshd
}

install_bash() {
  BASH_VERSION=5.2
  NAME_BASH=bash-${BASH_VERSION}

  set +eo
  exe=$(exec 2>/dev/null; readlink "/proc/$$/exe")
  add_flags
  case "$exe" in
  */busybox)
      echo "It's a busybox shell."
      prepare_device
      cd ~/
      curl -O https://ftp.gnu.org/gnu/bash/${NAME_BASH}.tar.gz
      tar -xzvf ${NAME_BASH}.tar.gz
      cd ${NAME_BASH}
      ./configure --prefix=/usr                     \
        --bindir=/bin                     \
        --htmldir=/usr/share/doc/${NAME_BASH} \
        --without-bash-malloc             \
        --with-installed-readline
      make
      sudo make install
      ;;
  esac

  bash --version
}

install_bash &
wait

# builtin variables
RED='\033[0;31m'
BLUE='\033[1;36m'
#SDK_VERSION='3.9.6'
#SDK_FILE_NAME="SailfishSDK-${SDK_VERSION}-linux64-offline.run"
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
DOCKER_REPO="ghcr.io/spiritecosse/bible-sailfishos-"
SSH_ID_RSA="${HOME}/.ssh/id_rsa"
SSH_ID_RSA_PUB="${HOME}/.ssh/id_rsa.pub"
TEMP_SSH_ID_RSA="${HOME}/.id_rsa"
PATH=$HOME/bin:/usr/local/bin:$PATH

# Default values
funcs=main

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--func='* ) funcs="${1#*=}" ;;           # Handles --opt1
  esac
  shift
done

if [[ -z ${ARCH+x} ]]; then
  ARCH=$(uname -m)
fi

PLATFORM_HOST=$(get_name_platform)

if [[ -z ${PLATFORM+x} ]]; then
  PLATFORM=$(get_name_platform)
fi

if [[ -z ${EC2_INSTANCE_NAME+x} ]]; then
  EC2_INSTANCE_NAME=backup_server
fi

if [[ -z ${RELEASE+x} ]]; then
  RELEASE="latest"
fi

echo "RELEASE: ${RELEASE}"
echo "PLATFORM: ${PLATFORM}"
echo "ARCH: ${ARCH}"
echo "EC2_INSTANCE_NAME: ${EC2_INSTANCE_NAME}"
BUILD_FOLDER_NAME="${PLATFORM}_${ARCH}"
SRC_FOLDER_NAME="${PLATFORM}_${ARCH}_src"
BUILD_FOLDER="${HOME}/${BUILD_FOLDER_NAME}"
FILE_TAR=${BUILD_FOLDER_NAME}.tar
FILE=${FILE_TAR}.gz
FILE_SRC_TAR=${SRC_FOLDER_NAME}.tar
FILE_SRC=${FILE_SRC_TAR}.gz
BACKUP_FILE_PATH="${HOME}/${FILE}"
BACKUP_FILE_SRC_PATH="${HOME}/${FILE_SRC}"
DESTINATION_PATH="/usr/share/nginx/html/backups/"
HTTP_FILE="https://bible-backups.s3.amazonaws.com/${FILE}"
HTTP_FILE_SRC="https://bible-backups.s3.amazonaws.com/${FILE_SRC}"
SRC="${HOME}/${SRC_FOLDER_NAME}"

chown_current_user() {
  sudo chown -R "$(whoami):$(id -g -n)" .
}

install_jq() {
  # TODO: add prepare: install sudo make git
  if [[ ! $(jq --help) ]]; then
    git clone https://github.com/stedolan/jq.git
    cd jq
    autoreconf -i
    ./configure --disable-maintainer-mode
    make
    sudo make install
  fi
}

get_pending_time_shutdown() {
	date --date "@$(head -1 /run/systemd/shutdown/scheduled |cut -c6-15)"
}

set_rsync_params() {
  RSYNC_PARAMS_UPLOAD_SOURCE_CODE=(-rv --size-only --progress --stats --human-readable --exclude '.idea')
}

install_pigz() {
  PIGZ_VERSION=2.7
  NAME_PIGZ=pigz-${PIGZ_VERSION}

  if [[ $(pigz --version | awk -F ' ' '{print $2}') != "${PIGZ_VERSION}" ]];
  then
    cd ~/
    curl -O https://zlib.net/pigz/${NAME_PIGZ}.tar.gz
    tar -xzvf ${NAME_PIGZ}.tar.gz
    cd ${NAME_PIGZ}
    make
    sudo cp -f pigz /usr/bin/
    cd ~/
  fi

  pigz --version
}

aws_get_host() {
  EC2_INSTANCE_HOST=$(aws ec2 describe-instances --instance-ids "${EC2_INSTANCE}" --query "Reservations[*].Instances[*].[PublicIpAddress]" --output text)
  while [[ "$EC2_INSTANCE_HOST" == "None" ]]
  do
    sleep 5
    aws_get_host
  done
}

aws_wait_status_running() {
  EC2_INSTANCE_STATUS=$(aws_get_instance_status)
  while [[ "$EC2_INSTANCE_STATUS" != "running" ]]
  do
    sleep 5
    aws_wait_status_running
  done
}

set_ec2_instance() {
    EC2_INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EC2_INSTANCE_NAME}" --query 'Reservations[*].Instances[*].[InstanceId]' --output text)
}

aws_stop() {
  set_ec2_instance
  aws ec2 stop-instances --instance-ids "${EC2_INSTANCE}"
}

aws_get_instance_status() {
  aws ec2 describe-instance-status --instance-ids "${EC2_INSTANCE}" --query "InstanceStatuses[*].InstanceState.Name" --output text
}

install_aws() {
  if ! which aws; then
    if [[ "${PLATFORM_HOST}" == "ubuntu" ]]; then
      install_for_ubuntu python3-pip
    elif [[ "${PLATFORM_HOST}" == "sailfishos" ]]; then
      sudo zypper -n install python3-pip
    fi

    sudo pip install awscli
    aws --version
  fi

  mkdir -p ~/.aws/
  echo "[default]
  region = ${AWS_REGION}" > ~/.aws/config
}

set_ssh() {
  if [[ "${PLATFORM_HOST}" == "ubuntu" ]]; then
    install_for_ubuntu openssh-client
  elif [[ "${PLATFORM_HOST}" == "sailfishos" ]]; then
    sudo zypper -n install openssh
  fi

  mkdir -p "${HOME}"/.ssh
  touch ~/.ssh/known_hosts
  chmod 0700 "${HOME}"/.ssh

  if [[ ! -f "${SSH_ID_RSA}" ]]; then
    ssh-keygen -t rsa -q -f "${SSH_ID_RSA}" -N ""
    chmod 600 "${SSH_ID_RSA}"
  fi
}

get_ec2_instance_user() {
  EC2_INSTANCE_USER=$(aws secretsmanager get-secret-value --secret-id "${EC2_INSTANCE_NAME}" --query 'SecretString' --output text | grep -o '"EC2_INSTANCE_USER":"[^"]*' |  grep -o '[^"]*$')
}

get_ec2_github_token() {
  GIT_HUB_TOKEN_REGISTRY=$(aws secretsmanager get-secret-value --secret-id github --query 'SecretString' --output text | grep -o '"GIT_HUB_TOKEN_REGISTRY":"[^"]*' |  grep -o '[^"]*$')
}

get_ec2_instance_identify_file() {
  IDENTITY_FILE=$(aws secretsmanager get-secret-value --secret-id "${EC2_INSTANCE_NAME}" --query 'SecretString' --output text | grep -o '"IDENTITY_FILE":"[^"]*' |  grep -o '[^"]*$')
}

set_up_instance_aws_host_to_known_hosts () {
  set_ssh
  get_ec2_instance_user

  if ! grep "$1" ~/.ssh/known_hosts; then
    if [[ ! $(ssh-keyscan -H "$1") ]];then
      set_up_instance_aws_host_to_known_hosts "$1"
      return
    else
      SSH_KEYSCAN=$(ssh-keyscan -H "$1")
    fi

    printf "#start %s\n%s\n#end %s\n" "$1" "$SSH_KEYSCAN" "$1" >> ~/.ssh/known_hosts

    get_ec2_instance_identify_file
    echo "${IDENTITY_FILE}" | sed 's;\\n;\n;g' | sed -e 1b -e 's/ //' | sed 's;\\$;;' > "${TEMP_SSH_ID_RSA}"
    chmod 600 "${TEMP_SSH_ID_RSA}"
    cat "${SSH_ID_RSA_PUB}" | ssh -o StrictHostKeyChecking=no -i "${TEMP_SSH_ID_RSA}" "${EC2_INSTANCE_USER}@$1" 'cat >> ~/.ssh/authorized_keys'

    ssh "${EC2_INSTANCE_USER}@$1" "sudo shutdown +60"
  fi
}

aws_start() {
  if [[ $(aws_get_instance_status) != "running" ]]; then
    if [[ ! $(aws ec2 start-instances --instance-ids "${EC2_INSTANCE}") ]]; then
      sleep 3
      aws_start
    else
      aws_wait_status_running
    fi
  fi
}

rsync_from_host_to_sever() {
  set_rsync_params
  rsync --rsync-path="sudo rsync" "${RSYNC_PARAMS_UPLOAD_SOURCE_CODE[@]}" --delete --include "3rdparty/*.cmake" --exclude "3rdparty/*" ~/projects/bible/bible/ "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}:~/$1"
}

prepare_aws_instance() {
  install_aws
  set_ec2_instance
  aws_start
  aws_get_host
  set_up_instance_aws_host_to_known_hosts "${EC2_INSTANCE_HOST}"
}

download_backup() {
  rm -f "${1}"_*

  SEC=$SECONDS
  count=0
  start=0

  for i in $(seq 1 "${4}" "${3}"); do
    end=$(python3 -c "start = int(${start})
end = int(start + ${4} - 1)
size = int(${3})
print(size if end > size else end)")
    curl -r "${start}"-"${end}" "${2}" -o "${1}_${count}" &
    count=$(echo "${count}" + 1 | bc)
    start=$(python3 -c "print(int(${start}) + int(${4}))")
  done

  wait
  echo "after downloads : $(( SECONDS - SEC ))"

  cat $(ls "${1}"_* | sort -V) > "${1}";
}

system_prepare_ubuntu() {
  if [[ "$(whoami)" == "root" ]]; then
    apt update
    apt install -y sudo
  fi

  sudo apt update -y
  sudo apt upgrade -y
  sudo apt dist-upgrade -y
  # sudo dpkg --configure -a
}

file_get_size() {
  curl -sI "${1}" | grep -i Content-Length | awk '{print ($2+0)}'
}

download_backup_from_aws() {
  cd ~/

  if [[ -d "${5}" ]]; then
    ls -la "${5}"
    ls -la .
    return
  fi

  if [[ $(aws s3 ls s3://bible-backups/"${1}") ]]; then
    download_backup "${4}" "${3}" "$(file_get_size "${3}")" "$(python3 -c "print(100 * 1024 * 1024)")"
    wait

    unpigz -v "${1}" # TODO: this line is broken on the ubuntu, i will fix it in the future
    tar -xf "${2}"
    rm -f "${4}"*
    chown_current_user
  else
    echo "Cannot find file ${1} on aws s3"
    mkdir -p "${5}"
  fi
  ls -la "${5}"
  ls -la .
}

upload_backup() {
  cd "${HOME}"
  tar --use-compress-program="pigz -k " -cf "${1}" "${2}"

  SEC=$SECONDS
  aws s3 cp "${1}" s3://bible-backups
  echo "after aws s3 cp : $(( SECONDS - SEC ))"
  rm "${1}"
}

deploy_qml_files_to_device() {
#    if [[ $(find . -mmin -3 -type f | grep "qml") && ! $(find . -mmin -3 -type f | grep ".cpp" && find . -mmin -3 -type f | grep ".h") ]]; then
#      set_rsync_params
#      rsync --rsync-path="sudo rsync" "${RSYNC_PARAMS_UPLOAD_SOURCE_CODE[@]}" qml/ "nemo@192.168.18.12:/usr/share/bible/qml";
#    fi

    set_rsync_params
    rsync --rsync-path="sudo rsync" "${RSYNC_PARAMS_UPLOAD_SOURCE_CODE[@]}" qml/ "nemo@192.168.18.12:/usr/share/bible/qml";
    ssh "nemo@192.168.18.12" "
        export ARCH=${ARCH}
        export RELEASE=${RELEASE}
        export PLATFORM=${PLATFORM}
        curl https://spiritecosse.github.io/aws-sailfish-sdk/install.sh | bash -s -- --func=\"run_app_on_device\"
      "
}

get_device_ip() {
  DEVICE_IP=$(echo "${SSH_CLIENT}" | awk '{ print $1}')
}

set_up_instance_host_to_known_hosts () {
  set_ssh

  if ! grep "$1" ~/.ssh/known_hosts; then
    if [[ ! $(ssh-keyscan -H "$1") ]];then
      set_up_instance_host_to_known_hosts "$1"
      return
    else
      SSH_KEYSCAN=$(ssh-keyscan -H "$1")
    fi

    printf "#start %s\n%s\n#end %s\n" "$1" "$SSH_KEYSCAN" "$1" >> ~/.ssh/known_hosts

    sshpass -p "${PASSWORD}" ssh-copy-id -i "${SSH_ID_RSA_PUB}" "${EC2_INSTANCE_USER}@${DEVICE_IP}"
  fi
}

install_sshpass() {
  # Add install sshpass to Dockerfile

  if [[ ! $(which sshpass) ]]; then
    cd ~/
    curl -O https://altushost-swe.dl.sourceforge.net/project/sshpass/sshpass/1.08/sshpass-1.08.tar.gz
    tar -xf sshpass-1.08.tar.gz
    cd sshpass-1.08
    ./configure
    make
    sudo make install
  fi
}

set_access_ssh_to_device() {
  install_sshpass
  get_device_ip
  get_ec2_instance_user
  get_sony_xperia_10_password
  set_up_instance_host_to_known_hosts "${DEVICE_IP}"
}

install_asan() {
  if [[ "${PLATFORM_HOST}" == "ubuntu" ]]; then
    system_prepare_ubuntu
    install_for_ubuntu libasan6
  elif [[ "${PLATFORM_HOST}" == "sailfishos" ]]; then
    sudo zypper -n install libasan
  fi
}

mb2_cmake_build() {
  cd "${BUILD_FOLDER}"
  mb2_set_target
  chown_current_user
  mb2 build-init
  mb2 build-requires
  mb2 cmake -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON -DCODE_COVERAGE=ON -S "${SRC}" -B "${BUILD_FOLDER}"
  mb2 cmake --build . -j "$((2 * $(getconf _NPROCESSORS_ONLN)))"
}

get_last_modified_file() {
  LAST_RPM=$(ls -lt *.rpm | head -1 | awk '{ print $9 }')
}

rpm_install_app() {
  cd "${BUILD_FOLDER}"
  get_last_modified_file
  sudo pkcon -y --allow-reinstall install zypper
  sudo zypper -n install --allow-unsigned-rpm --force --details ${LAST_RPM}
}

remove_build_file() {
  mkdir -p ~/"${BUILD_FOLDER_NAME}"
  cd ~/"${BUILD_FOLDER_NAME}"
  rm -fr *
}

mb2_deploy_to_device() {
  cd "${SRC}"
  chown_current_user
  install_aws
  mb2_build
  cd "${BUILD_FOLDER}/RPMS"
  ls -lah
  set_access_ssh_to_device  # Todo make async
  get_last_modified_file
  run_commands_on_device remove_build_file
  scp "${LAST_RPM}" "${EC2_INSTANCE_USER}@${DEVICE_IP}:~/${BUILD_FOLDER_NAME}"
  run_commands_on_device rpm_install_app
}

mb2_build() {
  cd "${BUILD_FOLDER}"
  chown_current_user
  mb2_set_target
  mb2 build "${SRC}"
}

mb2_make_clean() {
  cd "${BUILD_FOLDER}"
  chown_current_user
  mb2_set_target
  mb2 make clean
}

mb2_run_tests() {
  cd "${BUILD_FOLDER}"
  chown_current_user
  mb2_set_target
  mb2 build-shell ctest --output-on-failure
}

run_app_on_device() {
  sudo usermod -aG systemd-journal $(whoami)
  systemd-run --user bible
  journalctl -f /usr/bin/bible
}

mb2_run_ccov_all_capture() {
  cd "${BUILD_FOLDER}"
  chown_current_user
  mkdir ccov
  mb2 build-shell make ccov-all-capture
}

run_commands_on_device() {
  install_aws
  set_access_ssh_to_device
  ssh "${EC2_INSTANCE_USER}@${DEVICE_IP}" "
    export PASSWORD=\"${PASSWORD}\"
    export ARCH=${ARCH}
    export RELEASE=${RELEASE}
    export PLATFORM=${PLATFORM}
    curl https://spiritecosse.github.io/aws-sailfish-sdk/install.sh | bash -s -- --func=\"$1\"
  "
}

codecov_push_results() {
  cd "${BUILD_FOLDER}"
  curl -Os https://uploader.codecov.io/latest/linux/codecov
  chmod +x codecov
  ./codecov -t "${CODECOV_TOKEN}" -f ccov/all-merged.info
}

rsync_share_to_src() {
  cd "${SRC}"
  set_rsync_params
  sudo rsync "${RSYNC_PARAMS_UPLOAD_SOURCE_CODE[@]}" --delete --include "3rdparty/*.cmake" --exclude "3rdparty/*" /share/ .
  chown_current_user
}

rsync_share_to_build() {
  cd "${BUILD_FOLDER}"
  set_rsync_params
  sudo rsync "${RSYNC_PARAMS_UPLOAD_SOURCE_CODE[@]}" "${SRC}/" .
  chown_current_user
}

mb2_set_target() {
  alias mb2='mb2 --target SailfishOS-$RELEASE-$ARCH'
}

download_backup_build_from_aws() {
  download_backup_from_aws "${FILE}" "${FILE_TAR}" "${HTTP_FILE}" "${BACKUP_FILE_PATH}" "${BUILD_FOLDER}"
}

download_backup_src_from_aws() {
  download_backup_from_aws "${FILE_SRC}" "${FILE_SRC_TAR}" "${HTTP_FILE_SRC}" "${BACKUP_FILE_SRC_PATH}" "${SRC}"
}

code_coverage() {
  if [[ "${PLATFORM_HOST}" == "ubuntu" ]]; then
    system_prepare_ubuntu
    install_for_ubuntu curl pigz
  elif [[ "${PLATFORM_HOST}" == "sailfishos" ]]; then
    sudo zypper -n install curl pigz
  fi

  df -h

  mkdir -p "${BUILD_FOLDER}"
  download_backup_build_from_aws
  download_backup_src_from_aws
  rsync_share_to_src
  rsync_share_to_build
  mb2_cmake_build
  upload_backup "${FILE}" "${BUILD_FOLDER_NAME}"
  upload_backup "${FILE_SRC}" "${SRC_FOLDER_NAME}"
  mb2_run_tests
  mb2_run_ccov_all_capture
  codecov_push_results
  wait
}

install_for_ubuntu() {
  programs=()

  for lib in "$@"
  do
      if [[ ! $(dpkg -s ${lib}) ]]
      then
          echo "============================================= install ${lib} ===================================================="
          sudo apt-get install -y ${lib}
      fi

      programs+=("${lib}: `dpkg -s ${lib} | grep Status && dpkg -s ${lib} | grep Version || echo 'Not installed'`\n")
  done

  if [[ "${programs}" ]]
  then
    log_app_msg "Installed programs: "
    echo -e "${programs[@]}"
  fi
}

log_app_msg() {
	echo -ne "[${BLUE}INFO] $@\n"
}

log_failure_msg() {
	echo -ne "[${RED}ERROR] $@\n"
}

set_tz() {
	sudo timedatectl list-timezones | grep Europe
	sudo timedatectl set-timezone Europe/Madrid
	timedatectl
}

install_deps() {
	system_prepare_ubuntu
#	install_for_ubuntu sudo systemd libxcb1 libx11-xcb1 libxcb1 libxcb-glx0 libfontconfig1 libx11-data libx11-xcb1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libsm6 libxkbcommon-x11-0 libwayland-egl1 libegl-dev libxcomposite1 libwayland-cursor0 libharfbuzz-dev libxi-dev libtinfo5 ca-certificates curl gnupg lsb-release mesa-utils libgl1-mesa-glx micro lsb-release sudo zsh git
  install_for_ubuntu sudo systemd ca-certificates curl micro lsb-release zsh
}

install_virtualbox() {
	sudo apt-get install -y virtualbox
	log_app_msg "virtualbox has installed successfully."
}

install_docker() {
	# install docker
	# https://docs.docker.com/engine/install/ubuntu/

	if ! which docker; then
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
		sudo apt-get update -y
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io
		sudo usermod -aG docker "$USER"
		log_app_msg "Manage Docker as a non-root user. Successfully."
		exit 0
	fi
	log_app_msg "docker already installed."
}

rm_sdk_settings() {
  rm -fr ~/.config/SailfishSDK
}

docker_removecontainers() {
  if [[ $(docker ps -aq) ]]; then
    docker stop $(docker ps -aq)
  fi
  if [[ $(docker ps -aq) ]]; then
    docker rm $(docker ps -aq)
  fi
}

docker_armaggedon() {
  docker_removecontainers
  docker network prune -f
  if [[ $(docker images --filter dangling=true -qa) ]]; then
    docker rmi -f $(docker images --filter dangling=true -qa)
  fi
  if [[ $(docker volume ls --filter dangling=true -q) ]]; then
    docker volume rm $(docker volume ls --filter dangling=true -q)
  fi
  if [[ $(docker images -qa) ]]; then
    docker rmi -f $(docker images -qa)
  fi
}

set_envs() {
	LIBGL_ALWAYS_INDIRECT="LIBGL_ALWAYS_INDIRECT=1"
	if ! grep "$LIBGL_ALWAYS_INDIRECT" ~/.bashrc; then
		echo "$LIBGL_ALWAYS_INDIRECT" >> ~/.bashrc
	fi
	if ! grep "$LIBGL_ALWAYS_INDIRECT" ~/.zshrc; then
		echo "$LIBGL_ALWAYS_INDIRECT" >> ~/.zshrc
	fi
	PATH_="export PATH=$HOME/bin:/usr/local/bin:\$PATH"
	if ! grep "$PATH_" ~/.bashrc; then
		echo "$PATH_" >> ~/.bashrc
	fi
	if ! grep "$PATH_" ~/.zshrc; then
		echo "$PATH_" >> ~/.zshrc
	fi
}

set_zsh_by_default() {
	sudo chsh -s $(which zsh) $(whoami)
}

set_zsh_by_default_user() {
	sudo chsh -s $(which zsh) "$1"
}

install_ohmyzsh() {
	if [[ ! -d ".oh-my-zsh" && -z ${DOCKER_RUNNING+x} ]]; then
		sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	fi
	set_envs
}

git_submodule_remove() {
  for module in $(echo "$1" | tr "," "\n")
  do
    # Remove the submodule entry from .git/config
    if [[ $(git submodule deinit -f 3rdparty/"${module}") ]];then
      echo 'success: git submodule deinit'
    fi

    # Remove the submodule directory from the superproject's .git/modules directory
    rm -rf .git/modules/3rdparty/"${module}"

    # Remove the entry in .gitmodules and remove the submodule directory located at path/to/submodule
    if [[ $(git rm -f 3rdparty/"${module}") ]];then
      echo 'success: git rm -f'
    fi

    rm -fr 3rdparty/"${module}"
  done
}

git_submodule_init() {
	URL=$(git config --file .gitmodules --get-regexp url | grep "${1}" | awk '{ print $2 }' | tr ' ' '\n')
	git submodule add --depth 1 "${URL}" "${1}"
}

git_submodule_checkout() {
  for folder_name in $(git config --file .gitmodules --get-regexp path | awk '{ print $2 }' | tr ' ' '\n'); do
    if [[ ! $(git submodule status | grep "${folder_name}") ]]; then
      git_submodule_init "${folder_name}"
    elif [[ ! $(ls -la "${folder_name}/.git") ]]; then
#      rm -fr "${folder_name}"
      git submodule update --depth 1 --init "${folder_name}"
#      git fetch --tags # disable it because : Line 718: git fetch --tags
         #error: Could not read a2294d0d05f85c67c172551742a224e6a1f11d15
         #error: Could not read 27b62c5566a769a9379251b1a8c63dc5f9dfe1f2
         #error: Could not read 3cb38058058ca9f830a877bc672c0458bf379b34
         #error: Could not read a2294d0d05f85c67c172551742a224e6a1f11d15
         #error: Could not read 8fa1bd0092144308f2df65477fa1336d315e44c7
         #error: Could not read 84ea54549417e19caac8035b6c5fb3ba580045f6
         #fatal: pack has 593 unresolved deltas
         #fatal: index-pack failed
    fi

    TAG=$(git config --file .gitmodules --get-regexp tag | grep "${folder_name}" | awk '{ print $2 }' | tr ' ' '\n')
    cd "${folder_name}"
    if [[ ! $(git tag | grep "${TAG}") ]]; then
       git fetch origin tag "${TAG}" --no-tags
    fi

    cd ../../
  done

  git submodule foreach -q --recursive 'git checkout $(git config -f $toplevel/.gitmodules submodule.$name.tag)'
}

ec2_user_add_to_nginx_group() {
  # For backup server
  sudo usermod -a -G nginx ec2-user
}

nginx_destination_path_chown_ec2_user() {
  # For backup server
  sudo chown -R ec2-user:nginx "${DESTINATION_PATH}"
}

docker_login() {
  get_ec2_github_token
  # TODO: add smart check
  echo "${GIT_HUB_TOKEN_REGISTRY}" | docker login ghcr.io -u spiritEcosse --password-stdin
}

docker_push() {
  docker push "${DOCKER_REPO}${ARCH}:${RELEASE}"
}

docker_build() {
  docker build -t "${DOCKER_REPO}${ARCH}:${RELEASE}" --build-arg ARCH="${ARCH}" --build-arg RELEASE="${RELEASE}" .
}

docker_run_container() {
  if [[ ! $(docker start "${BUILD_FOLDER_NAME}") ]]; then
    docker run --name "${BUILD_FOLDER_NAME}" \
      -v "${PWD}:/home/mersdk/${BUILD_FOLDER_NAME}" \
      -v "${SRC}:/home/mersdk/${SRC_FOLDER_NAME}" \
      -dit "${DOCKER_REPO}${ARCH}:${RELEASE}" bash
  fi
}

docker_run_bash() {
    cd "${BUILD_FOLDER}"

    docker_run_container

    docker exec --privileged \
      -e BUILD_FOLDER="/home/mersdk/${BUILD_FOLDER_NAME}" \
      -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
      -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
      -e AWS_REGION="${AWS_REGION}" \
      -e ARCH="${ARCH}" \
      -e RELEASE="${RELEASE}" \
      -e EC2_INSTANCE_NAME="sony_xperia_10" \
      -e SSH_CLIENT="${SSH_CLIENT}" \
      -it \
      "${BUILD_FOLDER_NAME}" \
      /bin/bash
}

docker_run_commands() {
  cd "${BUILD_FOLDER}"

  docker_run_container

  docker exec --privileged \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    -e AWS_REGION="${AWS_REGION}" \
    -e ARCH="${ARCH}" \
    -e RELEASE="${RELEASE}" \
    -e EC2_INSTANCE_NAME="sony_xperia_10" \
    -e SSH_CLIENT="${SSH_CLIENT}" \
    "${BUILD_FOLDER_NAME}" \
    /bin/bash -c "
      curl https://spiritecosse.github.io/aws-sailfish-sdk/install.sh | bash -s -- --func=\"$1\"
    "
}

aws_run_commands() {
  prepare_aws_instance
  if [[ -z ${DONT_NEED_DEPLOY+x} ]]; then
    rsync_from_host_to_sever "${SRC_FOLDER_NAME}"
  fi

  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
    export ARCH=${ARCH}
    export RELEASE=${RELEASE}
    export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
    export AWS_REGION=${AWS_REGION}
    export PLATFORM=${PLATFORM}
    curl https://spiritecosse.github.io/aws-sailfish-sdk/install.sh | bash -s -- --func=\"$1\"
  "
}

docker_login_build_push() {
  mkdir -p ~/bible
  cd ~/bible
  docker_login
  docker_build
  docker_push
}

sdk_download() {
  docker_login
  docker pull "${DOCKER_REPO}${ARCH}:${RELEASE}"
}

main_from_client() {
  echo "ARCH: ${ARCH}"
  echo "EC2_INSTANCE_NAME: ${EC2_INSTANCE_NAME}"
  echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}"
  echo "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}"
  echo "AWS_REGION: ${AWS_REGION}"

  prepare_aws_instance
  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
    curl https://spiritecosse.github.io/aws-sailfish-sdk/install.sh | bash
  "
  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
    export ARCH=${ARCH}
    export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
    export AWS_REGION=${AWS_REGION}
    curl https://spiritecosse.github.io/aws-sailfish-sdk/install.sh | bash
  "
}

main() {
  install_deps
  install_docker
  install_ohmyzsh &
  set_zsh_by_default &
  set_tz &
  set_ssh &
  sdk_download &
  wait
}

set +ex
OPTIND=1 l=0 r=0;
while   getopts : na -"${funcs}"
do      [[ "$l" -gt "$r" ]]
        case    $?$OPTARG  in
        (1\;)  ! l=0 r=0    ;;
        (0\))    r=$((r+1)) ;;
        (?\()    l=$((l+1)) ;;
        esac    &&
        set -- "$*$OPTARG" ||
        set -- "$@" " "
done;
set -ex

echo "Start function ${funcs}"

for func in $(echo "$@")
do
  func_with_params=$(echo "${func}" | sed 's;=; ;')
  params=$(echo "${func_with_params}" | cut -d ' ' -f2)

  if [[ "${params}" = \(* ]]; then
    $(echo ${func_with_params} | sed 's; (; ;g' | sed 's;)$;;g')
  else
    ${func_with_params}
  fi
done
