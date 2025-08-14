#!/bin/bash
# Ensure /etc/hosts has the correct hostname for sudo
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
  echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi
#!/bin/bash
set -e


# Install required packages
apt-get update -y
apt-get install -y lvm2 curl jq

# Install K3s (single node, with default storage)
curl -sfL https://get.k3s.io | sh -

set -e
# Move udev rule and script to correct locations
mv /tmp/99-auto-lvm.rules /etc/udev/rules.d/99-auto-lvm.rules
mv /tmp/auto-lvm-add.sh /usr/local/bin/auto-lvm-add.sh
chmod +x /usr/local/bin/auto-lvm-add.sh

# Add logging to the script if not already present
if ! grep -q 'auto-lvm-add.log' /usr/local/bin/auto-lvm-add.sh; then
  sed -i '2i exec >> /var/log/auto-lvm-add.log 2>&1\nset -x' /usr/local/bin/auto-lvm-add.sh
fi

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

# Initial scan for existing disks (besides root)
for DEV in $(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | grep -v nvme0n1 | grep -v xvda); do
  /usr/local/bin/auto-lvm-add.sh $DEV
  sleep 1
  udevadm settle
  sleep 1
done

# Install and enable systemd mount service for /mnt/data
cat <<EOF > /etc/systemd/system/mnt-data-mount.service
[Unit]
Description=Ensure /mnt/data is mounted after disk/LVM changes
After=local-fs.target
Requires=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/mount /mnt/data

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now mnt-data-mount.service
