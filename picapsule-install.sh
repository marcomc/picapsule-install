#!/usr/bin/env bash

set -euo pipefail

DEBUG=false
logged_user=$(logname)
device="sda1"
hdd_name="picapsule"
mount_point="/media/${logged_user}/${hdd_name}"
user_uid=$(id -u "${logged_user}")
user_gid=$(id -g "${logged_user}")

print_usage() {
    echo "Usage: $0 [-h|--help] [--debug] [--device <device>] [--hdd-name <hdd_name>] [--uninstall]"
    echo "Options:"
    echo "  -h, --help    Show this help message and exit"
    echo "  --debug       Enable debug mode"
    echo "  --device      Specify the device to format (default: sda1)"
    echo "  --hdd-name    Specify the HDD name (default: picapsule)"
    echo "  --uninstall   Uninstall and remove all configurations"
}

log_debug() {
    local message="$1"
    if [[ "${DEBUG}" == "true" ]]; then
        echo "DEBUG: ${message}" >&2
    fi
}

check_device() {
    log_debug "Checking if device ${device} is recognized by the operating system"
    if [[ ! -b "/dev/${device}" ]]; then
        echo "Error: Device /dev/${device} is not recognized by the operating system." >&2
        exit 1
    fi
}

check_dependencies() {
    local dependencies=("apt-get" "service" "systemctl" "ps" "df" "mount")
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "Error: ${dep} is not installed." >&2
            exit 1
        fi
    done
}

install_utilities() {
    log_debug "Installing required utilities"
    if ! dpkg -s exfat-fuse exfat-utils netatalk &> /dev/null; then
        sudo apt-get install -y exfat-fuse exfat-utils netatalk
    else
        log_debug "Required utilities are already installed"
    fi
}

format_hdd_exfat() {
    log_debug "Formatting HDD with exFAT on ${device}"
    if ! sudo blkid "/dev/${device}" | grep -q exfat; then
        sudo mkfs.exfat "/dev/${device}"
    else
        log_debug "HDD is already formatted with exFAT"
    fi
}

configure_automount() {
    log_debug "Configuring automount for device ${device} at ${mount_point}"

    if ! grep -q "/dev/${device}" /etc/fstab; then
        sudo mkdir -p "${mount_point}"
        sudo chown "${logged_user}:${logged_user}" "${mount_point}"
        echo "/dev/${device} ${mount_point} exfat defaults,uid=${user_uid},gid=${user_gid} 0 0" | sudo tee -a /etc/fstab
    else
        log_debug "Device ${device} is already configured in /etc/fstab"
    fi
}

mount_device() {
    log_debug "Mounting device using fstab configuration at ${mount_point}"

    if ! mountpoint -q "${mount_point}"; then
        sudo mount "${mount_point}"
    else
        log_debug "Device is already mounted at ${mount_point}"
    fi
}

configure_netatalk() {
    log_debug "Configuring netatalk with HDD name ${hdd_name} and default user ${logged_user}"
    if ! grep -q "[PiCapsule]" /etc/netatalk/afp.conf; then
        sudo bash -c "cat > /etc/netatalk/afp.conf <<EOF
[PiCapsule]
path = /media/${logged_user}/${hdd_name}
time machine = yes
valid users = @users 
unix priv = no
EOF"
    else
        log_debug "Netatalk is already configured"
    fi
}

enable_restart_script() {
    log_debug "Creating restart-netatalk.service file"
    if ! sudo systemctl is-enabled restart-netatalk.service &> /dev/null; then
        sudo bash -c 'cat > /etc/systemd/system/restart-netatalk.service <<EOF
[Unit]
Description=Restart Netatalk Service
After=multi-user.target

[Service]
Type=idle
ExecStart=/bin/bash -c "sleep 10; echo \"restart netatalk service\"; sudo service netatalk restart"

[Install]
WantedBy=multi-user.target
EOF'
        sudo systemctl enable restart-netatalk.service --now
        sudo systemctl daemon-reload
    else
        log_debug "restart-netatalk.service is already enabled"
    fi

    log_debug "Confirming if restart-netatalk.service is restarting the netatalk service"
    sudo systemctl status restart-netatalk.service
}

uninstall() {
    log_debug "Disabling and removing restart-netatalk.service"
    if sudo systemctl is-enabled restart-netatalk.service &> /dev/null; then
        sudo systemctl disable restart-netatalk.service --now
        sudo rm /etc/systemd/system/restart-netatalk.service
        sudo systemctl daemon-reload
    else
        log_debug "restart-netatalk.service is not enabled"
    fi

    log_debug "Removing netatalk configuration"
    if grep -q "[PiCapsule]" /etc/netatalk/afp.conf; then
        sudo sed -i '/\[PiCapsule\]/,/^$/d' /etc/netatalk/afp.conf
    else
        log_debug "Netatalk configuration for PiCapsule not found"
    fi

    log_debug "Uninstalling utilities"
    sudo apt-get remove --purge -y exfat-fuse exfat-utils netatalk
}

main() {
    local uninstall_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            --debug)
                DEBUG=true
                ;;
            --device)
                shift
                device="$1"
                ;;
            --hdd-name)
                shift
                hdd_name="$1"
                mount_point="/media/${logged_user}/${hdd_name}"
                ;;
            --uninstall)
                uninstall_mode=true
                ;;
            *)
                echo "Unknown option: $1" >&2
                print_usage
                exit 1
                ;;
        esac
        shift
    done

    if [[ "${uninstall_mode}" == "true" ]]; then
        uninstall
        exit 0
    fi

    check_device
    check_dependencies
    install_utilities
    format_hdd_exfat
    configure_automount
    mount_device
    configure_netatalk
    enable_restart_script
    
}

main "$@"