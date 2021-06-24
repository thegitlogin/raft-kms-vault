#!/usr/bin/env bash
set -x
exec > >(tee /var/log/tf-user-data.log|logger -t user-data ) 2>&1

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT $0: $1"
}

logger "Running"

##--------------------------------------------------------------------
## Variables

# Get Private IP address
PRIVATE_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)

VAULT_ZIP="${tpl_vault_zip_file}"

# Detect package management system.
YUM=$(which yum 2>/dev/null)
APT_GET=$(which apt-get 2>/dev/null)

##--------------------------------------------------------------------
## Functions

user_rhel() {
  # RHEL/CentOS user setup
  sudo /usr/sbin/groupadd --force --system $${USER_GROUP}

  if ! getent passwd $${USER_NAME} >/dev/null ; then
    sudo /usr/sbin/adduser \
      --system \
      --gid $${USER_GROUP} \
      --home $${USER_HOME} \
      --no-create-home \
      --comment "$${USER_COMMENT}" \
      --shell /bin/false \
      $${USER_NAME}  >/dev/null
  fi
}

user_ubuntu() {
  # UBUNTU user setup
  if ! getent group $${USER_GROUP} >/dev/null
  then
    sudo addgroup --system $${USER_GROUP} >/dev/null
  fi

  if ! getent passwd $${USER_NAME} >/dev/null
  then
    sudo adduser \
      --system \
      --disabled-login \
      --ingroup $${USER_GROUP} \
      --home $${USER_HOME} \
      --no-create-home \
      --gecos "$${USER_COMMENT}" \
      --shell /bin/false \
      $${USER_NAME}  >/dev/null
  fi
}

##--------------------------------------------------------------------
## Install Base Prerequisites

logger "Setting timezone to UTC"
sudo timedatectl set-timezone UTC

if [[ ! -z $${YUM} ]]; then
  logger "RHEL/CentOS system detected"
  logger "Performing updates and installing prerequisites"
  sudo yum-config-manager --enable rhui-REGION-rhel-server-releases-optional
  sudo yum-config-manager --enable rhui-REGION-rhel-server-supplementary
  sudo yum-config-manager --enable rhui-REGION-rhel-server-extras
  sudo yum -y check-update
  sudo yum install -q -y wget unzip bind-utils ruby rubygems ntp jq
  sudo systemctl start ntpd.service
  sudo systemctl enable ntpd.service
elif [[ ! -z $${APT_GET} ]]; then
  logger "Debian/Ubuntu system detected"
  logger "Performing updates and installing prerequisites"
  sudo apt-get -qq -y update
  sudo apt-get install -qq -y wget unzip dnsutils ruby rubygems ntp jq
  sudo systemctl start ntp.service
  sudo systemctl enable ntp.service
  logger "Disable reverse dns lookup in SSH"
  sudo sh -c 'echo "\nUseDNS no" >> /etc/ssh/sshd_config'
  sudo service ssh restart
else
  logger "Prerequisites not installed due to OS detection failure"
  exit 1;
fi

##--------------------------------------------------------------------
## Install AWS-Specific Prerequisites

if [[ ! -z $${YUM} ]]; then
  logger "RHEL/CentOS system detected"
  logger "Performing updates and installing prerequisites"
  curl --silent -O https://bootstrap.pypa.io/get-pip.py
  sudo python get-pip.py
  sudo pip install awscli
elif [[ ! -z $${APT_GET} ]]; then
  logger "Debian/Ubuntu system detected"
  logger "Performing updates and installing prerequisites"
  sudo apt-get -qq -y update
  sudo apt-get install -qq -y awscli
else
  logger "AWS Prerequisites not installed due to OS detection failure"
  exit 1;
fi


##--------------------------------------------------------------------
## Configure Vault user

USER_NAME="vault"
USER_COMMENT="HashiCorp Vault user"
USER_GROUP="Vault"
USER_HOME="/srv/vault"

if [[ ! -z $${YUM} ]]; then
  logger "Setting up user $${USER_NAME} for RHEL/CentOS"
  user_rhel
