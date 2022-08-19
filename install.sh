#!/bin/bash

if [ ! "$BASH_VERSION" ] ; then
    echo "ERROR: Please use bash not sh or other shells to run this installer. You can also run this script directly like ./install.sh"
    exit 1
fi

show_version() {
    grep fullversion_for_installer "$BASEPATH/surveillance/surveillance.py" | head -n 1 | cut -d"=" -f2
}
get_init_sys() {
  if command -v systemctl > /dev/null && systemctl | grep -q '\-\.mount'; then
    SYSTEMD=1
  elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
    SYSTEMD=0
  else
    echo "Unrecognized init system"
    return 1
  fi
}

is_vlc_mmal_present() {
 sed -i 's/geteuid/getppid/' /usr/bin/vlc
 if /usr/bin/vlc -H  2>/dev/null | grep -q -- '--mmal-layer';then
    return 0
 else
    return 1
 fi
}

get_init_sys
BASEPATH="$(cd $(dirname "${BASH_SOURCE[0]}");pwd)"

if ! is_vlc_mmal_present;then
    echo "Your version of vlc does not have the needed mmal options. Rpisurv needs those"
    echo "Minimum tested vlc version for Rpisurv is (VLC media player 3.0.11 Vetinari (revision 3.0.11-0-gdc0c5ced72),"
    echo "Maximum tested vlc version for Rpisurv is (VLC media player 3.0.17.4 Vetinari (3.0.13-8-g41878ff4f2)"
    echo "Aborting installation, upgrade to latest vlc player with mmal support"
    exit 2
fi

#Prevent starting up in graphical mode, we do not need this -> save resources
if [ $SYSTEMD -eq 1 ]; then
  sudo systemctl set-default multi-user.target
  #enable systemd-timesyncd
  sudo timedatectl set-ntp true

else
  [ -e /etc/init.d/lightdm ] && update-rc.d lightdm disable
  #Enable timesync
  TIMESYNCCMD="/usr/sbin/service ntp stop 2>/dev/null 1>&2; /usr/sbin/ntpdate 0.debian.pool.ntp.org 2>/dev/null 1>&2; /usr/sbin/service ntp start 2>/dev/null 1>&2"
  if ! grep -q "^$TIMESYNCCMD" /etc/rc.local ;then
          sudo echo "$TIMESYNCCMD" >> /etc/rc.local

  fi
fi

SOURCEDIR="$BASEPATH/surveillance"
MAINSOURCE="surveillance.py"
CONFDIR="conf"
BACKUPCONFDIR=/tmp/backup_rpisurv3config_$(date +%Y%m%d_%s)


DESTPATH="/usr/local/bin/rpisurv"
sudo mkdir -p "$DESTPATH"
USEEXAMPLECONFIG="no"
OVERWRITESIMAGES="no"

if [ x"$OVERWRITESIMAGES" == x"no" ]; then
    RSYNCOPTIONS="${RSYNCOPTIONS} --exclude /images"
fi

if [ x"$USEEXAMPLECONFIG" == x"no" ]; then
    RSYNCOPTIONS="${RSYNCOPTIONS} --exclude /conf"
fi

sudo rsync -av $RSYNCOPTIONS "$SOURCEDIR/" "$DESTPATH/"

#Make sure pngview is executable by root
sudo chmod 770 "${DESTPATH}"/bin/pngview


STARTUPCMD="cd $DESTPATH; python "$MAINSOURCE" &"

if [ $SYSTEMD -eq 1 ]; then
    #Remove old way of starting rpisurv
    sudo sed -i /$MAINSOURCE/d /etc/rc.local
    sudo cp -v rpisurv /usr/bin/
    sudo chmod 700 /usr/bin/rpisurv
    sudo cp -v rpisurv.service /etc/systemd/system/
    sudo chmod 644 /etc/systemd/system/rpisurv.service
    sudo systemctl daemon-reload
    sudo systemctl enable rpisurv
else
    #No systemd detected use old method to start
    if ! grep -q "^$STARTUPCMD" /etc/rc.local ;then
        #Filter out exit 0 command if present
        sudo sed -i '/exit 0$/d' /etc/rc.local
        sudo echo "$STARTUPCMD" >> /etc/rc.local
        #Add exit 0 as last line for good practise
        sudo echo  "exit 0" >> /etc/rc.local
    fi
fi
#Link config file dir into /etc as convenient way to edit
if [ -f /etc/rpisurv ]; then sudo rm -fv /etc/rpisurv;fi
sudo ln -fs $DESTPATH/"$CONFDIR" /etc/rpisurv
