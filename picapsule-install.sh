#!/usr/bin/env bash

set -euo pipefail

VERBOSE=true
logged_user=$(logname)
device="sda1"
hdd_name="picapsule"
mount_point="/media/picapsule/${hdd_name}"
picapsule_pwd="changeme"
picapsule_uid=""
picapsule_gid=""

print_usage() {
    echo "Usage: $0 [-h|--help] [-q|--quiet] [--device <device>] [--hdd-name <hdd_name>] [--uninstall]"
    echo "Options:"
    echo "  -h, --help    Show this help message and exit"
    echo "  -q, --quiet   Disable verbose mode"
    echo "  --device      Specify the device to format (default: sda1)"
    echo "  --hdd-name    Specify the HDD name (default: picapsule)"
    echo "  --uninstall   Uninstall and remove all configurations"
}

log_verbose() {
    local message="$1"
    local status="${2:-}"
    local symbol="[ ]"
    local color=""

    if [[ "${VERBOSE}" == "true" ]]; then
        if [[ "${status}" == "success" ]]; then
            symbol="[✔]"
            color="\e[32m"  # Green
        elif [[ "${status}" == "fail" ]]; then
            symbol="[✘]"
            color="\e[31m"  # Red
        fi
        echo -e "${color}${symbol} ${message}\e[0m"
    fi
}

create_picapsule_user() {
    log_verbose "Checking if user 'picapsule' exists"
    if ! id -u picapsule &>/dev/null; then
        log_verbose "Creating user 'picapsule' with password 'changeme'"
        useradd -m picapsule
        echo "picapsule:${picapsule_pwd}" | chpasswd
        log_verbose "User 'picapsule' created successfully" "success"
    else
        log_verbose "User 'picapsule' already exists" "success"
    fi

    picapsule_uid=$(id -u picapsule)
    picapsule_gid=$(id -g picapsule)

    log_verbose "Adding logged user '${logged_user}' to 'picapsule' group"
    usermod -aG picapsule "${logged_user}"
    log_verbose "User '${logged_user}' added to 'picapsule' group successfully" "success"
}

check_device() {
    log_verbose "Checking if device ${device} is recognized by the operating system"
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
    log_verbose "Installing required utilities"
    if ! dpkg -s exfat-fuse exfat-utils netatalk &> /dev/null; then
        apt-get install -y exfat-fuse exfat-utils netatalk
    else
        log_verbose "Required utilities are already installed"
    fi
}

format_hdd_exfat() {
    log_verbose "Formatting HDD with exFAT on ${device}"
    if ! blkid "/dev/${device}" | grep -q exfat; then
        mkfs.exfat "/dev/${device}"
    else
        log_verbose "HDD is already formatted with exFAT"
    fi
}

configure_automount() {
    log_verbose "Configuring automount for device ${device} at ${mount_point}"

    local fstab_entry
    fstab_entry="/dev/${device} ${mount_point} exfat defaults,uid=${picapsule_uid},gid=${picapsule_gid},umask=002 0 0"
    if grep -q "/dev/${device}" /etc/fstab; then
        sed -i "\|/dev/${device}|c\\${fstab_entry}" /etc/fstab
        log_verbose "Updated existing fstab entry for device ${device}"
    else
        echo "${fstab_entry}" | tee -a /etc/fstab
        log_verbose "Added new fstab entry for device ${device}"
    fi
}

mount_device() {
    log_verbose "Mounting device using fstab configuration at ${mount_point}"

    if mountpoint -q "${mount_point}"; then
        log_verbose "Device is already mounted at ${mount_point}, unmounting first"
        umount "${mount_point}"
    fi

    if [[ ! -d "${mount_point}" ]]; then
        log_verbose "Creating mount point directory at ${mount_point}"
        mkdir -p "${mount_point}"
    else
        log_verbose "Mount point directory already exists at ${mount_point}"
    fi

    chown "picapsule:picapsule" "${mount_point}"
    chmod 775 "${mount_point}"

    log_verbose "Reloading systemd daemon"
    systemctl daemon-reload
    
    log_verbose "Mounting device at ${mount_point}"
    mount "${mount_point}"
}