elif [[ ! -z $${APT_GET} ]]; then
  logger "Setting up user $${USER_NAME} for Debian/Ubuntu"
  user_ubuntu
else
  logger "$${USER_NAME} user not created due to OS detection failure"
  exit 1;
fi

##--------------------------------------------------------------------
## Install Vault

logger "Downloading Vault"
curl -o /tmp/vault.zip $${VAULT_ZIP}

logger "Installing Vault"
sudo unzip -o /tmp/vault.zip -d /usr/local/bin/
sudo chmod 0755 /usr/local/bin/vault
sudo chown vault:Vault /usr/local/bin/vault
sudo mkdir -pm 0755 /etc/vault.d
sudo mkdir -pm 0755 /etc/ssl/vault

logger "/usr/local/bin/vault --version: $(/usr/local/bin/vault --version)"

logger "Configuring Vault"

sudo mkdir -pm 0755 ${tpl_vault_storage_path}
sudo chown -R vault:Vault ${tpl_vault_storage_path}
sudo chmod -R a+rwx ${tpl_vault_storage_path}

sudo tee /etc/vault.d/vault.hcl <<EOF
storage "raft" {
  path    = "${tpl_vault_storage_path}"
  node_id = "${tpl_vault_node_name}"

  retry_join {
    auto_join = "provider=aws addr_type=public_v4 tag_key=cluster_name tag_value=raft-test region=us-east-1"
    auto_join_scheme = "http"
  }
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  cluster_address     = "0.0.0.0:8201"
  tls_disable = true
}

seal "awskms" {
  region     = "${aws_region}"
  kms_key_id = "${kms_key}"
}

api_addr = "http://$${PUBLIC_IP}:8200"
cluster_addr = "http://$${PRIVATE_IP}:8201"
disable_mlock = true
ui=true
EOF

