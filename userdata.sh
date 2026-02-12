#!/bin/bash
exec > /var/log/user-data.log 2>&1

/usr/bin/echo "--- HOST SCRIPT STARTING ---"
/usr/bin/date

# 1. RAID SETUP
/usr/bin/yum install -y mdadm

ROOT_DISK=$(/usr/bin/lsblk -no PKNAME $(/usr/bin/findmnt -n / | /usr/bin/awk '{print $2}'))
for i in {1..30}; do
  SSD_DISKS=$(/usr/bin/lsblk -dno NAME | /usr/bin/grep nvme | /usr/bin/grep -v "$ROOT_DISK")
  [ -n "$SSD_DISKS" ] && break
  /usr/bin/sleep 2
done

if [ -n "$SSD_DISKS" ]; then
    DEVICES=$(/usr/bin/echo "$SSD_DISKS" | /usr/bin/sed 's|^|/dev/|' | /usr/bin/tr '\n' ' ')
    DISK_COUNT=$(/usr/bin/echo "$SSD_DISKS" | /usr/bin/wc -w)
    
    /usr/sbin/mdadm --create --verbose /dev/md0 --level=0 --name=scratch --raid-devices=$DISK_COUNT $DEVICES
    /usr/sbin/mkfs.xfs -f /dev/md0
    
    /usr/bin/mkdir -p /mnt/odm_data
    /usr/bin/mount /dev/md0 /mnt/odm_data
    /usr/bin/chmod 777 /mnt/odm_data
    
    # Swap
    /usr/bin/fallocate -l 128G /mnt/odm_data/swapfile
    /usr/bin/chmod 600 /mnt/odm_data/swapfile
    /usr/sbin/mkswap /mnt/odm_data/swapfile
    /usr/sbin/swapon /mnt/odm_data/swapfile

    /usr/bin/echo "Configuring Docker..."

    # 2. STOP SERVICES (Clean Order)
    /usr/bin/systemctl stop ecs
    /usr/bin/sleep 10
    /usr/bin/systemctl stop docker.socket
    /usr/bin/systemctl stop docker
    
    # 3. MOVE DOCKER TO NVMe
    /usr/bin/mkdir -p /mnt/odm_data/docker
    /usr/bin/echo 'OPTIONS="--default-ulimit nofile=1024:4096 --data-root=/mnt/odm_data/docker"' > /etc/sysconfig/docker
    
    # 4. WIPE ECS STATE
    /usr/bin/rm -rf /var/lib/ecs/data/*
    
    # 5. START SERVICES
    /usr/bin/systemctl start docker
    /usr/bin/systemctl start ecs --no-block
    
    # 6. SIGNAL READY
    /usr/bin/echo "READY" > /mnt/odm_data/host_ready.txt
    /usr/bin/echo "--- HOST SETUP COMPLETE ---"
else
    /usr/bin/echo "ERROR: NO DISKS FOUND" > /var/log/nvme_error.txt
fi