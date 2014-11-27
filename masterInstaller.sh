#!/bin/bash
# Puppet Master Install with The Foreman on Debian variants
# Revised by: Claude Durocher
# <https://github.com/clauded>
# Version 1.6.0
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
  
  # Create /etc/r10k.yaml file.
  cat << EOZ > /etc/r10k.yaml
:cachedir: /var/cache/r10k
:sources:
  puppet:
    basedir: /etc/puppet/environments
    prefix: false
    remote: https://your.remote.depot/repo-name.git

:purgedirs:
  - /etc/puppet/environments
EOZ

  # User must enter a repository or press enter with nothing to continue.
  defaultRepo=$(sed -n '/^\s*remote\s*:\s*\(.*\)$/s//\1/p' /etc/r10k.yaml)
  read -p "Enter r10k Puppetfile repository [$defaultRepo]: " userRepo
  userRepo=${userRepo:-$defaultRepo}
  echo "r10k Puppetfile repository is $userRepo"
  sed -i 's#^\(\s*remote\s*:\s*\).*$#\1'$userRepo'#' /etc/r10k.yaml

  echo && echo -e '\e[01;37;42mr10k.yaml file is by default in /etc\e[0m'
  echo -e '\e[01;37;42mr10k has been configured!\e[0m'
}
function installReaktor()
{
  echo && echo -e '\e[01;34m+++ Installing Reaktor...\e[0m'

  # Install Reaktor requirements.
  apt-get install bundler redis-server -y  

  # Use UpStart for redis-server instead of old SystemV.
  update-rc.d redis-server disable
 
  rm -f /etc/init/redis-server.conf
  cat << EOZ > /etc/init/redis-server.conf
description "redis server"

start on runlevel [23]
stop on shutdown

exec sudo -u redis /usr/bin/redis-server /etc/redis/redis.conf

respawn
EOZ

  # Use reaktor as a username/group to run Reaktor processes.
  user="reaktor"
  group=$user
  groupadd $group
  useradd $user -s /bin/bash -m -g $group -G sudo

  homedir="$(getent passwd $user | awk -F ':' '{print $6}')"
  
  # Install Reaktor from GitHub repository (enforcing 1.0.2 version for now).
  rm -rf /opt/reaktor
  cd /opt
  git clone git://github.com/pzim/reaktor
  cd /opt/reaktor
  git checkout 1.0.2 
  
  # Change access right in favor of selected user that will run the process.
  chown -R $user:$group /opt/reaktor 
  
  # Remove useless notifier plugin to avoid log error.
  rm -f /opt/reaktor/lib/reaktor/notification/active_notifiers/hipchat.rb

  # Install Reaktor Ruby requirements
  bundle install

  # Get R10K Puppetfile git repository from R10K config file.
  defaultGitRepo=$(sed -n '/^\s*remote\s*:\s*\(.*\)$/s//\1/p' /etc/r10k.yaml)
 
  # Export Reaktor environment variables.
  echo 'export RACK_ROOT="/opt/reaktor"' >> /etc/environment
  echo "export PUPPETFILE_GIT_URL=\"$defaultGitRepo\"" >> /etc/environment
  echo 'export REAKTOR_PUPPET_MASTERS_FILE="/opt/reaktor/masters.txt"' >> /etc/environment
  source $homedir/.profile

  # Currently that script supports only one puppet master in the masters txt file.
  rm -f /opt/reaktor/masters.txt
  defaultPuppetMaster="puppet"
  read -p "Enter Puppet Master server hostname [$defaultPuppetMaster]: " userPuppetMaster
  userPuppetMaster=${userPuppetMaster:-$defaultPuppetMaster}
  echo "$userPuppetMaster" >> /opt/reaktor/masters.txt

  # Generate a new ssh key to be able to use capistrano properly. 
  # Mandatory if Reaktor is on the same machine that runs Puppet Master.  
  mkdir $homedir/.ssh
  cd $homedir/.ssh

  ssh-keygen -t rsa -N "" -f id_rsa
  echo "" >> authorized_keys
  cat id_rsa.pub >> authorized_keys

  # Ask for username and password to access puppetfile git repo. Store them in .netrc file
  defaultGitUsername="username"
  read -p "Enter R10K Puppetfile git repository username [$defaultGitUsername]: " userGitUsername
  userGitUsername=${userGitUsername:-$defaultGitUsername}

  defaultGitPassword="password"
  read -p "Enter R10K Puppetfile git repository password [$defaultGitPassword]: " userGitPassword
  userGitPassword=${userGitPassword:-$defaultGitPassword}
 
  # Assume empty .netrc
  rm -f $homedir/.netrc
  touch $homedir/.netrc
 
  defaultGitRepoFQDN=$(echo $defaultGitRepo | awk -F/ '{print $3}')

  echo "machine $defaultGitRepoFQDN" >> $homedir/.netrc
  echo "login $userGitUsername" >> $homedir/.netrc
  echo "password $userGitPassword" >> $homedir/.netrc

  # Set the IP Address in Reaktor config file.
  hostIP=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')  
  sed -i 's#^\(\s*address\s*:\s*\).*$#\1'$hostIP'#' /opt/reaktor/reaktor-cfg.yml

  # Create a upstart job to be sure that service is always running.
  rm -f /etc/init/reaktor.conf
  cat << EOZ > /etc/init/reaktor.conf
start on started redis-server
stop on starting rcS

chdir /opt/reaktor/
setuid $user
setgid $user
env HOME=$homedir
env USER=$user
script
  . /etc/environment 
  /usr/local/bin/rake start
end script
EOZ

  # Ask for user realname and email for gituser.
  defaultGitRealname="Real Name"
  read -p "Enter R10K Puppetfile git repository user realname [$defaultGitRealname]: " userGitRealname
  userGitRealname=${userGitRealname:-$defaultGitRealname}

  defaultGitMail="example@example.com"
  read -p "Enter R10K Puppetfile git repository user e-mail [$defaultGitMail]: " userGitMail
  userGitMail=${userGitMail:-$defaultGitMail}

  cat << EOZ > $homedir/.gitconfig
[user]
	email = $userGitMail
	name = $userGitRealname
EOZ

  # Modify reaktor Capfile to support ssh.
  sed -i "1s/^/set \:user\, \"$user\"\n/" /opt/reaktor/Capfile
  sed -i "1s@^@ssh_options\[\:keys\] \= \[\"$homedir\"\]\n@" /opt/reaktor/Capfile

  # Modify reaktor Capfile to add sudo before r10k command.
  sed -i 's/r10k deploy/sudo r10k deploy/' /opt/reaktor/Capfile

  chown -R $user:$group $homedir

  # Add a file to sudo without passwd in /etc/sudoers.d/
  cat << EOZ > /etc/sudoers.d/reaktor
# User rules for reaktor
reaktor ALL=NOPASSWD:/usr/local/bin/r10k
EOZ

  initctl start reaktor

  echo -e '\e[01;37;42mReaktor has been installed!\e[0m'
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

  # Edit /etc/puppet/puppet.conf to support dynamic environments (Foreman modify puppet.conf during installation).
  sed -i '/\[development\]/d' /etc/puppet/puppet.conf
  sed -i '/\[production\]/d' /etc/puppet/puppet.conf
  sed -i '/modulepath/d' /etc/puppet/puppet.conf
  sed -i '/config_version/d' /etc/puppet/puppet.conf

  echo '   environment = production' >> /etc/puppet/puppet.conf
  echo '   modulepath  = $confdir/environments/$environment/modules' >> /etc/puppet/puppet.conf 
}
function installGit()
{
  # Installs Git
  echo && echo -e '\e[01;34m+++ Installing Git...\e[0m'
  apt-get install git -y
  echo -e '\e[01;37;42mGit has been installed (Puppet repos is in /opt/git)!\e[0m'
}
function runR10K()
{
  # Delete /etc/puppet/environment folder
  rm -rf /etc/puppet/environment

  echo && echo -e '\e[01;34m+++ Running R10K...\e[0m'
  # Assuming reaktor user...
  su reaktor << 'EOF'
sudo r10k deploy environment -pv
EOF

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
  askQuestion "Install reaktor ?" $yes_switch
  if [ "$yesno" = "y" ]; then
    installReaktor
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