sudo chown -R vault:Vault /etc/vault.d /etc/ssl/vault
sudo chmod -R 0644 /etc/vault.d/*

sudo tee -a /etc/environment <<EOF
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
EOF

source /etc/environment

logger "Granting mlock syscall to vault binary"
sudo setcap cap_ipc_lock=+ep /usr/local/bin/vault

##--------------------------------------------------------------------
## Install Vault Systemd Service

sudo tee /etc/systemd/system/vault.service > /dev/null <<EOF
[Unit]
Description="HashiCorp Enterprise Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
[Service]
User=vault
Group=Vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity
[Install]
WantedBy=multi-user.target
EOF

sudo chmod 0664 /etc/systemd/system/vault*
sudo chown -R vault:Vault /etc/systemd/system/vault*
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl restart vault
sudo mkdir -p /tmp/vault.d
sleep 10

if [[ ! -z $${YUM} ]]; then
  SYSTEMD_DIR="/etc/systemd/system"
  logger "Installing systemd services for RHEL/CentOS"
  echo "$${VAULT_SERVICE}" | sudo tee $${SYSTEMD_DIR}/vault.service
  sudo chmod 0664 $${SYSTEMD_DIR}/vault*
elif [[ ! -z $${APT_GET} ]]; then
  SYSTEMD_DIR="/lib/systemd/system"
  logger "Installing systemd services for Debian/Ubuntu"
  echo "$${VAULT_SERVICE}" | sudo tee $${SYSTEMD_DIR}/vault.service
  sudo chmod 0664 $${SYSTEMD_DIR}/vault*
else
  logger "Service not installed due to OS detection failure"
  exit 1;
fi

sudo systemctl enable vault
sudo systemctl start vault

##-------------------------------------------------------------------
## Set up aliases to ease networking to each node
%{ for address, name in tpl_vault_node_address_names  ~}
echo "${address} ${name}" | sudo tee -a /etc/hosts
%{ endfor ~}

%{ if tpl_vault_node_name == "vault_1" }
# vault_2 adds some test data to demonstrate that the cluster is connected to
#   the same data.
sleep 5
logger "Initializing Vault and storing results for ubuntu user"
vault operator init -recovery-shares 1 -recovery-threshold 1 -format=json > /tmp/key.json
sudo chown vault:Vault /tmp/key.json

logger "Saving root_token and recovery key to ubuntu user's home"
VAULT_TOKEN=$(cat /tmp/key.json | jq -r ".root_token")
echo $VAULT_TOKEN > /home/ubuntu/root_token
sudo chown vault:Vault /home/ubuntu/root_token
echo $VAULT_TOKEN > /home/ubuntu/.vault-token
sudo chown vault:Vault /home/ubuntu/.vault-token

echo $(cat /tmp/key.json | jq -r ".recovery_keys_b64[]") > /home/ubuntu/recovery_key
sudo chown vault:Vault /home/ubuntu/recovery_key

logger "Setting VAULT_ADDR and VAULT_TOKEN"
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$VAULT_TOKEN

logger "Waiting for Vault to finish preparations (10s)"
sleep 10

sudo aws s3 cp s3://$${s3bucket}/lic_payload.json /home/ --acl bucket-owner-full-control
cd /home/
curl \
--header "X-Vault-Token: $VAULT_TOKEN" \
--request PUT \
--data @lic_payload.json \
http://127.0.0.1:8200/v1/sys/license

logger "Waiting for Vault to finish preparations (10s)"
sleep 10

logger "Enable file audit log"
sudo touch /var/log/vault_audit.log
sudo chown -R vault:Vault /var/log/
vault audit enable file file_path=/var/log/vault_audit.log
sleep 5

logger "Enabling kv-v2 secrets engine and inserting secret"
vault secrets enable -path=kv kv-v2
vault kv put kv/apikey webapp=ABB39KKPTWOR832JGNLS02


# From <https://learn.hashicorp.com/tutorials/vault/transform>

# Enable

logger "Enabling Transform Secrets Engine"
vault secrets enable transform

# From <https://learn.hashicorp.com/tutorials/vault/transform>

vault write transform/role/payments transformations=card-number

vault write transform/transformations/fpe/card-number \
template="builtin/creditcardnumber" \
tweak_source=internal \
allowed_roles=payments

vault write transform/template/ssn \
type=regex \
pattern="(\d{3})-(\d{2})-(\d{4})" \
alphabet=builtin/numeric

vault write transform/role/payments transformations=card-number,sin

vault write transform/transformations/fpe/sin \
template=ssn \
tweak_source=internal \
allowed_roles=*

vault write transform/role/payments \
transformations=card-number,sin,phone-number

vault write transform/template/phone-no-tmpl \
type=regex \
pattern="\+\d{1,2} (\d{3})-(\d{3})-(\d{4})" \
alphabet=builtin/numeric

vault write transform/transformations/masking/phone-number \
template=phone-no-tmpl \
masking_character=# \
allowed_roles=*
%{ endif }

logger "Complete"

sudo aws s3 cp s3://$${s3bucket}/nf-test5.json /home/ --acl bucket-owner-full-control
sudo aws s3 cp s3://$${s3bucket}/testing.sh /home/ --acl bucket-owner-full-control
sudo aws s3 cp s3://$${s3bucket}/testing10calls.sh /home/ --acl bucket-owner-full-control
sudo aws s3 cp s3://$${s3bucket}/testing9calls.sh /home/ --acl bucket-owner-full-control
sudo aws s3 cp s3://$${s3bucket}/testing8calls.sh /home/ --acl bucket-owner-full-control
sudo aws s3 cp s3://$${s3bucket}/testing6calls.sh /home/ --acl bucket-owner-full-control

sudo chmod +x testing.sh
sudo chmod +x testing10calls.sh
sudo chmod +x testing9calls.sh
sudo chmod +x testing8calls.sh
sudo chmod +x testing6calls.sh

sudo chown -R vault:Vault /home/testing.sh
sudo chown -R vault:Vault /home/testing10calls.sh
sudo chown -R vault:Vault /home/testing9calls.sh
sudo chown -R vault:Vault /home/testing8calls.sh
sudo chown -R vault:Vault /home/testing6calls.sh
