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
SSH_ID_RSA="${HOME}/.ssh/id_rsa"

# Default values
func=main
operands=()

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--func='* ) func="${1#*=}" ;;           # Handles --opt1
    ( '--' ) operands+=( "${@:2}" ); break ;;  # End of options
    ( '-'?* ) ;;                               # Discard non-valid options
    ( * ) operands+=( "${1}" )                 # Handles operands
  esac
  shift
done

if [[ -z ${ARCH+x} ]]; then
  ARCH=$(uname -m)
fi

get_name_platform() {
  awk -F= '$1=="ID" { print $2 ;}' /etc/os-release
}

if [[ -z ${PLATFORM+x} ]]; then
  PLATFORM=$(get_name_platform)
fi

BUILD_FOLDER="${HOME}/${PLATFORM}_${ARCH}"
FILE=${PLATFORM}_${ARCH}.tar.gz
BACKUP_FILE_PATH="${HOME}/${FILE}"
DESTINATION_PATH="/usr/share/nginx/html/backups/"
DESTINATION_FILE_PATH="${DESTINATION_PATH}${FILE}"

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

aws_stop() {
  aws ec2 stop-instances --instance-ids "${EC2_INSTANCE}"
}

aws_get_instance_status() {
  aws ec2 describe-instance-status --instance-ids "${EC2_INSTANCE}" --query "InstanceStatuses[*].InstanceState.Name" --output text
}

install_aws() {
  if ! which aws; then
    if [[ "${PLATFORM}" == "ubuntu" ]]; then
      install_for_ubuntu python3-pip
    elif [[ "${PLATFORM}" == "sailfishos" ]]; then
      sudo zypper -n install python3-pip
    fi

    sudo pip install awscli
    aws --version
    mkdir -p ~/.aws/
    echo "[default]
    region = ${AWS_REGION}" > ~/.aws/config
  fi
}

set_up_instance_aws_host_to_known_hosts () {
  if ! grep "$1" ~/.ssh/known_hosts; then
    if [[ ! $(ssh-keyscan -H "$1") ]];then
      sleep 5
      set_up_instance_aws_host_to_known_hosts "$1"
    else
      SSH_KEYSCAN=$(ssh-keyscan -H "$1")
    fi

    printf "#start %s\n%s\n#end %s\n" "$1" "$SSH_KEYSCAN" "$1" >> ~/.ssh/known_hosts
    ssh "${EC2_INSTANCE_USER}"@"$1" "sudo shutdown +60"

    if [[ -f ".idea/sshConfigs.xml" && -f ".idea/.idea/webServers.xml" ]]; then
      sed -i '' -e "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$1/g" .idea/webServers.xml .idea/sshConfigs.xml
    fi
  fi
}

aws_start() {
  if [[ $(aws_get_instance_status) != "running" ]]; then
    if [[ ! $(aws ec2 start-instances --instance-ids "${EC2_INSTANCE}") ]]; then
      sleep 5
      aws_start
    else
      aws_wait_status_running
    fi
  fi
}

sfdk_deploy_to_device() {
  prepare_aws_instance
  ssh -i "${ID_FILE}" "${EC2_INSTANCE_USER}"@"${EC2_INSTANCE_HOST}" "
    export BUILD_FOLDER=\"${BUILD_FOLDER}\"
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_device_list
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_tools_list
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_config_device_sony
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_config_target_sony
    cd ~/\"${BUILD_FOLDER}\"
    sfdk build ../bible
    sfdk deploy --sdk
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_device_exec_app
  "
}

sailfish_run_tests_on_aws() {
    prepare_aws_instance
    ssh -i "${ID_FILE}" "${EC2_INSTANCE_USER}"@"${EC2_INSTANCE_HOST}" "
      export BUILD_FOLDER=\"${BUILD_FOLDER}\"
      curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_tools_list
      curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_config_target_sony
      cd \"${BUILD_FOLDER}\"
      sfdk build ../bible -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON -DCODE_COVERAGE=ON
      sfdk build-shell ctest --output-on-failure
    "
}

sfdk_run_app_on_device() {
  # on device: devel-su usermod -a -G systemd-journal nemo
  prepare_aws_instance
  ssh -i "${ID_FILE}" "${EC2_INSTANCE_USER}"@"${EC2_INSTANCE_HOST}" "
    export ARCH=\"${ARCH}\"
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_device_list
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_config_device_sony
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=sfdk_device_exec_app
  "
}

sfdk_device_list() {
  sfdk device list
}

sfdk_config_target_sony() {
  sfdk config target=SailfishOS-4.4.0.58-"${ARCH}"
}

sfdk_config_device_sony() {
  sfdk config device='Xperia 10 - Dual SIM \(ARM\)'
}

sfdk_device_exec_app() {
  sfdk device exec /usr/bin/bible &
  sfdk device exec journalctl -f /usr/bin/bible
}

