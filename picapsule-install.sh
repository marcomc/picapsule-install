#!/usr/bin/env bash

set -euo pipefail

DEBUG=false
logged_user=$(logname)
device="sda1"
hdd_name="picapsule"
mount_point="/media/picapsule/${hdd_name}"

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

    local fstab_entry
    fstab_entry="/dev/${device} ${mount_point} exfat defaults,uid=$(id -u picapsule),gid=$(id -g picapsule),umask=002 0 0"
    if grep -q "/dev/${device}" /etc/fstab; then
        sudo sed -i "\|/dev/${device}|c\\${fstab_entry}" /etc/fstab
        log_debug "Updated existing fstab entry for device ${device}"
    else
        echo "${fstab_entry}" | sudo tee -a /etc/fstab
        log_debug "Added new fstab entry for device ${device}"
    fi

}

mount_device() {
    log_debug "Mounting device using fstab configuration at ${mount_point}"

    if mountpoint -q "${mount_point}"; then
        log_debug "Device is already mounted at ${mount_point}, unmounting first"
        sudo umount "${mount_point}"
    fi

    if [[ ! -d "${mount_point}" ]]; then
        log_debug "Creating mount point directory at ${mount_point}"
        sudo mkdir -p "${mount_point}"
    else
        log_debug "Mount point directory already exists at ${mount_point}"
    fi


    sudo chown "picapsule:picapsule" "${mount_point}"
    sudo chmod 775 "${mount_point}"

    log_debug "Reloading systemd daemon"
    sudo systemctl daemon-reload

}

configure_netatalk() {
    log_debug "Configuring netatalk with HDD name ${hdd_name} and user picapsule"

    local afp_conf_content="[PiCapsule]
path = /media/picapsule/${hdd_name}
time machine = yes
valid users = @picapsule
unix priv = no
file perm = 0775
directory perm = 0775"

    if grep -q "[PiCapsule]" /etc/netatalk/afp.conf; then
        sudo sed -i "/\[PiCapsule\]/,/^\s*\[/{//!d;}" /etc/netatalk/afp.conf
        sudo sed -i "/\[PiCapsule\]/r /dev/stdin" /etc/netatalk/afp.conf <<< "${afp_conf_content}"
        log_debug "Updated existing netatalk configuration for PiCapsule"
    else
        echo "${afp_conf_content}" | sudo tee -a /etc/netatalk/afp.conf
        log_debug "Added new netatalk configuration for PiCapsule"
    fi
}

enable_restart_script() {
    log_debug "Creating restart-netatalk.service file"

    local service_content="[Unit]
Description=Restart Netatalk Service
After=multi-user.target

[Service]
Type=idle
ExecStart=/bin/bash -c \"sleep 10; echo 'restart netatalk service'; sudo service netatalk restart\"

[Install]
WantedBy=multi-user.target"

    echo "${service_content}" | sudo tee /etc/systemd/system/restart-netatalk.service
    sudo systemctl enable restart-netatalk.service --now
    sudo systemctl daemon-reload
    log_debug "Enabled and started restart-netatalk.service"

    if sudo systemctl is-active --quiet restart-netatalk.service; then
        log_debug "restart-netatalk.service is already running, restarting it"
        sudo systemctl restart restart-netatalk.service
    else
        log_debug "restart-netatalk.service is not running, starting it"
        sudo systemctl start restart-netatalk.service
    fi
    log_debug "Confirming if restart-netatalk.service is restarting the netatalk service"
    if ! sudo systemctl is-active --quiet restart-netatalk.service; then
        log_debug "restart-netatalk.service is not active, waiting for it to start"
        sleep 10
    fi
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

create_user() {
    log_debug "Checking if user 'picapsule' exists"
    if ! id -u picapsule &>/dev/null; then
        log_debug "Creating user 'picapsule' with password 'changeme'"
        sudo useradd -m picapsule
        echo "picapsule:changeme" | sudo chpasswd
    else
        log_debug "User 'picapsule' already exists"
    fi

    log_debug "Adding logged user '${logged_user}' to 'picapsule' group"
    sudo usermod -aG picapsule "${logged_user}"
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
                mount_point="/media/picapsule/${hdd_name}"
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

    create_user
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