configure_netatalk() {
    log_verbose "Configuring netatalk with HDD name ${hdd_name} and user picapsule"

    local afp_conf_content="[PiCapsule]
path = /media/picapsule/${hdd_name}
time machine = yes
valid users = @picapsule
unix priv = no
file perm = 0775
directory perm = 0775"

    if grep -q "[PiCapsule]" /etc/netatalk/afp.conf; then
        sed -i "/\[PiCapsule\]/,/^\s*\[/{//!d;}" /etc/netatalk/afp.conf
        sed -i "/\[PiCapsule\]/r /dev/stdin" /etc/netatalk/afp.conf <<< "${afp_conf_content}"
        log_verbose "Updated existing netatalk configuration for PiCapsule"
    else
        echo "${afp_conf_content}" | tee -a /etc/netatalk/afp.conf
        log_verbose "Added new netatalk configuration for PiCapsule"
    fi
}

enable_restart_script() {
    log_verbose "Creating restart-netatalk.service file"

    local service_content="[Unit]
Description=Restart Netatalk Service
After=multi-user.target

[Service]
Type=idle
ExecStart=/bin/bash -c \"sleep 10; echo 'restart netatalk service'; service netatalk restart\"

[Install]
WantedBy=multi-user.target"

    echo "${service_content}" | tee /etc/systemd/system/restart-netatalk.service
    systemctl enable restart-netatalk.service --now
    systemctl daemon-reload
    log_verbose "Enabled and started restart-netatalk.service"

    if systemctl is-active --quiet restart-netatalk.service; then
        log_verbose "restart-netatalk.service is already running, restarting it"
        systemctl restart restart-netatalk.service
    else
        log_verbose "restart-netatalk.service is not running, starting it"
        systemctl start restart-netatalk.service
    fi
    log_verbose "Confirming if restart-netatalk.service is restarting the netatalk service"
    if ! systemctl is-active --quiet restart-netatalk.service; then
        log_verbose "restart-netatalk.service is not active, waiting for it to start"
        sleep 10
    fi
    systemctl status restart-netatalk.service
}

uninstall() {
    log_verbose "Disabling and removing restart-netatalk.service"
    if systemctl is-enabled restart-netatalk.service &> /dev/null; then
        systemctl disable restart-netatalk.service --now
        rm /etc/systemd/system/restart-netatalk.service
        systemctl daemon-reload
    else
        log_verbose "restart-netatalk.service is not enabled"
    fi

    log_verbose "Removing netatalk configuration"
    if grep -q "[PiCapsule]" /etc/netatalk/afp.conf; then
        sed -i '/\[PiCapsule\]/,/^$/d' /etc/netatalk/afp.conf
    else
        log_verbose "Netatalk configuration for PiCapsule not found"
    fi

    log_verbose "Uninstalling utilities"
    apt-get remove --purge -y exfat-fuse exfat-utils netatalk

    log_verbose "Removing mount point directory at ${mount_point}"
    if mountpoint -q "${mount_point}"; then
        umount "${mount_point}"
    fi
    rm -rf "${mount_point}"

    log_verbose "Removing user 'picapsule'"
    if id -u picapsule &>/dev/null; then
        userdel -r picapsule
    else
        log_verbose "User 'picapsule' does not exist"
    fi
}

main() {
    local uninstall_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -q|--quiet)
                VERBOSE=false
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
        log_verbose "Uninstallation completed successfully" "success"
        exit 0
    fi

    create_picapsule_user
    check_device
    check_dependencies
    install_utilities
    format_hdd_exfat
    configure_automount
    mount_device
    configure_netatalk
    enable_restart_script

    log_verbose "Installation completed successfully" "success"
}

main "$@"