prepare_aws_instance() {
  install_aws
  aws_start
  aws_get_host
  set_up_instance_aws_host_to_known_hosts "${EC2_INSTANCE_HOST}"
}

upload_backup() {
  prepare_aws_instance
  cd "${HOME}"
  tar -zcf "${FILE}" "${PLATFORM}_${ARCH}"
  scp "${FILE}" "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}:${DESTINATION_PATH}"
#  rsync -av --inplace --progress "${FILE}" "${EC2_INSTANCE_USER}"@"${EC2_INSTANCE_HOST}":"${DESTINATION_PATH}"
  aws_stop
}

mb2_cmake_build() {
  cd "${BUILD_FOLDER}"
  mb2 build-init
  mb2 build-requires
  mb2 cmake -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON -DCODE_COVERAGE=ON
  mb2 cmake --build .
}

mb2_run_tests() {
  cd "${BUILD_FOLDER}"
  mb2 build-shell ctest --output-on-failure
}

mb2_run_ccov_all_capture() {
  cd "${BUILD_FOLDER}"
  mkdir ccov
  mb2 build-shell make ccov-all-capture
}

codecov_push_results() {
  cd "${BUILD_FOLDER}"
  curl -Os https://uploader.codecov.io/latest/linux/codecov
  chmod +x codecov
  ./codecov -t "${CODECOV_TOKEN}" -f ccov/all-merged.info
}

rsync_share_to_build() {
  cd "${BUILD_FOLDER}"
  sudo rsync -rv --checksum --ignore-times --info=progress2 --stats --human-readable --exclude '.git/modules' /share/ .
  sudo chown -R mersdk:mersdk .
}

code_coverage() {
  alias mb2='mb2 --target SailfishOS-$RELEASE-$ARCH'
  download_backup
  rsync_share_to_build
  mb2_cmake_build
  upload_backup
  mb2_run_tests
  mb2_run_ccov_all_capture
  codecov_push_results
  wait
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
	install_for_ubuntu sudo systemd libxcb1 libx11-xcb1 libxcb1 libxcb-glx0 libfontconfig1 libx11-data libx11-xcb1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libsm6 libxkbcommon-x11-0 libwayland-egl1 libegl-dev libxcomposite1 libwayland-cursor0 libharfbuzz-dev libxi-dev libtinfo5 ca-certificates curl gnupg lsb-release mesa-utils libgl1-mesa-glx micro lsb-release sudo zsh git
}

install_virtualbox() {
	sudo apt-get install -y virtualbox
	log_app_msg "virtualbox has installed successfully."
}

install_docker() {
	# install docker
	# https://docs.docker.com/engine/install/ubuntu/

	if ! which docker; then
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
		sudo apt-get update -y && \
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io && \
		sudo usermod -aG docker "$USER"
		log_app_msg "Manage Docker as a non-root user. Successfully."
		exit 0
	fi
	log_app_msg "docker already installed."
}

sfdk_download() {
	if [ ! -f "${SDK_FILE_NAME}" ]; then
		curl -O https://releases.sailfishos.org/sdk/installers/${SDK_VERSION}/${SDK_FILE_NAME} && \
		chmod +x ${SDK_FILE_NAME}
		log_app_msg "Download ${SDK_FILE_NAME} has completed successfully."
	else
	  ls -la .
		log_app_msg "File ${SDK_FILE_NAME} already exists."
	fi
}

