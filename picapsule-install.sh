#!/usr/bin/env bash

set -euo pipefail

DEBUG=false

print_usage() {
    echo "Usage: $0 [-h|--help] [--debug] [--device <device>] [--hdd-name <hdd_name>]"
    echo "Options:"
    echo "  -h, --help    Show this help message and exit"
    echo "  --debug       Enable debug mode"
    echo "  --device      Specify the device to format (default: sda1)"
    echo "  --hdd-name    Specify the HDD name (default: picapsule)"
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
    local dependencies=("apt-get" "mkfs.exfat" "service" "systemctl" "ps" "df" "mount")
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "Error: ${dep} is not installed." >&2
            exit 1
        fi
    done
}

update_dependencies() {
    log_debug "Updating dependencies"
    sudo apt-get update
    sudo apt-get upgrade -y
}

install_utilities() {
    log_debug "Installing required utilities"
    sudo apt-get install -y exfat-fuse exfat-utils netatalk
}

format_hdd_exfat() {
    local device="$1"
    log_debug "Formatting HDD with exFAT on ${device}"
    sudo mkfs.exfat "/dev/${device}"
}

configure_netatalk() {
    local hdd_name="$1"
    local logged_user
    logged_user=$(logname)
    log_debug "Configuring netatalk with HDD name ${hdd_name} and default user ${default_user}"
    sudo bash -c "cat > /etc/netatalk/afp.conf <<EOF
[PiCapsule]
path = /media/${logged_user}/${hdd_name}
time machine = yes
valid users = @users 
unix priv = no
EOF"
}

enable_restart_script() {
    log_debug "Creating restart-netatalk.service file"
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

    log_debug "Confirming if restart-netatalk.service is restarting the netatalk service"
    sudo systemctl status restart-netatalk.service
}

main() {
    local device="sda1"
    local hdd_name="picapsule"

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
            *)
                echo "Unknown option: $1" >&2
                print_usage
                exit 1
                ;;
        esac
        shift
    done

    check_device "${device}"
    check_dependencies
    update_dependencies
    install_utilities
    format_hdd_exfat "${device}"
    configure_netatalk "${hdd_name}"
    enable_restart_script
}

main "$@"