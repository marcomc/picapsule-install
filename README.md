# PiCapsule TimeMachine Capsule for RPi Setup Script

This README file explains what the `picapsule-install.sh` script does and how to use it.

## Options

- `-h, --help`: Show the help message and exit.
- `--debug`: Enable debug mode.
- `--device`: Specify the device to format (default: `sda1`).
- `--hdd-name`: Specify the HDD name (default: `picapsule`).

## Example

To run the script with a specific device and HDD name:

```sh
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

7. **Restart Netatalk**  
    The script restarts the Netatalk service using `sudo service netatalk restart`.

8. **Reboot Raspberry Pi**  
    The script reboots the Raspberry Pi using `sudo reboot`.

9. **Test Service and Drive Mount**  
    The script tests the Netatalk service and drive mount using `pgrep netatalk`, `df /<hdd_name>`, and `mount | grep /<hdd_name>`.

10. **Enable Restart Script**  
     The script creates and enables a systemd service to restart Netatalk after boot. The service file is created at `/etc/systemd/system/restart-netatalk.service` and is enabled using `sudo systemctl enable restart-netatalk.service --now` and `sudo systemctl daemon-reload`.

## Notes

- Ensure you have the necessary permissions to run the script and perform the required operations.
- The script assumes the default user is the one returned by the `logname` command.
- The script requires a reboot to complete the setup process.

## Credits

This work was inspired by [rafaelmaeuer/timecapsule-pi](https://github.com/rafaelmaeuer/timecapsule-pi).