#!/bin/bash
# Puppet Master Install with The Foreman on Debian variants
# Revised by: Claude Durocher
# <https://github.com/clauded>
# Version 1.8.0
#
# Fork from this source:
#  Author: John McCarthy
#  <http://www.midactstech.blogspot.com> <https://www.github.com/Midacts>
#  Date: 18th of June, 2014
#  Version 1.3
#
######## FUNCTIONS ########
#
function usage()
{
  echo -e "\nUsage:\n$0 distribution foreman_version [-y] \n"
  echo -e "  distribution : wheeezy, trusty, etc"
  echo -e "  foreman_version : 1.8, 1.9, etc"
  echo -e "  -y : don't ask for confirmation"
}
function askQuestion()
{
  # ask yes/no question : answer stored in $yesno var
  question=$1
  yes_switch=$2
  yesno="n"
  if [ "$yes_switch" = "-y" ]; then
    yesno=y
  else
    echo && echo -e "\e[33m=== $question (y/n)\e[0m"
    read yesno
  fi
}
function setHostname()
{
  # Edits the /etc/hosts file
  IP=$(hostname -I)
  Hostname=$(hostname)
  DN=$(sed -n '/^search \(.*\)$/s//\1/p' /etc/resolv.conf)
  FQDN=$Hostname.$DN
  echo -e "127.0.0.1 localhost\n$IP $FQDN $Hostname puppet" > /etc/hosts
}

