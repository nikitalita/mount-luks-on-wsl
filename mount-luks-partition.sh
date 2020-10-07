#!/bin/bash

#defaults:
DEFAULTLUKSMOUNTPOINT="/mnt/luks-drive"
LUKSMOUNTPOINT=${LUKSMOUNTPOINT-$DEFAULTLUKSMOUNTPOINT}
READONLY=${READONLY-1}
IGNOREWARNING=${IGNOREWARNING-0}
UNMOUNT=${UNMOUNT-0}
DEPENDENCIES="cryptsetup lvm2"

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

printColor () {
    #Param or NC.
    COLOR="${2-$NC}"
    printf "${COLOR}${1}${NC}"
}

printError () {
    printColor "${1}\n" $RED
}

printInstruction () {
    printColor "${1}" $BLUE
}

printSuccess () {
    printColor "******${1}******\n" $GREEN
}

printMessage () {
    printColor "******${1}******\n" $CYAN
}

printWarning () {
    printColor "${1}\n" $YELLOW
}

installDependencies () {
	$distro_name = `lsb_release -i -s`
	  case "$distro_name" in
		Ubuntu)
			dpkg -s $DEPENDENCIES >/dev/null 2>&1
			if [[ $? -ne 0 ]]; then
				printMessage "Installing dependencies"
				apt install $DEPENDENCIES
			fi
			;;
		*)
			printError "Other distros not supported yet!"
			;;
	
}

findLuksBlkDev () {
    for luksBlkDev in `lsblk -rno path`; do
            cryptsetup isLuks $luksBlkDev
            if [[ $? -eq "0" ]]; then
                    break
            fi
            luksBlkDev=""
    done
}

findVGName () {
    VGName=`sudo pvdisplay /dev/mapper/myvolume --noheadings -C -o vg_name`
}

findRootFSLVDev () {
    LVDEVS=( $(dmsetup ls -o blkdevname) )
    index=0
    if [[ ${LVDEVS[0]} == "No" ]]; then
        printError "no logical volumes on LUKS partition!"
        exit_with_error
    fi
    while [[ $index < ${#LVDEVS[@]} ]]; do
        LVNAME=${LVDEVS[$index]}
        LVDEVICE=${LVDEVS[$index + 1]}
        LVDEVICE=${LVDEVICE//(}
        LVDEVICE=${LVDEVICE//)}
        blargh=`echo $LVNAME | grep $VGName`
        if [[ $? -eq 0 ]] && [[ `blkid /dev/$LVDEVICE --match-tag TYPE -o value` == "ext4" ]]; then 
            break
        fi
        LVNAME=""
        LVDEVICE=""
        ((index=index+2))
    done
    if [[ $LVNAME == "" ]]; then
        printError "could not find Logical volume with root fs!"
        exit_with_error
    fi
    RootFSDevice=$LVDEVICE
}

unmountLuks () {
    printMessage "***** Unmounting LUKS partition *****"
    sudo umount -v $LUKSMOUNTPOINT
    EXITCODE=$?

    if [[ $EXITCODE -eq 32 ]]; then
        echo "LUKS mount point already unmounted"
    # If device is still busy
    elif [[ $EXITCODE -eq 16 ]]; then
        printError "Could not unmount LUKS drive, still in use!"
        exit_with_error
    elif [[ $EXITCODE -ne 0 ]]; then
        printError "Could not unmount LUKS drive"
        exit_with_error
    fi
    findVGName
    sudo vgchange -an $VGName
    sudo cryptsetup luksClose myvolume
    EXITCODE=$?
    if [[ $EXITCODE -eq 4 ]]; then
        echo "LUKS volume already closed"
    elif [[ $EXITCODE -ne 0 ]]; then
        printError "Could not close LUKS volume with cryptsetup!"
        exit_with_error
    else 
        echo "LUKS volume closed"
    fi
    printSuccess "***** Successfully unmounted LUKS partition *****"
}

print_write_warning () {
    if [[ $IGNOREWARNING -eq 1 ]]; then 
        return
    fi
    if [[ $READONLY -eq 0 ]]; then
        printWarning "\n*************************************************************************"
        printWarning "WARNING: Write permissions on LUKS partitions with WSL is highly experimental."
        printWarning "Seriously, you're a mad lad/lass/lax if you do this."
        printWarning "*************************************************************************\n"
    fi
}

exit_with_error () {
    printError "***** Exited with errors! *****"
    exit 1;
}


# ************** MAIN ****************

#Parse params
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -u|--unmount)
      UNMOUNT=1
      shift
      ;;
    -m|--mount-point)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        LUKSMOUNTPOINT=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -w|--read-write)
      READONLY=0
      shift
      ;;
    -r|--read-only)
      READONLY=1
      shift
      ;;
    -y|--yes)
      IGNOREWARNING=1
      shift
      ;;
    -h|--help)
      echo "Finds LUKS drive on system and asks user to mount."
      echo "Usage: $0 <options>"
      echo "-u | --unmount: unmount drive"
      echo "-m | --mount-point <mountpoint>: mount point on Linux instance"
      echo "-r | --read-only: mounts with read-only permissions (default)"
      echo "-w | --read-write: mount LUKS drive with write permissions (WARNING: highly experimental)"
      echo "-y | --yes: Skip warning about write permissions"
      exit 0
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"

# Run this script as root
if [ "$EUID" -ne 0 ]; then 
  printError "Please run as root"
  exit 1
fi

installDependencies

if [[ $UNMOUNT -eq 1 ]]; then
    unmountLuks
    exit 0
fi

printMessage "Mounting LUKS partition"

findmnt $LUKSMOUNTPOINT >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    printError "LUKS mount point already mounted!"
    exit_with_error
fi

print_write_warning

findLuksBlkDev
echo "Found LUKS partition: $luksBlkDev"
printInstruction "Please enter in your LUKS encrypted drive password\n"

# cryptsetup mount options
if [[ $READONLY -eq 0 ]]; then
    OPTIONS=""
else
    #default
    OPTIONS="--readonly"
fi

cryptsetup $OPTIONS luksOpen $luksBlkDev myvolume

if [[ $? -ne 0 ]]; then
    printError "could not open LUKS drive"
    exit_with_error
fi

findVGName

if [[ $VGName == "" ]]; then 
    printError "No volume group found!"
    exit_with_error
fi

vgchange -ay $VGName

findRootFSLVDev

echo "Mapped root drive is $RootFSDevice"

if [[ $READONLY -eq 0 ]]; then
    OPTIONS="-o rw"
else
    #default
    OPTIONS="-o ro"
fi

mkdir -p $LUKSMOUNTPOINT
mount -v $OPTIONS /dev/$RootFSDevice $LUKSMOUNTPOINT
if [[ $? -ne "0" ]]; then
    printError "could not mount drive"
    exit_with_error
fi

echo "luksBlkDev=$luksBlkDev" > ~/.luksmountenv
echo "VGName=$VGName" >> ~/.luksmountenv
echo "RootFSDevice=$RootFSDevice" >> ~/.luksmountenv
echo "LUKSMOUNTPOINT=$LUKSMOUNTPOINT" >> ~/.luksmountenv
printSuccess "Successfully mounted LUKS partition!"
