#!/bin/bash
# vim: set cindent tabstop=4 shiftwidth=4:

########################################################
# Definition of variables                              #
########################################################
VM_DIR=/var/lib/glance/images
workdir=`cd $(dirname ${BASH_SOURCE[0]}); pwd`

########################################################
# check input parameter number                         #
########################################################
function check_paramter_number()
{
    paramter_number=$1
    if [ $paramter_number -lt 2 ]; then
	    echo "Usage: $0 <size> [name] [mac_addr] [mem_size] [vcpus] [bridge]"
	    exit 1
    fi
}

########################################################
# check the parameter and set the default value        #
########################################################
function set_defautl_value()
{
    VM_SIZE=$1
    if [ $VM_SIZE -lt 2 ]; then
	    echo "Image size must be larger than 2GB."
	    exit 1
    fi

    VM_NAME=$2
    #default vm name
    if [ -z $VM_NAME ]; then
	    VM_NAME=kersrv
    fi

    VM_MAC=$3
    #default vm mac address
    if [ -z $VM_MAC ]; then
	    VM_MAC=52:54:52:54:52:54
    fi

    VM_MEM=$4
    #default vm memorry size
    if [ -z $VM_MEM ]; then
	    VM_MEM=1024
    fi

    VM_CPUS=$5
    #default vm cp number
    if [ -z $VM_CPUS ]; then
	    VM_CPUS=1
    fi

    BRIDGE=$6
    #default vm cp number
    if [ -z $BRIDGE ]; then
	    BRIDGE=br0
    fi

    let VM_SIZE=$VM_SIZE*1024
}

########################################################
# Print . . . when executing a long action             #
########################################################
function doing()
{
	if [ $# -ne 1 ]; then
		echo "Wrong number of arguments: $#, exit."
		exit
	fi

	while true; do
		echo -n ". "
		sleep 2
	done &

	BG_PID=$!
	eval $1
	kill -PIPE $BG_PID
	echo
}

########################################################
# chmod for the whole chain                            #
########################################################
function chcmod()
{
	mod_str="$1"
	item="$2"
	while [ "${item}" != "/" -a "${item}" != "." ]; do
		echo "Changing mode for ${item} ..."
		chmod ${mod_str} ${item}
		item=`dirname ${item}`
	done
}

########################################################
# check kvm mode and permission                        #
########################################################
function check_kvm()
{
    yum -y install qemu-kvm qemu-img python-virtinst virt-manager virt-viewer libvirt libvirt-client libguestfs
    #make sure kvm mode is loaded
    modprobe kvm && modprobe kvm_intel || modprobe kvm_amd
    echo "Reload kvm dev entry"
    udevadm trigger --sysname-match=kvm
}

########################################################
# clean the last files                                 #
########################################################
function clean_last()
{
    service libvirtd restart

    #destroy last vm
    virsh destroy $VM_NAME >/dev/null 2>&1
    virsh undefine $VM_NAME >/dev/null 2>&1

    #remove last vm image file
    rm -f $IMG_FILE
}

########################################################
# check the free disk space in Mb                      #
########################################################
function dir_free_lt()
{
	directory="$1"
	threshold="$2"  # size in MB
	df_result=(`df -m "$directory" | tail -n 1`)
	((idx=${#df_result[@]}-3))
	[ ${df_result[$idx]} -lt "$threshold" ]
}

########################################################
# check disk space for VM                              #
########################################################
function check_disk_space()
{
    let VM_THRESHOLD=$VM_SIZE+1024
    dir_free_lt "$VM_DIR" "$VM_THRESHOLD" && echo "Not enough disk space for VM" && exit 1
}

########################################################
# create vm image file                                 #
########################################################
function create_vm_img()
{
    dd if=/dev/zero of=$IMG_FILE seek=$VM_SIZE count=0 bs=1024k

    virt-install \
    --name=$VM_NAME \
    --ram=$VM_MEM \
    --vcpus=$VM_CPUS \
    --arch=x86_64 \
    --os-type=linux \
    --os-variant=rhel6 \
    --hvm \
    --disk path=$IMG_FILE \
    --accelerate \
    --network=bridge:$BRIDGE,mac=$VM_MAC \
    --nographics \
    --location=http://$REPO_IP/rhel6/ \
    --extra-args="ksdevice=bootif ks=http://$REPO_IP/scp/vmks.cfg biosdevname=0 console=ttyS0" \
    --noautoconsole

    doing "sleep 30"
    virsh console $VM_NAME

    reset
}

########################################################
# register base image                                  #
########################################################
function register_image()
{
    if [ "$VM_NAME" != "kersrv" ]; then	# only kersrv need the registration process below
	    exit
    fi
    
    #Begin to register base image
    echo -e "\n\n\033[01;32mFinished ... \nRegistering base image ...\n\033[00m"
    
    virsh destroy $VM_NAME >/dev/null 2>&1
    virsh undefine $VM_NAME >/dev/null 2>&1

    # find a free loopback device
    if ! losetup -f 2>/dev/null; then
	    max_loop_num=`ls /dev/loop* | tr -d "/dev/loop" | sort -n | tail -n 1`
	    next_loop_num=$(( $max_loop_num + 1 ))
	    mknod -m660 "/dev/loop${next_loop_num}" b 7 ${next_loop_num}
        udevadm settle
    fi
    # extract the root partition of the image
    echo "Extracting the root partition of the image ..."
    LOOP_DEV=$(losetup -f)
    losetup $LOOP_DEV $IMG_FILE
    udevadm settle
    kpartx -a $LOOP_DEV
    LOOP_DEV_P1=/dev/mapper/$(basename $LOOP_DEV)p1
    udevadm settle
    mount -o rw "${LOOP_DEV_P1}" /mnt
    udevadm settle --exit-if-exists="/mnt/lost+found"
    cd /mnt
    find * | sort | cpio -oc > ${CPIO_FILE}
    cd -
    sync
    umount /mnt
    udevadm settle
    kpartx -d $LOOP_DEV
    udevadm settle
    losetup -d $LOOP_DEV
    udevadm settle
}
test "${BASH_SOURCE[0]}" != "$0" && return

#get the input parameters
export TERM=xterm LC_ALL=C

check_paramter_number $#

VM_SIZE=$1
REPO_IP=$2
VM_NAME=$3
VM_MAC=$4
VM_MEM=$5
VM_CPUS=$6
BRIDGE=$7

#set the paramter value
set_defautl_value

IMG_FILE=$VM_DIR/$VM_NAME.img
CPIO_FILE=$VM_DIR/$VM_NAME.cpio

#ensure vm_dir's access right
cd $workdir
mkdir -p $VM_DIR
chcmod go+rx $VM_DIR

#install virtualization packages
yum groupinstall -y virtualization virtualization-client virtualization-platform

check_kvm
clean_last
check_disk_space

create_vm_img

#register base image
register_image

