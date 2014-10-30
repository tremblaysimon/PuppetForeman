#!/bin/bash
# Puppet Master Install with The Foreman on Debian variants
# Revised by: Claude Durocher
# <https://github.com/clauded>
# Version 1.5.0
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
  echo -e "  foreman_version : 1.4, 1.5, etc"
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
  IP=`hostname -I`
  Hostname=`hostname`
  FQDN=`hostname -f`
  echo -e "127.0.0.1 localhost localhosts.localdomain $FQDN\n$IP $FQDN $Hostname puppet" > /etc/hosts
}
function installApache()
{
  # Installs Apache
  echo && echo -e '\e[01;34m+++ Installing Apache...\e[0m'
  apt-get install apache2 -y
  # fix utf8 encoding in apache2
  #sed -i 's/export LANG=C/export LANG=C.UTF-8/' /etc/apache2/envvars
  echo -e '\e[01;37;42mThe Apache has been installed!\e[0m'
}
function puppetRepos()
{
  # Gets the latest puppet repos
  distribution=$1
  echo && echo -e '\e[01;34m+++ Getting Puppet repositories for $distribution...\e[0m'
  wget http://apt.puppetlabs.com/puppetlabs-release-$distribution.deb
  dpkg -i puppetlabs-release-$distribution.deb
  apt-get update
  echo -e '\e[01;37;42mThe Latest Puppet Repos have been added!\e[0m'
}
function installPuppet()
{
  # Installs puppetmaster
  echo && echo -e '\e[01;34m+++ Installing Puppet Master...\e[0m'
  apt-get install puppetmaster -y
  echo -e '\e[01;37;42mThe Puppet Master has been installed!\e[0m'
}
function enablePuppet()
{
  # Enables the puppetmaster service to be set to ensure it is running
  echo && echo -e '\e[01;34m+++ Enabling Puppet Master Service...\e[0m'
  puppet resource service puppetmaster ensure=running enable=true
  echo -e '\e[01;37;42mThe Puppet Master Service has been initiated!\e[0m'
}
function installr10k()
{
  echo && echo -e '\e[01;34m+++ Installing r10k...\e[0m'
  gem install r10k
  echo -e '\e[01;37;42mr10k has been installed!\e[0m'

  echo && echo -e '\e[01;34m+++ Configuring r10k...\e[0m'

  cp ./r10k.yaml /etc/r10k.yaml

  defaultRepo=$(sed -n '/^\s*remote\s*:\s*\(.*\)$/s//\1/p' ./r10k.yaml)
  read -p "Enter r10k Puppetfile repository [$defaultRepo]: " userRepo
  userRepo=${userRepo:-$defaultRepo}
  echo "r10k Puppetfile repository is $userRepo"
  sed -i 's#^\(\s*remote\s*:\s*\).*$#\1'$userRepo'#' /etc/r10k.yaml

  echo && echo -e '\e[01;37;42mr10k.yaml file is by default in /etc\e[0m'
  echo -e '\e[01;37;42mr10k has been configured!\e[0m'
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
  foreman-installer -i -v
  # Sets foreman and foreman-proxy services to start on boot
  sed -i 's/START=no/START=yes/g' /etc/default/foreman
  echo "START=yes" >> /etc/default/foreman-proxy
  # Sets it so you the puppetmaster and puppet services starts on boot
  sed -i 's/START=no/START=yes/g' /etc/default/puppet
  # Restarts the foreman and foreman-proxy services
  service foreman restart
  service foreman-proxy restart
  echo -e '\e[01;37;42mThe Foreman has been installed!\e[0m'
  # Restarts the apache2 service
  echo && echo -e '\e[01;34m+++ Restarting the apache2 service...\e[0m'
  service apache2 restart
  echo -e '\e[01;37;42mThe apache2 service has been restarted!\e[0m'
}
function installGit()
{
  # Installs Git
  echo && echo -e '\e[01;34m+++ Installing Git...\e[0m'
  apt-get install git -y
  echo -e '\e[01;37;42mGit has been installed (Puppet repos is in /opt/git)!\e[0m'
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
  askQuestion "Install Apache" $yes_switch
  if [ "$yesno" = "y" ]; then
    installApache
  fi
  askQuestion "Add Latest Puppet Repos ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    puppetRepos $distribution
  fi
  askQuestion "Install Puppet Master ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    installPuppet
  fi
  askQuestion "Enable Puppet Master Service ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    enablePuppet
  fi
  askQuestion "Install Git ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    installGit
  fi
  askQuestion "Install r10k ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    installr10k
  fi
  askQuestion "Add Foreman Repos ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    foremanRepos $distribution $foreman_version
  fi
  askQuestion "Install The Foreman ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    installForeman
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
