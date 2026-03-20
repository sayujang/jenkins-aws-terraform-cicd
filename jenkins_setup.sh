#!/bin/bash
set -e
set -x

# 1. Update and install Java
sudo apt-get update -y
sudo apt-get install openjdk-17-jdk curl -y

# 2. Download the Jenkins GPG Key and enforce read permissions
# 2. Download the Jenkins GPG Key and enforce read permissions
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
sudo chmod 644 /usr/share/keyrings/jenkins-keyring.asc

# 3. Add the Jenkins Repository (Single Line!)
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# 4. Update apt so it sees the new Jenkins repo, then install
sudo apt-get update -y
sudo apt-get install jenkins -y

# 5. Start the service
sudo systemctl enable jenkins
sudo systemctl start jenkins