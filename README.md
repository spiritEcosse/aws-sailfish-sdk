# aws-sailfish-sdk

# Run
curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash

# Run specific function
apt update && apt install -y curl
curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=ssh_copy_id_on_sailfish_device

# Run download_backup
apt update && apt install -y curl
curl https://raw.githubusercontent.com/spiritEcosse/aws-sailfish-sdk/master/install.sh | bash -s -- --func=download_backup
