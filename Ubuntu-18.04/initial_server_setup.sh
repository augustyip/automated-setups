#!/bin/bash
set -euo pipefail

########################
### SCRIPT VARIABLES ###
########################

# Name of the user to create and grant sudo privileges
USERNAME=august

# Whether to copy over the root user's `authorized_keys` file to the new sudo
# user.
COPY_AUTHORIZED_KEYS_FROM_ROOT=true

# Additional public keys to add to the new sudo user
# OTHER_PUBLIC_KEYS_TO_ADD=(
#     "ssh-rsa AAAAB..."
#     "ssh-rsa AAAAB..."
# )
OTHER_PUBLIC_KEYS_TO_ADD=(
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+Th8uMauqACNRaGQkqrkEvZhDtMQmdwItB9nvE6tlWT0ORGdGVT0jeTFA+aQOGjulnNgaY4kdqOxJ0zi3movDqBzOL98WBPJaHl1QKK3EcdrpGwF3ziMIQQf5/wAQtTTtpEoLI9/5rJRF61lEpbL+/yGeC3xje3AiLBtuZ+j3dCpis9PwuivS6QEVs9XE9Sl1Okl4+tWhtx/I5i7L4CjR/GuvV1S8EeecSch7YzZoYv9Q8zQ7djs7yDVK23ahP826UozIUS41t+2QxroMaWhJ9S/d/f77xQe0eavERlzfnJJyAI5OkSaiijqNBmYQ5attF8uoD7qDDOBxhkjL6msb augustyip@PF1MBNJD"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDY34Y0p8SiyW1PNc4lf97OB904ASLpbLda3l9lLMh524ErVZxv9WHsLDto2maVXrV4LUWYEFUckz10yLaVVUVFlW7yuQ74PPT79CxaielThrmXdFR8uGz6kMBHTb8wWjUT/8nkzUL7JQRyEN4V1csAcevqPCbwoT/o6F28Aul4b9hebm7Ey2pE7dKJhGFn/0yHNB4peZBfC3tXZV/BtPjClDrZafcz97yS3NBJkeNUojg9lY2l0BGc3i/OkgtYUXQ2Ap9NntQFcjR+pYcW6hRqVud0hM0anyTPdHyfVJ3lpH6ws3VXfdudzqcN0f0BwbWmFq1PogPegOZx0FVdI8BMQUp4TmkL14F9J8P9b8ksovjP9t5sdpFs3HSHXxcOfzgdPay4k1l0YPShQDFj5BZvXthJeqf3l2N3+7vgITvd2VoFRRPlzQM8SJO7P5MREa6pCiwzcxfhiy/lCfHikMKBE8JXtW71TOKbGDjOBC7w/aaIA++UDqc9nmMMLISVNvUeBm4xqDuxg80as0ngJyUsso25689s4OZwkuTQTAmMQ/z5C/bVDDalGiOP7bojm0e6jvcLJ3TmckxNtEMcTxYDzlJhEC87EDQWi1DRz25oRRJ0jvf/oI63IwYgSQPEamUzLYK1WunoXGoFnLlCYAAkWMcUtUH6r5GrzR/7NkEqWQ== augustyip@gmail.com"
)

####################
### SCRIPT LOGIC ###
####################

# Add sudo user and grant privileges
useradd --create-home --shell "/bin/bash" --groups sudo "${USERNAME}"

# Check whether the root account has a real password set
encrypted_root_pw="$(grep root /etc/shadow | cut --delimiter=: --fields=2)"

if [ "${encrypted_root_pw}" != "*" ]; then
    # Transfer auto-generated root password to user if present
    # and lock the root account to password-based access
    echo "${USERNAME}:${encrypted_root_pw}" | chpasswd --encrypted
    passwd --lock root
else
    # Delete invalid password for user if using keys so that a new password
    # can be set without providing a previous value
    passwd --delete "${USERNAME}"
fi

# Expire the sudo user's password immediately to force a change
chage --lastday 0 "${USERNAME}"

# Create SSH directory for sudo user
home_directory="$(eval echo ~${USERNAME})"
mkdir --parents "${home_directory}/.ssh"

# Copy `authorized_keys` file from root if requested
if [ "${COPY_AUTHORIZED_KEYS_FROM_ROOT}" = true ]; then
    cp /root/.ssh/authorized_keys "${home_directory}/.ssh"
fi

# Add additional provided public keys
for pub_key in "${OTHER_PUBLIC_KEYS_TO_ADD[@]}"; do
    echo "${pub_key}" >> "${home_directory}/.ssh/authorized_keys"
done

# Adjust SSH configuration ownership and permissions
chmod 0700 "${home_directory}/.ssh"
chmod 0600 "${home_directory}/.ssh/authorized_keys"
chown --recursive "${USERNAME}":"${USERNAME}" "${home_directory}/.ssh"

# Disable root SSH login with password
sed --in-place 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
if sshd -t -q; then
    systemctl restart sshd
fi

# Add exception for SSH and then enable UFW firewall
ufw allow OpenSSH
ufw --force enable
