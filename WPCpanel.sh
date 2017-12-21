#!/usr/bin/env bash

# Help message.
usage="$(basename "$0") [-h] [-e -q] <domain> <username> -- program to install WP on cpanel servers.
where:
    <domain> string	The account's main domain name
    <user>	 string	The account's username.	A valid username.
    -h  show this help text
    -e  set the user's email
    -q  integer,    The account's disk space quota"

if [[ "$EUID" -ne 0 ]]; then
	echo "Sorry, you need to run this as root"
	exit 1
fi

if [[ "$#" -eq 0 ]]; then
    echo "please enter some arguments"
    echo "$usage"
    exit 1
fi

email= quota=
while getopts ':e:q:h' opt; do
    case $opt in

        e)  email=$OPTARG
            ;;

        q)  quota=true
            ;;

        h)  echo "$usage"
            exit
            ;;
        '?')    echo "$0: invalid option -$OPTARG" >&2
                echo "$usage" >&2
                exit 1
                ;;
    esac
done
shift $(($OPTIND -1)) # Remove options, leave arguments.

#Set username and domain from positional arguments.
domain=$1
username=$2
# OS type
if [[ -e /etc/debian_version ]]; then
	OS="debian"
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
	OS="centos"
else
	echo "Looks like you aren't running this installer on a Debian, Ubuntu or CentOS system. Please run it on a supported system"
	exit 4
fi

# check and install pwgen
if [[ ! -e "/usr/bin/pwgen" ]]; then
    if [[ $OS == 'debian' ]]; then
        apt-get -y install pwgen
    else [[ $OS == 'centos' ]]
        yum -y install epel-release
        yum -y install pwgen
    fi
fi

# check if domain is already got account.
cut -d ':' -f 1 /etc/userdomains | sed -n '2,$p' | grep -q  "^$domain$"

if [[ $? -eq 0 ]];then
    echo ""
    echo "Domain $domain is found"
    echo " do you want to retrieve\\change account info?"
    while [[ $CONTINUE != "y" && $CONTINUE != "n" ]]; do
        read -p "Continue ? [y/n]: " -e CONTINUE
    done
    if [[ "$CONTINUE" = "n" ]]; then
        echo "Ok, bye !"
        exit 4
    fi
    user_name=$(/scripts/whoowns "$domain")
    newpass=$(pwgen -s -1 35)
    whmapi0 passwd user=$user_name pass=$newpass
    # if email is added.. send email with Credentials.
    if [[ -n $email ]];then
        echo ""
        echo "Sending Email to $email with Credentials:"

        mail -s "Cpanel Credentials" "$email" <<EOF
         "+==============================================================+"
         "| New Account Info                                             |"
         "+==============================================================+"
         "|
         "| Cpanel credentials:
         "| Cpanel domain: $domain"
         "| Cpanel user: $user_name
         "| Cpanel password: $newpass 
EOF
    fi

    echo "+==============================================================+"
    echo "|      Account Info                                             |"
    echo "+==============================================================+"
    echo "|                                                              "
    echo "| Cpanel credentials:                                          "
    echo "| Cpanel domain: $domain"
    echo "| Cpanel user: $user_name                                       "
    echo "| Cpanel password: $newpass                                    "
    echo "|                                                              "

exit
fi


# Test if wwwacct is available.
if [[ ! -e "/usr/local/cpanel/scripts/wwwacct" ]] ; then
    echo "wwwacct not found"
    exit 1
fi
newpass=$(pwgen -s -1 35)
echo ""
echo "Cpanel account is being made"
echo y | /usr/local/cpanel/scripts/wwwacct  $domain $username $newpass

if php -i | grep -q suhosin; then
    echo ""
    echo "Suhosin is found..."
    echo "Suhosin will cause some problems but we could Avoid them by adding aline on php.ini "
    echo "It will be removed afterwords tho"
    while [[ $CONTINUE != "y" && $CONTINUE != "n" ]]; do
        read -p "Continue ? [y/n]: " -e CONTINUE
    done
    if [[ "$CONTINUE" = "n" ]]; then
        echo "Ok, bye !"
        exit 4
    fi
    phpini=$(php --ini | grep "Configuration File" | tr -s ' ' | cut -d ' ' -f 4 | grep ini)
    echo "suhosin.executor.include.whitelist=\"phar\"" >> $phpini
    Suhosin="y"
fi

echo ""
echo "Wordpress is being downloaded..."
# download WP.
curl -sL https://wordpress.org/latest.tar.gz -o wp.tar.gz
tar -zxf wp.tar.gz -C /home/$username/public_html --strip-components=1
rm -rf  wp.tar.gz

echo ""
echo "Database is being made..."

dbname=${username:0:8}"_wordpress"
dbuser=${username:0:8}"_dbuser"
dbpassword=$(pwgen -s -1 35)

# Create mySQL database
echo ""
echo -e "\n\nCreating mySQL database ($dbname) in new cPanel account"
uapi --user=$username Mysql create_database name=$dbname
uapi --user=$username Mysql create_user name=$dbuser password=$dbpassword
uapi --user=$username Mysql set_privileges_on_database user=$dbuser database=$dbname privileges=ALL%20PRIVILEGES
echo ""

# download WP-cli.
curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod u+x ./wp-cli.phar
./wp-cli.phar config create --dbname="$dbname" --dbuser="$dbuser" --dbpass="$dbpassword" --dbhost="localhost" --path="/home/$username/public_html/" --allow-root
rm -f ./wp-cli.phar

chown -R $username:$username /home/$username/public_html 
# Remove suhosin tweak
if [[ $Suhosin = "y" ]]; then
    echo ""
    echo "Suhosin tweak is being removed..."
    sed -i '$ d' $phpini
fi

# if email is added.. send email with Credentials.
if [[ -n $email ]];then
    echo ""
    echo "Sending Email to $email with Credentials:"

    mail -s "Cpanel Credentials" "$email" <<EOF
     "+==============================================================+"
     "| New Account Info                                             |"
     "+==============================================================+"
     "|
     "| Cpanel credentials:
     "| Cpanel domain: $domain"
     "| Cpanel user: $username
     "| Cpanel password: $newpass
EOF

fi
echo "+==============================================================+"
echo "| New Account Info                                             |"
echo "+==============================================================+"
echo "|                                                              "
echo "| Cpanel credentials:                                          "
echo "| Cpanel domain: $domain"
echo "| Cpanel user: $username                                       "
echo "| Cpanel password: $newpass                                    "
echo "|                                                              "
echo "|                                                              "
echo "| Database credentials:                                        "
echo "| DB name: $dbname                                             "
echo "| DB user: $dbuser                                             "
echo "| DB name password: $dbpassword                                "
echo "+==============================================================+"