function installr10k()
{
  echo && echo -e '\e[01;34m+++ Installing r10k...\e[0m'
  gem install r10k
  echo -e '\e[01;37;42mr10k has been installed!\e[0m'

  echo && echo -e '\e[01;34m+++ Configuring r10k...\e[0m'

  # Create r10k.yaml file
  mkdir -p /etc/puppetlabs/r10k
  cat << EOZ > /etc/puppetlabs/r10k/r10k.yaml
:cachedir: '/var/cache/r10k'
:sources:
  puppet:
    basedir: '/etc/puppet/environments'
    remote: 'git@gitlab.local:root/r10k.git'
EOZ

  # User must enter a repository or press enter with nothing to continue.
  defaultRepo=$(sed -n '/^\s*remote\s*:\s*\(.*\)$/s//\1/p' /etc/r10k.yaml)
  read -p "Enter r10k Puppetfile repository [$defaultRepo]: " userRepo
  userRepo=${userRepo:-$defaultRepo}
  echo "r10k Puppetfile repository is $userRepo"
  sed -i 's#^\(\s*remote\s*:\s*\).*$#\1'$userRepo'#' /etc/r10k.yaml

  echo && echo -e '\e[01;37;42mr10k.yaml file is by default in /etc\e[0m'

  # Generate a new ssh key to be able to connect to remote repository.
  defaultGitlabDns="gitlab.local"
  read -p "Enter Gitlab server fqdn [$defaultGitlabDns]: " userGitlabDns
  userGitlabDns=${userGitlabDns:-$defaultGitlabDns}
  user="root"
  group=$user
  homedir="/root"
  mkdir -p $homedir/.ssh
  cd $homedir/.ssh
  ssh-keygen -t rsa -N "" -f id_rsa
  ssh-keyscan $userGitlabDns >> known_hosts
  chown -R $user. $homedir
  chmod 600 $homedir/.ssh/*
  echo && echo -e '\e[01;37;42mSSH key for repository generated in ${homedir}/.ssh/id_rsa.pub\e[0m'
  echo -e '\e[01;37;42mr10k has been configured!\e[0m'
}
function installWebhook()
{
  # Install Gitlab's webhook service
  echo && echo -e '\e[01;34m+++ Installing Gitlab Webhook Service...\e[0m'
  curl https://raw.githubusercontent.com/clauded/PuppetForeman/master/gitlab-webhook -o '/etc/init.d/gitlab-webhook'
  chmod +x /etc/init.d/gitlab-webhook
  mkdir /var/lib/puppet/gitlab-webhook
  apt-get install -y curl
  curl https://raw.githubusercontent.com/clauded/PuppetForeman/master/gitlab-webhook-r10k.py -o '/var/lib/puppet/gitlab-webhook/gitlab-webhook-r10k.py'
  chmod +x /var/lib/puppet/gitlab-webhook/gitlab-webhook-r10k.py
  update-rc.d -f gitlab-webhook defaults
  /etc/init.d/gitlab-webhook start
  echo -e '\e[01;37;42mThe Gitlab Webhook Service listening on port 8000!\e[0m'
}
function foremanRepos()
{
  # Gets the latest foreman repos
  distribution=$1
  foreman_version=$2
  echo && echo -e '\e[01;34m+++ Getting Foreman $foreman_version repositories for $distribution...\e[0m'
  echo "deb http://deb.theforeman.org/ $distribution $foreman_version" > /etc/apt/sources.list.d/foreman.list
  echo "deb http://deb.theforeman.org/ plugins $foreman_version" >> /etc/apt/sources.list.d/foreman.list
  wget -q http://deb.theforeman.org/pubkey.gpg -O- | apt-key add -
  apt-get update
  echo -e '\e[01;37;42mThe Foreman Repos have been added!\e[0m'
}
function installForeman()
{
# Downloads the foreman-installer
  echo
  echo -e '\e[01;34m+++ Installing The Foreman...\e[0m'
  apt-get install foreman-installer -y
  echo -e '\e[01;37;42mThe Foreman Installer has been downloaded!\e[0m'
  # Starts foreman-installer
  echo && echo -e '\e[01;34mInitializing The Foreman Installer...\e[0m'
  echo "-------------------------------------"
  sleep 1
  echo -e '\e[33mMake any additional changes you would like\e[0m'
  sleep 1
  echo && echo -e '\e[97mHere\e[0m'
  sleep .5
  echo -e '\e[97mWe\e[0m'
  sleep .5
  echo -e '\e[01;97;42mG O ! ! ! !\e[0m'
  foreman-installer
  echo -e '\e[01;37;42mThe Foreman has been installed!\e[0m'
}
function installGit()
{
  # Installs Git
  echo && echo -e '\e[01;34m+++ Installing Git...\e[0m'
  apt-get install git -y
  echo -e '\e[01;37;42mGit has been installed!\e[0m'
}
function runR10K()
{
  # Delete /etc/puppet/environment folder
  rm -rf /etc/puppet/environments
  echo && echo -e '\e[01;34m+++ Running R10K...\e[0m'
  r10k deploy environment -pv
  echo -e '\e[01;37;42mR10K First Job Finished!\e[0m'
}
function doAll()
{
  distribution=$1
  foreman_version=$2
  yes_switch=$3
  askQuestion "Set Machine's Hostname for Puppet Runs ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    setHostname
  fi

  askQuestion "Install Git ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    installGit
  fi
  askQuestion "Install r10k ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    installr10k
    askQuestion "Install Gitlab webhook service for r10k ?" $yes_switch
    if [ "$yesno" = "y" ]; then
      installWebhook
    fi
  fi
  askQuestion "Add Foreman Repos ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    foremanRepos $distribution $foreman_version
  fi
  askQuestion "Install The Foreman ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    installForeman
  fi
  askQuestion "Run R10K for the first time?" $yes_switch
  if [ "$yesno" = "y" ]; then
    runR10K
  fi
  clear
  farewell=$(cat << EOZ
\e[01;37;42mYou have completed your Puppet Master and Foreman Installation! \e[0m
\e[01;39mProceed to your Foreman web UI, https://serverfqdn\e[0m
EOZ
  )
  #Calls the End of Script variable
  echo -e "$farewell" && echo && echo
  exit 0
}
#
######## MAIN ########
#
# check whether user had supplied -h or --help . If yes display usage
if [[ ( $# == "--help") ||  $# == "-h" ]]; then
  usage && exit 0
fi
# check number of arguments
if [  $# -lt 2 ]; then
  usage && exit 1
fi
# check if the script is run as root user
if [[ $USER != "root" ]]; then
  echo "This script must be run as root!" && exit 1
fi
#
distribution=$1
foreman_version=$2
yes_switch=$3
clear
echo -e "\e[01;37;42mPuppet/Foreman Master Installer on Debian derivatives\e[0m"
case "$go" in
  * )
    doAll $distribution $foreman_version $yes_switch ;;
esac
exit 0