sfdk_install() {
  if [[ ! -d "SailfishOS" ]]; then
	  QT_QPA_PLATFORM=minimal ./${SDK_FILE_NAME} --verbose non-interactive=1 accept-licenses=1 build-engine-type=docker
	else
	  log_app_msg "Folder SailfishOS already exists."
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

create_spec_dirs() {
	mkdir -p ~/build-bible-SailfishOS_4_4_0_58_armv7hl_in_sailfish_sdk_build_engine_ubuntu-Debug
}

install_ohmyzsh() {
	if [[ ! -d ".oh-my-zsh" && -z ${DOCKER_RUNNING+x} ]]; then
		sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	fi
}

sfdk_put_to_bin() {
  mkdir -p ~/bin

  echo '#!/bin/sh
exec ~/SailfishOS/bin/sfdk "$@"' > ~/bin/sfdk
  chmod +x ~/bin/sfdk
}

sfdk_tools_list() {
  sfdk tools list
}

set_ssh() {
  if [[ "${PLATFORM}" == "ubuntu" ]]; then
    install_for_ubuntu openssh-client
  elif [[ "${PLATFORM}" == "sailfishos" ]]; then
    sudo zypper -n install openssh
  fi

  mkdir -p "${HOME}"/.ssh
  touch ~/.ssh/known_hosts
  chmod 0700 "${HOME}"/.ssh

  if [[ ! -f "${SSH_ID_RSA}" ]]; then
    if [[ -z ${IDENTITY_FILE+x} ]]; then
      ssh-keygen -t rsa -q -f "${SSH_ID_RSA}" -N ""
    else
      echo "${IDENTITY_FILE}" > "${SSH_ID_RSA}"
    fi
    chmod 600 "${SSH_ID_RSA}"
  fi
}

ssh_copy_id() {
  SAILFISH_IP=$(echo "$SSH_CLIENT" | awk '{ print $1}')
  set_up_instance_host_to_known_hosts "$SAILFISH_IP"
  ssh-copy-id -i "$SSH_ID_RSA.pub" nemo@"${SAILFISH_IP}"
}

set_up_instance_host_to_known_hosts () {
  if ! grep "$1" ~/.ssh/known_hosts; then
    SSH_KEYSCAN=$(ssh-keyscan -T 180 -H "$1")
    printf "#start %s\n%s\n#end %s\n" "$1" "$SSH_KEYSCAN" "$1" >> ~/.ssh/known_hosts
  fi
}

prepare_user_mersdk() {
  USER_MERSDK=mersdk
  if [[ ! $(getent passwd | grep "${USER_MERSDK}") ]]; then
    sudo adduser --disabled-password --gecos "" "${USER_MERSDK}"
    sudo usermod -a -G adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev "${USER_MERSDK}"
    sudo cp -fr ~/.ssh /home/"${USER_MERSDK}"/
    sudo chown -R "${USER_MERSDK}": /home/"${USER_MERSDK}"/
    sudo bash -c 'echo "# User rules for mersdk
mersdk ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/rules-for-user-mersdk'
    exit 0
  fi
}

file_get_size() {
  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "stat -c%s ${DESTINATION_FILE_PATH}"
}

download_backup() {
  echo "${EC2_INSTANCE_USER}"
  echo "${BACKUP_FILE_PATH}"
  echo "${EC2_INSTANCE}"
  echo "${SSH_ID_RSA}"
  echo "${AWS_ACCESS_KEY_ID}"
  echo "${AWS_REGION}"
  echo "${AWS_SECRET_ACCESS_KEY}"

  if [[ "${PLATFORM}" == "ubuntu" ]]; then
    system_prepare_ubuntu
    install_for_ubuntu openssl curl
  elif [[ "${PLATFORM}" == "sailfishos" ]]; then
    sudo zypper -n install openssl curl
  fi

  set_ssh
  prepare_aws_instance

  cd ~/

  if [[ $(file_get_size) ]]; then # TODO put result to SIZE_BACKUP_FILE
    SIZE_BACKUP_FILE=$(file_get_size)
    CHUNKS=$(python3 -c "print(100 * 1024 * 1024)")
    HASH_ORIGINAL=$(ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "openssl sha256 ${DESTINATION_FILE_PATH} | awk -F'= ' '{print \$2}'")

    rm -f ${BACKUP_FILE_PATH}*

    SEC=$SECONDS
    count=0
    start=0
    for i in `seq 1 ${CHUNKS} ${SIZE_BACKUP_FILE}`; do
    	end=$(python3 -c "start = int(${start})
end = int(start + ${CHUNKS} - 1)
size = int(${SIZE_BACKUP_FILE})
print(size if end > size else end)")
      curl -r "${start}"-"${end}" http://"${EC2_INSTANCE_HOST}/backups/${FILE}" -o "${BACKUP_FILE_PATH}_${count}" &
    	count=$(( "${count}" + 1 ))
    	start=$(python3 -c "print(int(${start}) + int(${CHUNKS}))")
    done
    wait
    echo "after downloads : $(( SECONDS - SEC ))"

    cat $(ls ${BACKUP_FILE_PATH}_* | sort -V) > "${BACKUP_FILE_PATH}";

    HASH=$(openssl sha256 "${BACKUP_FILE_PATH}" | awk -F'= ' '{print $2}')
    [ "$HASH_ORIGINAL" = "$HASH" ]

    tar -xf "${FILE}"
  else
    mkdir -p "${BUILD_FOLDER}"
  fi
  ls -la "${BUILD_FOLDER}"
}

ec2_user_add_to_nginx_group() {
  # For backup server
  sudo usermod -a -G nginx ec2-user
}

nginx_destination_path_chown_ec2_user() {
  # For backup server
  sudo chown -R ec2-user:nginx "${DESTINATION_PATH}"
}

main() {
  prepare_user_mersdk
  [ "$(whoami)" = "mersdk" ]
  create_spec_dirs &
  set_envs &
  sfdk_put_to_bin &
  install_deps
  install_docker
  install_ohmyzsh &
  set_tz &
  set_zsh_by_default &
  set_ssh
  sfdk_download

  # Due to qemu-x86_64: Could not open '/lib64/ld-linux-x86-64.so.2': No such file or directory; TODO: add smart check
  if [[ -z ${DOCKER_RUNNING+x} ]]; then
    sfdk_install
    sfdk_tools_list
  fi
  wait
}

$func
