# PiCapsule TimeMachine Capsule for RPi Setup Script

This README file explains what the `picapsule-install.sh` script does and how to use it.

## Pre-requisites

Before running the script, update your system dependencies using the following commands:

```sh
sudo apt-get update
sudo apt-get upgrade -y
```

## Download and Execute Script

To download and execute the `picapsule-install.sh` script directly from GitHub, use the following command:

```sh
curl -o picapsule-install.sh https://raw.githubusercontent.com/marcomc/picapsule-install/main/picapsule-install.sh
chmod +x picapsule-install.sh
sudo ./picapsule-install.sh
```

## Options

- `-h, --help`: Show the help message and exit.
- `--debug`: Enable debug mode.
- `--device`: Specify the device to format (default: `sda1`).
- `--hdd-name`: Specify the HDD name (default: `picapsule`).

## Example

To run the script with a specific device and HDD name:

```sh
sudo ./picapsule-install.sh [--device sda1] [--hdd-name my_drive]
```

> Note: The parameters `--device` and `--hdd-name` are optional. If not specified, the script will use the default values.

## Detailed Steps

1. **Check Device**  
    The script checks if the specified device is recognized by the operating system. If the device is not recognized, the script exits with an error.

2. **Check Dependencies**  
    The script checks for the following dependencies: `apt-get`, `mkfs.exfat`, `service`, `systemctl`, `ps`, `df`, and `mount`. If any of these dependencies are missing, the script exits with an error.

3. **Update Dependencies**  
    The script updates the system dependencies using `sudo apt-get update` and `sudo apt-get upgrade -y`.

4. **Install Utilities**  
    The script installs the necessary utilities for exFAT support and Netatalk using `sudo apt-get install -y exfat-fuse exfat-utils netatalk`.

5. **Format HDD with exFAT**  
    The script formats the specified HDD with exFAT using `sudo mkfs.exfat /dev/<device>`.

6. **Configure Netatalk**  
    The script configures Netatalk to use the specified HDD for Time Machine backups. It creates the `/etc/netatalk/afp.conf` file with the appropriate configuration.

7. **Enable Restart Script**  
    The script creates and enables a systemd service to restart Netatalk after boot. The service file is created at `/etc/systemd/system/restart-netatalk.service` and is enabled using `sudo systemctl enable restart-netatalk.service --now` and `sudo systemctl daemon-reload`. The script also confirms if `restart-netatalk.service` is restarting the Netatalk service.

## Post-Install Steps

1. **Reboot Raspberry Pi**  
    Manually reboot the Raspberry Pi using the following command:
    ```sh
    sudo reboot
    ```

2. **Test Service and Drive Mount**  
    After the reboot, manually test the Netatalk service and drive mount using the following commands:
    ```sh
    pgrep netatalk
    df /<hdd_name>
    mount | grep /<hdd_name>
    ```

## Notes

- Ensure you have the necessary permissions to run the script and perform the required operations.
- The script assumes the default user is the one returned by the `logname` command.
- The script requires a reboot to complete the setup process.

## Credits

This work was inspired by [rafaelmaeuer/timecapsule-pi](https://github.com/rafaelmaeuer/timecapsule-pi).