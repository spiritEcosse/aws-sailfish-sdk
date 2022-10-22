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
SSH_ID_RSA_PUB="${HOME}/.ssh/id_rsa.pub"
TEMP_SSH_ID_RSA="${HOME}/.id_rsa"
PATH=$HOME/bin:/usr/local/bin:$PATH

# Default values
funcs=main
operands=()

# Arguments handling
while (( ${#} > 0 )); do
  case "${1}" in
    ( '--func='* ) funcs="${1#*=}" ;;           # Handles --opt1
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
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    awk -F= '$1=="ID" { print $2 ;}' /etc/os-release
  elif [[ "$OSTYPE" == "darwin"* ]]; then
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

PLATFORM_HOST=$(get_name_platform)

if [[ -z ${PLATFORM+x} ]]; then
  PLATFORM=$(get_name_platform)
fi

echo "PLATFORM: ${PLATFORM}"
echo "ARCH: ${ARCH}"
echo "EC2_INSTANCE_NAME: ${EC2_INSTANCE_NAME}"
BUILD_FOLDER="${HOME}/${PLATFORM}_${ARCH}"
FILE_TAR=${PLATFORM}_${ARCH}.tar
FILE=${FILE_TAR}.gz
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
    cat "${TEMP_SSH_ID_RSA}"
    chmod 600 "${TEMP_SSH_ID_RSA}"
    cat "${SSH_ID_RSA_PUB}" | ssh -o StrictHostKeyChecking=no -i "${TEMP_SSH_ID_RSA}" "${EC2_INSTANCE_USER}@$1" 'cat >> ~/.ssh/authorized_keys'

    ssh "${EC2_INSTANCE_USER}@$1" "sudo shutdown +60"

    if [[ -f ".idea/sshConfigs.xml" && -f ".idea/webServers.xml" ]]; then
      sed -i '' -e "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$1/g" .idea/webServers.xml .idea/sshConfigs.xml
    fi
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

prepare_aws_instance() {
  install_aws
  set_ec2_instance
  aws_start
  aws_get_host
  set_up_instance_aws_host_to_known_hosts "${EC2_INSTANCE_HOST}"
}

sfdk_deploy_to_device() {
  prepare_aws_instance
  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
    export ARCH=${ARCH}
    export PLATFORM=${PLATFORM}
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func='sfdk_device_list;sfdk_tools_list;sfdk_config_device_sony;sfdk_config_target_sony;sfdk_build_deploy;sfdk_device_exec_app'
  "
}

sailfish_run_tests_on_aws() {
    prepare_aws_instance
    ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
      export ARCH=${ARCH}
      export PLATFORM=${PLATFORM}
      curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func='sfdk_tools_list;sfdk_config_target_sony;sfdk_build_test'
    "
}

sfdk_run_app_on_device() {
  prepare_aws_instance
  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
    export ARCH=${ARCH}
    export PLATFORM=${PLATFORM}
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func='sfdk_device_list;sfdk_config_device_sony;sfdk_device_exec_app'
  "
}

sfdk_build_test() {
  cd "${BUILD_FOLDER}"
  sfdk build ../bible -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON -DCODE_COVERAGE=ON
  sfdk build-shell ctest --output-on-failure
}

sfdk_build_deploy() {
  cd "${BUILD_FOLDER}"
  sfdk build ../bible
  sfdk deploy --sdk
}

sfdk_device_list() {
  sfdk device list
}

sfdk_tools_list() {
  sfdk tools list
}

sfdk_config_target_sony() {
  sfdk config target=SailfishOS-4.4.0.58-"${ARCH}"
}

sfdk_config_device_sony() {
  sfdk config device='Xperia 10 - Dual SIM \(ARM\)'
}

sfdk_device_exec_app() {
  # on device: devel-su usermod -a -G systemd-journal nemo
  sfdk device exec /usr/bin/bible &
  sfdk device exec journalctl -f /usr/bin/bible
}

download_backup_from_aws_to_aws() {
  echo "ARCH: ${ARCH}"
  echo "PLATFORM: ${PLATFORM}"
  echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}"
  echo "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}"
  echo "AWS_REGION: ${AWS_REGION}"

  prepare_aws_instance
  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
    export ARCH=${ARCH}
    export PLATFORM=${PLATFORM}
    export EC2_INSTANCE_NAME=backup_server
    export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
    export AWS_REGION=${AWS_REGION}
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=download_backup_from_aws
  "
}

set_ec2_instance() {
    EC2_INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EC2_INSTANCE_NAME}" --query 'Reservations[*].Instances[*].[InstanceId]' --output text)
}

download_backup() {
  rm -f ${BACKUP_FILE_PATH}*

  SEC=$SECONDS
  count=0
  start=0

  for i in `seq 1 ${CHUNKS} ${SIZE_BACKUP_FILE}`; do
    end=$(python3 -c "start = int(${start})
end = int(start + ${CHUNKS} - 1)
size = int(${SIZE_BACKUP_FILE})
print(size if end > size else end)")
    curl -r "${start}"-"${end}" "${1}" -o "${BACKUP_FILE_PATH}_${count}" &
    count=$(( "${count}" + 1 ))
    start=$(python3 -c "print(int(${start}) + int(${CHUNKS}))")
  done

  wait
  echo "after downloads : $(( SECONDS - SEC ))"

  cat $(ls ${BACKUP_FILE_PATH}_* | sort -V) > "${BACKUP_FILE_PATH}";
}

download_backup_from_aws() {
  if [[ "${PLATFORM_HOST}" == "ubuntu" ]]; then
    system_prepare_ubuntu
    install_for_ubuntu openssl curl pigz
  elif [[ "${PLATFORM_HOST}" == "sailfishos" ]]; then
    sudo zypper -n install openssl curl pigz
  fi

  prepare_aws_instance

  cd ~/

  if [[ $(file_get_size) ]]; then # TODO put result to SIZE_BACKUP_FILE
    SIZE_BACKUP_FILE=$(file_get_size)
    CHUNKS=$(python3 -c "print(100 * 1024 * 1024)")

    ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "openssl sha256 ${DESTINATION_FILE_PATH} | awk -F'= ' '{print \$2}'" > "${FILE}"-hash &
    download_backup http://"${EC2_INSTANCE_HOST}/backups/${FILE}"
    wait
    HASH_ORIGINAL=$(cat "${FILE}"-hash)
    HASH=$(openssl sha256 "${BACKUP_FILE_PATH}" | awk -F'= ' '{print $2}')
    [ "$HASH_ORIGINAL" = "$HASH" ]

    unpigz -v "${FILE}"
    tar -xf "${FILE_TAR}"
  else
    mkdir -p "${BUILD_FOLDER}"
  fi
  ls -la "${BUILD_FOLDER}"
}

upload_backup() {
  if [[ "${PLATFORM_HOST}" == "ubuntu" ]]; then
    install_for_ubuntu pigz
  elif [[ "${PLATFORM_HOST}" == "sailfishos" ]]; then
    sudo zypper -n install pigz
  fi

  cd "${HOME}"
  tar --use-compress-program="pigz -k " -cf "${FILE}" "${PLATFORM}_${ARCH}"
  HASH=$(openssl sha256 "${FILE}" | awk -F'= ' '{print $2}')

  if [[ "${HASH_ORIGINAL}" != "${HASH}" ]]; then
    prepare_aws_instance
    SEC=$SECONDS
    scp "${FILE}" "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}:${DESTINATION_PATH}"
    echo "after scp : $(( SECONDS - SEC ))"
  fi
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
  sudo rsync -rv --checksum --ignore-times --info=progress2 --stats --human-readable /share/ .
  sudo chown -R mersdk:mersdk .
}

code_coverage() {
  alias mb2='mb2 --target SailfishOS-$RELEASE-$ARCH'
  download_backup_from_aws
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
	set_envs
}

sfdk_put_to_bin() {
  mkdir -p ~/bin

  echo '#!/bin/sh
exec ~/SailfishOS/bin/sfdk "$@"' > ~/bin/sfdk
  chmod +x ~/bin/sfdk
}

ssh_copy_id_on_sailfish_device() {
  SAILFISH_IP=$(echo "$SSH_CLIENT" | awk '{ print $1}')
  set_up_instance_host_to_known_hosts "$SAILFISH_IP"
  ssh-copy-id -i "${SSH_ID_RSA_PUB}" nemo@"${SAILFISH_IP}"
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

git_submodule_init() {
	URL=$(git config --file .gitmodules --get-regexp url | grep "${1}" | awk '{ print $2 }' | tr ' ' '\n')
	git submodule add "${URL}" "${1}"
}

git_submodule_checkout() {
  for folder_name in $(git config --file .gitmodules --get-regexp path | awk '{ print $2 }' | tr ' ' '\n'); do
    if [[ ! -d "${folder_name}" ]]; then
      git_submodule_init "${folder_name}"
    elif [[ ! -d "${folder_name}/.git" ]]; then
      git submodule update --init "${folder_name}"
    fi
  done

  git submodule foreach -q --recursive 'git checkout $(git config -f $toplevel/.gitmodules submodule.$name.tag || echo master)'
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
  echo "${CR_PAT}" | docker login ghcr.io -u spiritEcosse --password-stdin
}

docker_push() {
  if [[ -z ${RELEASE+x} ]]; then
    RELEASE="latest"
  fi

  docker push ghcr.io/spiritecosse/bible-sailfishos-"${ARCH}":"${RELEASE}"
}

docker_build() {
  if [[ -z ${RELEASE+x} ]]; then
    RELEASE="latest"
  fi

  docker build -t ghcr.io/spiritecosse/bible-sailfishos-"${ARCH}":"${RELEASE}" --build-arg ARCH="${ARCH}" --build-arg RELEASE="${RELEASE}" .
}

docker_login_build_push() {
  docker_login
  docker_build
  docker_push
}

main() {
  prepare_user_mersdk
  [ "$(whoami)" = "mersdk" ]
  create_spec_dirs &
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

for func in $(echo "${funcs}" | tr ";" "\n")
do
  "${func}"
done
