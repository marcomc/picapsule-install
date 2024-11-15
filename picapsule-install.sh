#!/usr/bin/env bash

set -euo pipefail

DEBUG=false

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
    local device="$1"
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

create_udev_rule() {
    log_debug "Creating udev rule for automounting USB devices"
    if ! grep -q "udisksctl mount" /etc/udev/rules.d/99-automount.rules 2>/dev/null; then
        sudo bash -c 'cat > /etc/udev/rules.d/99-automount.rules <<EOF
ACTION=="add", SUBSYSTEMS=="usb", KERNEL=="sd[a-z][0-9]", RUN+="/usr/bin/udisksctl mount -b /dev/%k"
ACTION=="remove", SUBSYSTEMS=="usb", KERNEL=="sd[a-z][0-9]", RUN+="/usr/bin/udisksctl unmount -b /dev/%k"
EOF'
        sudo udevadm control --reload-rules
        sudo udevadm trigger
    else
        log_debug "Udev rule for automounting USB devices already exists"
    fi
}

format_hdd_exfat() {
    local device="$1"
    log_debug "Formatting HDD with exFAT on ${device}"
    if ! sudo blkid "/dev/${device}" | grep -q exfat; then
        sudo mkfs.exfat "/dev/${device}"
    else
        log_debug "HDD is already formatted with exFAT"
    fi
}

configure_netatalk() {
    local hdd_name="$1"
    local logged_user
    logged_user=$(logname)
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
    local device="sda1"
    local hdd_name="picapsule"
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

    check_device "${device}"
    check_dependencies
    install_utilities
    create_udev_rule
    format_hdd_exfat "${device}"
    configure_netatalk "${hdd_name}"
    enable_restart_script
}

main "$@"