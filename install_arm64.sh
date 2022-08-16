#!/bin/bash

# Color
RED='\033[0;31m'
NC='\033[0m' # No Color

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 1>&2
   exit 1
fi

# Check for enough space on / volume
boot_line=$(df -h | grep / | head -n 1)
if [ "x${boot_line}" = "x" ]; then
  echo "Warning: /boot volume not found .."
else
  boot_space=$(echo $boot_line | awk '{print $4;}')
  free_space=$(echo "${boot_space%?}")
  unit="${boot_space: -1}"
  if [[ "$unit" = "K" ]]; then
    echo "Error: Not enough space left ($boot_space) on /boot"
    exit 1
  elif [[ "$unit" = "M" ]]; then
    if [ "$free_space" -lt "25" ]; then
      echo "Error: Not enough space left ($boot_space) on /boot"
      exit 1
    fi
  fi
fi

#
# make sure that we are on something Armbian/RockPi related
# Armbian/RockPi stuff available
# - check for /boot/overlay-user
# - dtparam and dtoverlay is available
errorFound=0
OVERLAYS=/boot/overlay-user
[ -d /boot/firmware/overlays ] && OVERLAYS=/boot/firmware/overlays

if [ ! -d $OVERLAYS ] ; then
  echo "$OVERLAYS not found or not a directory" 1>&2
  mkdir $OVERLAYS
  echo "$OVERLAYS directory created"
fi
# should we also check for alsactl and amixer used in seeed-voicecard?
PATH=$PATH:/opt/vc/bin
for cmd in alsactl amixer ; do
  if ! which $cmd &>/dev/null ; then
    echo "$cmd not found" 1>&2
    echo "You may need to run ./ubuntu-prerequisite.sh"
    errorFound=1
  fi
done
if [ $errorFound = 1 ] ; then
  echo "Errors found, exiting." 1>&2
  exit 1
fi


ver="0.3"
uname_r=$(uname -r)

# we create a dir with this version to ensure that 'dkms remove' won't delete
# the sources during kernel updates
marker="0.0.0"

COMPAT_KERNEL_VER="5.15.52"
COMPAT_PACKAGE_VER="22.05.3"

_VER_RUN=
function get_kernel_version() {
  local ZIMAGE IMG_OFFSET

  _VER_RUN=`uname -r`
  echo "$_VER_RUN"
  return 0
}

function check_kernel_headers() {
  VER_RUN=$(get_kernel_version)
  VER_HDR=$(dpkg -L linux-headers-current-rockchip64 | egrep -m1 "/lib/modules/[[:print:]]+/build" | awk -F'/' '{ print $4; }')
  echo $VER_RUN
  echo $VER_HDR
  [ "X$VER_RUN" == "X$VER_HDR" ] && {
    return 0
  }

  # Only compatible with kernel version
  [ "X$VER_RUN" == "X${COMPAT_KERNEL_VER}"] && {
    return 0
  }

  apt-get -y --reinstall install linux-headers-current-rockchip64=$COMPAT_PACKAGE_VER linux-image-current-rockchip64=$COMPAT_PACKAGE_VER
  echo 'Please reboot to load new kernel and re-run this script'
}

# update and install required packages
which apt &>/dev/null
if [[ $? -eq 0 ]]; then
  # apt update -y
  # Armbian RockPi kernel packages
  apt-get -y install linux-headers-current-rockchip64=$COMPAT_PACKAGE_VER linux-image-current-rockchip64=$COMPAT_PACKAGE_VER
  apt-get -y install dkms git i2c-tools libasound2-plugins
  # update checker
  check_kernel_headers
fi

# Arch Linux
which pacman &>/dev/null
if [[ $? -eq 0 ]]; then
  pacman -Syu --needed git gcc automake make dkms linux-headers-current-rockchip64 i2c-tools
fi

# locate currently installed kernels (may be different to running kernel if it's just been updated)
base_ver=$(get_kernel_version)
base_ver=${base_ver%%[-+]*}
#kernels="${base_ver}+ ${base_ver}-v7+ ${base_ver}-v7l+"
kernels=$(uname -r)
kernel_base_ver=${kernels%%[-+]*}

