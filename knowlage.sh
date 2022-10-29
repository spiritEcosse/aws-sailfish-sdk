# is not used

sfdk_deploy_to_device() {
  prepare_aws_instance
  rsync_from_host_to_sever
  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
    export ARCH=${ARCH}
    export PLATFORM=${PLATFORM}
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func='sfdk_device_list;sfdk_tools_list;sfdk_config_device_sony;sfdk_config_target_sony;sfdk_build_deploy;sfdk_device_exec_app'
  "
}

sailfish_run_tests_on_aws() {
    prepare_aws_instance
    rsync_from_host_to_sever
    ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
      export ARCH=${ARCH}
      export PLATFORM=${PLATFORM}
      curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func='sfdk_tools_list;sfdk_config_target_sony;sfdk_build_test'
    "
}

sfdk_run_app_on_device() {
  prepare_aws_instance
  rsync_from_host_to_sever
  ssh "${EC2_INSTANCE_USER}@${EC2_INSTANCE_HOST}" "
    export ARCH=${ARCH}
    export PLATFORM=${PLATFORM}
    curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func='sfdk_device_list;sfdk_config_device_sony;sfdk_device_exec_app'
  "
}

sfdk_build_test() {
  cd "${BUILD_FOLDER}"
  sfdk cmake -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON -DCODE_COVERAGE=ON
  sfdk make
#  sfdk build ../bible -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON -DCODE_COVERAGE=ON
  sfdk build-shell ctest --output-on-failure
}

sfdk_build_deploy() {
  cd "${BUILD_FOLDER}"
  sfdk cmake
  sfdk make
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
  sfdk config device='Xperia 10 - Dual SIM (ARM)'
}

sfdk_device_exec_app() {
  # on device: devel-su usermod -a -G systemd-journal nemo
  sfdk device exec /usr/bin/bible &
  sfdk device exec journalctl -f /usr/bin/bible
}

sfdk_download() {
  if [ ! -f "${SDK_FILE_NAME}" ]; then
    curl -O https://releases.sailfishos.org/sdk/installers/${SDK_VERSION}/${SDK_FILE_NAME}
    chmod +x ${SDK_FILE_NAME}
    log_app_msg "Download ${SDK_FILE_NAME} has completed successfully."
  else
    ls -la .
    log_app_msg "File ${SDK_FILE_NAME} already exists."
  fi
}

sfdk_reinstall() {
  # because of https://forum.sailfishos.org/t/sailfish-ide-unable-to-deploy-after-4-0-1-sdk-update/5292
  rm_sdk_settings
  rm -fr ~/SailfishOS
  docker_armaggedon
  sfdk_download
  sfdk_install
}

sfdk_install() {
  if [[ ! -d "SailfishOS" ]]; then
    rm_sdk_settings
	  QT_QPA_PLATFORM=minimal ./${SDK_FILE_NAME} --verbose non-interactive=1 accept-licenses=1 build-engine-type=docker
	else
	  log_app_msg "Folder SailfishOS already exists."
	fi
}

sfdk_put_to_bin() {
  mkdir -p ~/bin

  echo '#!/bin/sh
exec ~/SailfishOS/bin/sfdk "$@"' > ~/bin/sfdk
  chmod +x ~/bin/sfdk
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

cp_share_to_bible() {
  mkdir -p "${BIBLE_FOLDER}"
  cd "${BIBLE_FOLDER}"
  sudo cp -r /share/. .
  sudo chown -R mersdk:mersdk .
  cp -r "${BIBLE_FOLDER}"/rpm "${BUILD_FOLDER}"
}
