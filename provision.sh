#!/usr/bin/env bash

# Initialize install log
rm -f install.log
# Configure for noninteractive mode (for dpkg)
export DEBIAN_FRONTEND=noninteractive
# Prevent accessing stdin when no terminal available in root profile
sudo sed -i 's/^mesg n/tty -s \\&\\& mesg n/g' /root/.profile
sudo ex +"%s@DPkg@//DPkg" -cwq /etc/apt/apt.conf.d/70debconf
sudo dpkg-reconfigure debconf -f noninteractive -p critical

echo "Updating packages"
sudo apt-get -qq update

echo "Installing OpenJDK Java8"
sudo apt-get -y install openjdk-8-jre >> install.log

############## SQL SERVER INSTALLATION ##############

# Password for the SA user (required)
MSSQL_SA_PASSWORD='P@ssw0rd'

# Product ID of the version of SQL server you're installing
# Must be evaluation, developer, express, web, standard, enterprise, or your 25 digit product key
# Defaults to developer
MSSQL_PID='express'

# Install SQL Server Agent (recommended)
SQL_INSTALL_AGENT='y'

# Install SQL Server Full Text Search (optional)
# SQL_INSTALL_FULLTEXT='n'

# Create an additional user with sysadmin privileges (optional)
SQL_INSTALL_USER='ignition'
SQL_INSTALL_USER_PASSWORD='Ign!ti0n'

if [ -z $MSSQL_SA_PASSWORD ]
then
  echo Environment variable MSSQL_SA_PASSWORD must be set for unattended install
  exit 1
fi

echo Adding Microsoft repositories...
sudo curl -s https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
repoargs="$(curl -s https://packages.microsoft.com/config/ubuntu/16.04/mssql-server-2017.list)"
sudo add-apt-repository "${repoargs}"
repoargs="$(curl -s https://packages.microsoft.com/config/ubuntu/16.04/prod.list)"
sudo add-apt-repository "${repoargs}"

echo Installing SQL Server...
sudo apt-get -qq update && apt-get install -y mssql-server >> install.log

echo Running mssql-conf setup...
sudo MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD \
	 MSSQL_PID=$MSSQL_PID \
	 /opt/mssql/bin/mssql-conf -n setup accept-eula

echo Installing mssql-tools and unixODBC developer...
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev >> install.log

# Add SQL Server tools to the path by default:
echo Adding SQL Server tools to your path...
echo PATH="$PATH:/opt/mssql-tools/bin" >> ~/.bash_profile
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc

# Optional SQL Server Agent installation:
if [ ! -z $SQL_INSTALL_AGENT ]
then
  echo Installing SQL Server Agent...
  sudo apt-get install -y mssql-server-agent >> install.log
fi

# Optional SQL Server Full Text Search installation:
if [ ! -z $SQL_INSTALL_FULLTEXT ]
then
	echo Installing SQL Server Full-Text Search...
	sudo apt-get install -y mssql-server-fts
fi

# Configure firewall to allow TCP port 1433:
echo Configuring UFW to allow traffic on port 1433...
sudo ufw allow 1433/tcp
sudo ufw reload

# Optional example of post-installation configuration.
# Trace flags 1204 and 1222 are for deadlock tracing.
# echo Setting trace flags...
# sudo /opt/mssql/bin/mssql-conf traceflag 1204 1222 on

# Restart SQL Server after installing:
echo Restarting SQL Server...
sudo systemctl restart mssql-server

# Connect to server and get the version:
counter=1
errstatus=1
while [ $counter -le 5 ] && [ $errstatus = 1 ]
do
  echo Waiting for SQL Server to start...
  sleep 3s
  /opt/mssql-tools/bin/sqlcmd \
	-S localhost \
	-U SA \
	-P $MSSQL_SA_PASSWORD \
	-Q "SELECT @@VERSION" 2>/dev/null
  errstatus=$?
  ((counter++))
done

# Display error if connection failed:
if [ $errstatus = 1 ]
then
  echo Cannot connect to SQL Server, installation aborted
  exit $errstatus
fi

# Optional new user creation:
if [ ! -z $SQL_INSTALL_USER ] && [ ! -z $SQL_INSTALL_USER_PASSWORD ]
then
  echo Creating user $SQL_INSTALL_USER
  /opt/mssql-tools/bin/sqlcmd \
	-S localhost \
	-U SA \
	-P $MSSQL_SA_PASSWORD \
	-Q "CREATE LOGIN [$SQL_INSTALL_USER] WITH PASSWORD=N'$SQL_INSTALL_USER_PASSWORD', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=ON, CHECK_POLICY=ON; ALTER SERVER ROLE [sysadmin] ADD MEMBER [$SQL_INSTALL_USER]"
fi

echo Done!

############## END OF SQL SERVER INSTALLATION ##############


# Download Ignition if the installer is not already present (or if md5sum doesn't match)
if [ ! -f /vagrant/Ignition-7.9.4-linux-x64-installer.run ] || [ "`md5sum /vagrant/Ignition-7.9.4-linux-x64-installer.run | cut -c 1-32`" != "b60bc5173dd61cf0273a7394006328dd" ]; then
  echo "Downloading Ignition 7.9.4"
  wget -q https://s3.amazonaws.com/files.inductiveautomation.com/release/ia/build7.9.4/20170829-1101/Ignition-7.9.4-linux-x64-installer.run -O /vagrant/Ignition-7.9.4-linux-x64-installer.run >> install.log
else
  echo "Existing Installer Detected, Skipping Download"
fi
echo "Installing Ignition 7.9.4"
chmod a+x /vagrant/Ignition-7.9.4-linux-x64-installer.run
sudo /vagrant/Ignition-7.9.4-linux-x64-installer.run --unattendedmodeui none --mode unattended --prefix /usr/local/share/ignition >> install.log
# Restore base gateway backup
echo "Restoring Base Gateway Backup"
sudo /usr/local/share/ignition/gwcmd.sh -s /vagrant/base-gateway.gwbk -y >> install.log
echo "Starting Ignition"
sudo systemctl start ignition.service