if [[ "$base_ver" != "$kernel_base_ver" ]] ; then
  echo "------------------------------------------------------"
  echo -e " ${RED}WARNING${NC} Your loaded kernel version is $kernel_base_ver"
  echo " Not matching the updated version $base_ver."
  echo " Kernel was updated, but new kernel was not loaded yet"
  echo -e " Please ${RED}reboot${NC} your device AND THEN run this script ${RED}again"
  exit 1;
fi

function install_module {
  local _i

  src=$1
  mod=$2

  if [[ -d /var/lib/dkms/$mod/$ver/$marker ]]; then
    rmdir /var/lib/dkms/$mod/$ver/$marker
  fi

  if [[ -e /usr/src/$mod-$ver || -e /var/lib/dkms/$mod/$ver ]]; then
    dkms remove --force -m $mod -v $ver --all
    rm -rf /usr/src/$mod-$ver
  fi

  mkdir -p /usr/src/$mod-$ver
  cp -a $src/* /usr/src/$mod-$ver/

  dkms add -m $mod -v $ver
  for _i in $kernels; do
    dkms build -k $_i -m $mod -v $ver && {
      dkms install --force -k $_i -m $mod -v $ver
    }
  done

  mkdir -p /var/lib/dkms/$mod/$ver/$marker
}

install_module "./" "seeed-voicecard"

# install dts overlays
armbian-add-overlay seeed-2mic-voicecard-overlay.dts

#install alsa plugins
# no need this plugin now
# install -D ac108_plugin/libasound_module_pcm_ac108.so /usr/lib/arm-linux-gnueabihf/alsa-lib/
rm -f /usr/lib/arm-linux-gnueabihf/alsa-lib/libasound_module_pcm_ac108.so

#set kernel modules
grep -q "^snd-soc-seeed-voicecard$" /etc/modules || \
  echo "snd-soc-seeed-voicecard" >> /etc/modules
grep -q "^snd-soc-ac108$" /etc/modules || \
  echo "snd-soc-ac108" >> /etc/modules
grep -q "^snd-soc-wm8960$" /etc/modules || \
  echo "snd-soc-wm8960" >> /etc/modules  

#set dtoverlays
CONFIG=/boot/armbianEnv.txt
[ -f /boot/firmware/usercfg.txt ] && CONFIG=/boot/firmware/usercfg.txt

# check that i2c7 is enabled
I2C7=`sed -rn 's/^.*overlays=.*(i2c7).*$/\1/p' $CONFIG`
if [[ -z $I2C7 ]]; then
  echo 'i2c7 is not enabled. You may need to enable this in armbian-config?'
  exit 1
fi

sed -i -e 's:#dtparam=i2c_arm=on:dtparam=i2c_arm=on:g'  $CONFIG || true
grep -q "^dtoverlay=i2s-mmap$" $CONFIG || \
  echo "dtoverlay=i2s-mmap" >> $CONFIG

grep -q "^dtparam=i2s=on$" $CONFIG || \
  echo "dtparam=i2s=on" >> $CONFIG

grep -q "^param_spidev_spi_bus=1$" $CONFIG || \
  echo "param_spidev_spi_bus=1" >> $CONFIG

grep -q "^param_spidev_spi_bus=1$" $CONFIG || \
  echo "param_spidev_spi_bus=1" >> $CONFIG

#install config files
mkdir /etc/voicecard || true
cp *.conf /etc/voicecard
cp *.state /etc/voicecard

#create git repo
git_email=$(git config --global --get user.email)
git_name=$(git config --global --get user.name)
if [ "x${git_email}" == "x" ] || [ "x${git_name}" == "x" ] ; then
    echo "setup git config"
    git config --global user.email "respeaker@seeed.cc"
    git config --global user.name "respeaker"
fi
echo "git init"
git --git-dir=/etc/voicecard/.git init
echo "git add --all"
git --git-dir=/etc/voicecard/.git --work-tree=/etc/voicecard/ add --all
echo "git commit -m \"origin configures\""
git --git-dir=/etc/voicecard/.git --work-tree=/etc/voicecard/ commit  -m "origin configures"

# We don't want a service updating this every time
# cp seeed-voicecard /usr/bin/
# cp seeed-voicecard.service /lib/systemd/system/
# systemctl enable  seeed-voicecard.service 
# systemctl start   seeed-voicecard

echo "------------------------------------------------------"
echo "Please reboot your device to apply all settings"
echo "Enjoy!"
echo "------------------------------------------------------"
