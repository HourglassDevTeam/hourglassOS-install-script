#!/bin/bash

# echo -e 是用于在 Bash 脚本中输出文本的命令，其中 -e 选项用于启用对反斜杠转义字符的解释。
if [ "$USER" != root ]; then
    # echo -e "${RED}Please execute this script as root. \n${NC}"
    echo -e "${RED}请以 root 用户身份执行此脚本。\n${NC}"
    exit 1
fi


# 这些是用于在终端输出文本时设置颜色的 ANSI 转义码。每个变量表示一种颜色或格式，用于格式化文本的显示。
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\e[1;33m'
NC='\033[0m'

# Source file that contains "hidden" settings
# 在 Bash 脚本中，if [ "$#" == "1" ]; 用来检查传递给脚本的命令行参数数量是否为 1。即首先检查脚本是否传递了一个参数。
if [ "$#" == "1" ]; then
    # echo -e "Sourcing hidden options file... \n"
    # commandFailure="Sourcing hidden options file has failed."
    echo -e "正在加载隐藏的选项文件... \n"
    commandFailure="加载隐藏的选项文件失败。"
    . "$1" || failureCheck
fi

entry() {

    # Unsetting to prevent duplicates when the installer scans for modules
    # 这段代码的作用是在安装程序扫描模块时，确保不会出现重复的模块项。
    # 它首先检查一个名为 modulesDialogArray 的变量是否已定义，如果已定义则将其取消定义，以防止后续操作中出现重复的模块。
    if [ -n "$modulesDialogArray" ]; then
        unset modulesDialogArray
    fi

    # This script will only work on UEFI systems.
    # 这段代码的作用是检查系统是否通过 UEFI 启动，如果系统是通过 BIOS 启动的，则会提示错误信息并执行相应的错误处理函数。
    if [ ! -e "/sys/firmware/efi" ]; then
        # commandFailure="This script only supports UEFI systems, but it appears we have booted as BIOS."
        commandFailure="此脚本仅支持 UEFI 系统，但似乎本机器是通过 BIOS 启动的。"
        failureCheck
    fi

    # Autodetection for glibc/musl　
    # 这段代码的作用是自动检测系统使用的 C 标准库是 glibc 还是 musl，并根据结果设置变量 muslSelection。
    if ldd --version | grep GNU ; then
        muslSelection="glibc"
    else
        muslSelection="musl"
    fi

    if [ "$(uname -m)" != "x86_64" ]; then
        # commandFailure="This systems CPU architecture is not currently supported by this install script."
        commandFailure="此安装脚本当前不支持该系统的 CPU 架构。"
        failureCheck
    fi

    # 这段代码的作用是检查当前目录下是否存在名为 systemchroot.sh 的脚本文件。
    # 如果文件不存在，则设置一个错误信息，并调用 failureCheck 函数处理错误。
    if [ ! -e "$(pwd)/systemchroot.sh" ]; then
        commandFailure="次要脚本似乎缺失。这可能是因为它的名称不正确，或者它在 $(pwd) 中不存在。"
        # commandFailure="Secondary script appears to be missing. This could be because the name of it is incorrect, or it does not exist in $(pwd)."
        failureCheck
    fi

    # 这段代码的作用是检查当前工作目录下是否存在名为 modules 的目录。
    # 如果目录不存在，则设置一个错误信息，并调用 failureCheck 函数处理错误。
    if [ ! -e "$(pwd)/modules" ]; then
        # commandFailure="Modules directory appears to be missing. This could be because the name of it is incorrect, or it does not exist in $(pwd)."
        commandFailure="模块目录似乎缺失。它在 $(pwd) 中并不存在，可能是因为名称不正确。"
        failureCheck
    fi

    # echo -e "Testing network connectivity... \n"
    echo -e "正在测试网络连接...\n"

    # 注意我们的国内版才这样ping
    if ping -c 1 baidu.com &>/dev/null || ping -c 1 qq.com &>/dev/null ; then
        # echo -e "Network check succeeded. \n"
        echo -e "网络已经正常运行。\n"
    else
        # commandFailure="Network check failed. Please make sure your network is active."
        commandFailure="网络检测失败。请确保您的网络处于活动状态。"
        failureCheck
    fi

    # echo -e "Begin void installer... \n"
    echo -e "开始 HourglassOS 安装程序... \n"

    # echo -e "Grabbing installer dependencies... \n"
    echo -e "正在获取安装程序的依赖项... \n"

    # commandFailure="Dependency installation has failed."
    commandFailure="依赖项安装失败。"
    
    xbps-install -Suy xbps || failureCheck # 以防 ISO 中的 xbps 过时
    xbps-install -Suy dialog bc parted || failureCheck

    # echo -e "Creating .dialogrc... \n"
    echo -e "正在创建 .dialogrc... \n"
    dialog --create-rc ~/.dialogrc
    # 我觉得 dialog 默认的蓝色背景有点刺眼，这里将它改成黑色。
    sed -i -e 's/screen_color = (CYAN,BLUE,ON)/screen_color = (BLACK,BLACK,ON)/g' ~/.dialogrc
    # 顺便调整一些其他设置...
    sed -i -e 's/title_color = (BLUE,WHITE,ON)/title_color = (BLACK,WHITE,ON)/g' ~/.dialogrc

    diskConfiguration

}

diskConfiguration() {

    # We're going to define all disk options and use them later on so the user can verify the layout and return to entry to start over if something isn't correct, before touching the disks.
    # 先定义所有磁盘选项，让用户在修改磁盘前验证磁盘布局。如果发现有问题，用户可以返回重新选择。
    diskPrompt=$(lsblk -d -o NAME,SIZE -n -e7)
    diskReadout=$(lsblk -o NAME,SIZE,TYPE -e7)

    # if ! diskPrompt=$(drawDialog --begin 2 2 --title "Available Disks" --infobox "$diskReadout" 0 0 --and-widget --title "Partitioner" --menu 'The disk you choose will not be modified until you confirm your installation options.\n\nPlease choose the disk you would like to partition and install Void Linux to:' 0 0 0 $diskPrompt) ; then
    #     exit 0
    # fi

    # 这段代码的作用是通过 drawDialog 工具展示一个带有磁盘信息的对话框，允许用户选择一个磁盘。如果用户取消或关闭了对话框，则脚本将退出。
    if ! diskPrompt=$(drawDialog --begin 2 2 --title "可用磁盘" --infobox "$diskReadout" 0 0 --and-widget --title "分区工具" --menu '在确认您的安装选项之前，您选择的磁盘不会被修改。\n\n请选择您希望分区并安装 HourglassOS 的磁盘：' 0 0 0 $diskPrompt) ; then
    # exit 0 表示脚本正常完成，操作系统接收到状态码 0，表示没有错误。
          exit 0
    fi

    diskInput="/dev/$diskPrompt"

    diskSize=$(lsblk --output SIZE -n -d $diskInput)
    diskFloat=$(echo $diskSize | sed 's/G//g')
    diskAvailable=$(echo $diskFloat - 0.5 | bc)
    diskAvailable+="G"

    partOutput=$(partitionerOutput)

    # 这段代码的作用是通过 drawDialog 提供一个交互式对话框，询问用户是否希望创建交换分区（swap partition），如果用户选择 "是"，则进一步询问用户希望创建多大的交换分区。根据用户输入的大小进行计算，并更新分区信息。
    # if drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --title "Partitioner" --yesno "Would you like to have a swap partition?" 0 0 ; then
    #     swapPrompt="Yes"
    #     partOutput=$(partitionerOutput)
        
    #     swapInput=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "Partitioner" --inputbox "How large would you like your swap partition to be?\n(Example: '4G')" 0 0)

    #     sizeInput=$swapInput
    #     diskCalculator
    #     partOutput=$(partitionerOutput)
    # fi

    if drawDialog --begin 2 2 --title "磁盘详情" --infobox "$partOutput" 0 0 --and-widget --title "分区工具" --yesno "您想要创建一个交换分区吗？" 0 0 ; then
    swapPrompt="Yes"
    partOutput=$(partitionerOutput)
    
    swapInput=$(drawDialog --begin 2 2 --title "磁盘详情" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "分区工具" --inputbox "您想要多大的交换分区？\n（例如：'4G')" 0 0)

    sizeInput=$swapInput
    diskCalculator
    partOutput=$(partitionerOutput)
fi

    # rootPrompt=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "Partitioner" --inputbox "If you would like to limit the size of your root filesystem, such as to have a separate home partition, you can enter a value such as '50G' here.\n\nOtherwise, if you would like your root partition to take up the entire drive, enter 'full' here." 0 0)

    rootPrompt=$(drawDialog --begin 2 2 --title "磁盘详情" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "分区工具" --inputbox "如果您希望限制根文件系统的大小（例如为了创建单独的 /home 分区），请在此输入一个值，例如 '50G'。\n\n否则，如果您希望根分区占用整个磁盘空间，请输入 'full'。" 0 0)
    # If the user wants the root partition to take up all space after the EFI partition, a separate home on this disk isn't possible.
    if [ "$rootPrompt" == "full" ]; then
        # 设置 separateHomePossible 变量为 0，表示不可能创建单独的 /home 分区，因为根分区占用了整个磁盘。
        separateHomePossible=0
        # 设置 homePrompt 为 "No"，表示不会创建单独的 /home 分区。
        homePrompt="No"
    else
        sizeInput=$rootPrompt
        diskCalculator
        partOutput=$(partitionerOutput)

        separateHomePossible=1
    fi

    # if [ "$separateHomePossible" == "1" ]; then
    #     if drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --title "Partitioner" --yesno "Would you like to have a separate home partition?" 0 0 ; then
    #         homePrompt="Yes"
    #         homeInput=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "Partitioner" --inputbox "How large would you like your home partition to be?\n(Example: '100G')\n\nYou can choose to use the rest of your disk after the root partition by entering 'full' here." 0 0)
            
    #         if [ "$homeInput" != "full" ]; then
    #             sizeInput=$homeInput
    #             diskCalculator
    #         fi
    #     else
    #         homePrompt="No"
    #     fi
    # fi

    if [ "$separateHomePossible" == "1" ]; then
        if drawDialog --begin 2 2 --title "磁盘详情" --infobox "$partOutput" 0 0 --and-widget --title "分区工具" --yesno "您希望创建一个单独的 /home 分区吗？" 0 0 ; then
            homePrompt="Yes"
            homeInput=$(drawDialog --begin 2 2 --title "磁盘详情" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "分区工具" --inputbox "您希望创建多大的 /home 分区？\n（例如：'100G'）\n\n您可以选择使用根分区之后剩下的磁盘空间，输入 'full' 即可。" 0 0)

            if [ "$homeInput" != "full" ]; then
                sizeInput=$homeInput
                diskCalculator
            fi
        else
            homePrompt="No"
        fi
    fi

    installOptions

}

installOptions() {

    if drawDialog --title "Encryption" --yesno "Should this installation be encrypted?" 0 0 ; then
        encryptionPrompt="Yes"
        if drawDialog --title "Wipe Disk" --yesno "Would you like to securely wipe the selected disk before setup?\n\nThis can take quite a long time depending on how many passes you choose." 0 0 ; then
            wipePrompt="Yes"
            passInput=$(drawDialog --title "Wipe Disk" --inputbox "How many passes would you like to do on this disk?\n\nSane values include 1-3. The more passes you choose, the longer this will take." 0 0)
        else
            wipePrompt="No"
            passInput=0
        fi
    else
        encryptionPrompt="No"
    fi

    if [ -z "$basesystem" ]; then
        baseChoice=$(drawDialog --no-cancel --title "Base system meta package choice" --menu "If you are unsure, choose 'base-system'" 0 0 0 "base-system" "- Traditional base system package" "base-container" "- Minimal base system package targeted at containers and chroots")
    else
        baseChoice="Custom"
    fi

    # More filesystems such as zfs can be added later.
    # Until btrfs is any bit stable or performant, it will not be accepted as a feature.
    fsChoice=$(drawDialog --no-cancel --title "Filesystem choice" --menu "If you are unsure, choose 'ext4'" 0 0 0 "ext4" "" "xfs" "")

    suChoice=$(drawDialog --no-cancel --title "SU choice" --menu "If you are unsure, choose 'sudo'" 0 0 0 "sudo" "" "doas" "" "none" "")
    
    if [ -z "$basesystem" ]; then
        kernelChoice=$(drawDialog --no-cancel --title "Kernel choice" --menu "If you are unsure, choose 'linux'" 0 0 0 "linux" "- Normal Void kernel" "linux-lts" "- Older LTS kernel" "linux-mainline" "- Bleeding edge kernel")
    else
        kernelChoice="Custom"
    fi

    bootloaderChoice=$(drawDialog --no-cancel --title "Bootloader choice" --menu "If you are unsure, choose 'grub'" 0 0 0 "grub" "- Traditional bootloader" "efistub" "- Boot kernel directly" "uki" "- Unified Kernel Image (experimental)" "none" "- Installs no bootloader (Advanced)")

    hostnameInput=$(drawDialog --no-cancel --title "System hostname" --inputbox "Set your system hostname." 0 0)

    createUser=$(drawDialog --title "Create User" --inputbox "What would you like your username to be?\n\nIf you do not want to set a user here, choose 'Skip'\n\nYou will be asked to set a password later." 0 0)

    # Most of this timezone section is taken from the normal Void installer.
    areas=(Africa America Antarctica Arctic Asia Atlantic Australia Europe Indian Pacific)

    if area=$(IFS='|'; drawDialog --title "Set Timezone" --menu "" 0 0 0 $(printf '%s||' "${areas[@]}")) ; then
        read -a locations -d '\n' < <(find /usr/share/zoneinfo/$area -type f -printf '%P\n' | sort) || echo "Disregard exit code"
        location=$(IFS='|'; drawDialog --no-cancel --title "Set Timezone" --menu "" 0 0 0 $(printf '%s||' "${locations[@]//_/ }"))
    fi

    location=$(echo $location | tr ' ' '_')
    timezonePrompt="$area/$location"

    # This line is also taken from the normal Void installer.
    localeList=$(grep -E '\.UTF-8' /etc/default/libc-locales | awk '{print $1}' | sed -e 's/^#//')

    for i in $localeList
    do
        # We don't need to specify an item here, only a tag and print it to stdout
        tmp+=("$i" $(printf '\u200b')) # Use a zero width unicode character for the item
    done

    localeChoice=$(drawDialog --no-cancel --title "Locale Selection" --menu "Please choose your system locale." 0 0 0 ${tmp[@]})

    locale="LANG=$localeChoice"
    libclocale="$localeChoice UTF-8"

    if drawDialog --title "Repository Mirror" --yesno "Would you like to set your repo mirror?" 0 0 ; then
        xmirror
        installRepo=$(cat /etc/xbps.d/*-repository-main.conf | sed 's/repository=//g')
    else
        if [ "$muslSelection" == "glibc" ]; then
            installRepo="https://repo-default.voidlinux.org/current"
        elif [ "$muslSelection" == "musl" ]; then
            installRepo="https://repo-default.voidlinux.org/current/musl"
        fi
    fi

    if [ "$muslSelection" == "glibc" ]; then
        ARCH="x86_64"
    elif [ "$muslSelection" == "musl" ]; then
        ARCH="x86_64-musl"
    fi

    installType=$(drawDialog --no-cancel --title "Profile Choice" --menu "Choose your installation profile:" 0 0 0 "minimal" " - Installs base system only, dhcpcd included for networking." "desktop" "- Provides extra optional install choices.")

    # Extra install options
    if [ "$installType" == "desktop" ]; then

        if [ "$muslSelection" == "glibc" ]; then
            graphicsChoice=$(drawDialog --title 'Graphics Drivers' --checklist 'Select graphics drivers: ' 0 0 0 'intel' '' 'off' 'intel-32bit' '' 'off' 'amd' '' 'off' 'amd-32bit' '' 'off' 'nvidia' '- Proprietary driver' 'off' 'nvidia-32bit' '' 'off' 'nvidia-nouveau' '- Nvidia Nouveau driver (experimental)' 'off' 'nvidia-nouveau-32bit' '' 'off')
        elif [ "$muslSelection" == "musl" ]; then
            graphicsChoice=$(drawDialog --title 'Graphics Drivers' --checklist 'Select graphics drivers: ' 0 0 0 'intel' '' 'off' 'amd' '' 'off' 'nvidia-nouveau' '- Nvidia Nouveau driver (experimental)' 'off') 
        fi

        if [ ! -z "$graphicsChoice" ]; then
            IFS=" " read -r -a graphicsArray <<< "$graphicsChoice"
        fi

        networkChoice=$(drawDialog --title "Networking" --menu "If you are unsure, choose 'NetworkManager'\n\nChoose 'Skip' if you want to skip." 0 0 0 "NetworkManager" "" "dhcpcd" "")

        audioChoice=$(drawDialog --title "Audio Server" --menu "If you are unsure, 'pipewire' is recommended.\n\nChoose 'Skip' if you want to skip." 0 0 0 "pipewire" "" "pulseaudio" "")

        desktopChoice=$(drawDialog --title "Desktop Environment" --menu "Choose 'Skip' if you want to skip." 0 0 0 "gnome" "" "kde" "" "xfce" "" "sway" "" "swayfx" "" "wayfire" "" "i3" "")

        case $desktopChoice in
            sway)
                drawDialog --msgbox "Sway will have to be started manually on login. This can be done by entering 'dbus-run-session sway' after logging in on the new installation." 0 0
                ;;

            swayfx)
                drawDialog --msgbox "SwayFX will have to be started manually on login. This can be done by entering 'dbus-run-session sway' after logging in on the new installation." 0 0
                ;;

            wayfire)
                drawDialog --msgbox "Wayfire will have to be started manually on login. This can be done by entering 'dbus-run-session wayfire' after logging in on the new installation." 0 0
                ;;

            i3)
                if drawDialog --title "" --yesno "Would you like to install lightdm with i3?" 0 0 ; then
                    i3prompt="Yes"
                fi
                ;;
        esac

        # Extras
        read -a modulesList -d '\n' < <(ls modules/ | sort)
        commandFailure="Importing module has failed."

        for i in "${modulesList[@]}"
        do
            if [ -e "modules/$i" ] && checkModule ; then
                . "modules/$i" || failureCheck
                modulesDialogArray+=("'$title' '$description' '$status'")
            fi
        done

        # Using sh here as a simple solution to it misbehaving when ran normally
        modulesChoice=( $(sh -c "dialog --stdout --title 'Extra Options' --no-mouse --backtitle "https://github.com/kkrruumm/void-install-script" --checklist 'Enable or disable extra install options: ' 0 0 0 $(echo "${modulesDialogArray[@]}")") )

        confirmInstallationOptions
    elif [ "$installType" == "minimal" ]; then
        confirmInstallationOptions
    fi

}

confirmInstallationOptions() {  

    drawDialog --yes-label "Install" --no-label "Exit" --extra-button --extra-label "Restart" --title "Confirm Installation Choices" --yesno "    Selecting 'Install' here will install with the options below. \n\n
        Base System: $baseChoice \n
        Repo mirror: $installRepo \n
        Bootloader: $bootloaderChoice \n
        Kernel: $kernelChoice \n
        Install disk: $diskInput \n
        Encryption: $encryptionPrompt \n
        Wipe disk: $wipePrompt \n
        Number of disk wipe passes: $passInput \n
        Filesystem: $fsChoice \n
        SU Choice: $suChoice \n
        Create swap: $swapPrompt \n
        Swap size: $swapInput \n
        Root partition size: $rootPrompt \n
        Create separate home: $homePrompt \n
        Home size: $homeInput \n
        Hostname: $hostnameInput \n
        Timezone: $timezonePrompt \n
        User: $createUser \n
        Installation profile: $installType \n\n
        $( if [ -n "$modulesChoice" ]; then echo "Enabled modules: ${modulesChoice[@]}"; fi ) \n
        $( if [ $installType == "desktop" ]; then echo "Graphics drivers: $graphicsChoice"; fi ) \n
        $( if [ $installType == "desktop" ]; then echo "Networking: $networkChoice"; fi ) \n
        $( if [ $installType == "desktop" ]; then echo "Audio server: $audioChoice"; fi ) \n
        $( if [ $installType == "desktop" ]; then echo "DE/WM: $desktopChoice"; fi ) \n\n
        $( if [ $desktopChoice == "i3" ]; then echo "Install lightdm with i3: $i3prompt"; fi ) \n
    You can choose 'Restart' to go back to the beginning of the installer and change settings." 0 0

    case $? in 
        0)
            install
            ;;
        1)
            exit 0
            ;;
        3)
            entry
            ;;
        *)
            commandFailure="Invalid confirm settings exit code"
            failureCheck
            ;;
    esac
    
}

install() {

    if [ "$wipePrompt" == "Yes" ]; then
        commandFailure="Disk erase has failed."
        clear
        echo -e "Beginning disk secure erase with $passInput passes and then overwriting with zeroes. \n"
        shred --verbose --random-source=/dev/urandom -n$passInput --zero $diskInput || failureCheck
    fi

    clear
    echo "Begin disk partitioning..."

    # We need to wipe out any existing VG on the chosen disk before the installer can continue, this is somewhat scuffed but works.
    deviceVG=$(pvdisplay $diskInput* | grep "VG Name" | while read c1 c2; do echo $c2; done | sed 's/Name//g')

    if [ -z $deviceVG ]; then
        echo -e "Existing VG not found, no need to do anything... \n"
    else
        commandFailure="VG Destruction has failed."
        echo -e "Existing VG found... \n"
        echo -e "Wiping out existing VG... \n"

        vgchange -a n $deviceVG || failureCheck
        vgremove $deviceVG || failureCheck
    fi

    # Make EFI boot partition and secondary partition to store lvm
    commandFailure="Disk partitioning has failed."
    wipefs -a $diskInput || failureCheck
    parted $diskInput mklabel gpt || failureCheck
    parted $diskInput mkpart primary 0% 500M --script || failureCheck
    parted $diskInput set 1 esp on --script || failureCheck
    parted $diskInput mkpart primary 500M 100% --script || failureCheck
 
    if [[ $diskInput == /dev/nvme* ]] || [[ $diskInput == /dev/mmcblk* ]]; then
        partition1="$diskInput"p1
        partition2="$diskInput"p2
    else
        partition1="$diskInput"1
        partition2="$diskInput"2
    fi

    mkfs.vfat $partition1 || failureCheck

    clear

    if [ "$encryptionPrompt" == "Yes" ]; then
        echo "Configuring partitions for encrypted install..."

        if [ -z "$hash" ]; then
            hash="sha512"
        fi
        if [ -z "$keysize" ]; then
            keysize="512"
        fi
        if [ -z "$itertime" ]; then
            itertime="10000"
        fi

        echo -e "${YELLOW}Enter your encryption passphrase here. ${NC}\n"

        case $bootloaderChoice in
            uki)
                cryptsetup luksFormat --type luks2 --batch-mode --verify-passphrase --hash $hash --key-size $keysize --iter-time $itertime --pbkdf argon2id --use-urandom $partition2 || failureCheck
                ;;
            efistub)
                # We get to use luks2 here, no need to maintain compatibility.
                cryptsetup luksFormat --type luks2 --batch-mode --verify-passphrase --hash $hash --key-size $keysize --iter-time $itertime --pbkdf argon2id --use-urandom $partition2 || failureCheck
                ;;
            none)
                # Best effort encryption here, should provide options for luks version and pbkdf in the future
                cryptsetup luksFormat --type luks2 --batch-mode --verify-passphrase --hash $hash --key-size $keysize --iter-time $itertime --pbkdf argon2id --use-urandom $partition2 || failureCheck
                ;;
            grub)
                # We need to use luks1 and pbkdf2 to maintain compatibility with grub here.
                # It should be possible to replace the grub EFI binary to add luks2 support, but for the time being I'm going to leave this as luks1.
                cryptsetup luksFormat --type luks1 --batch-mode --verify-passphrase --hash $hash --key-size $keysize --iter-time $itertime --pbkdf pbkdf2 --use-urandom $partition2 || failureCheck
                ;;
        esac

        echo -e "${YELLOW}Opening new encrypted container... ${NC}\n"
        cryptsetup luksOpen $partition2 void || failureCheck
    else
        pvcreate $partition2 || failureCheck
        echo -e "Creating volume group... \n"
        vgcreate void $partition2 || failureCheck
    fi

    if [ "$encryptionPrompt" == "Yes" ]; then
        echo -e "Creating volume group... \n"
        vgcreate void /dev/mapper/void || failureCheck
    fi

    echo -e "Creating volumes... \n"

    if [ "$swapPrompt" == "Yes" ]; then
        echo -e "Creating swap volume..."
        lvcreate --name swap -L $swapInput void || failureCheck
        mkswap /dev/void/swap || failureCheck
    fi

    if [ "$rootPrompt" == "full" ]; then
        echo -e "Creating full disk root volume..."
        lvcreate --name root -l 100%FREE void || failureCheck
    else
        echo -e "Creating $rootPrompt disk root volume..."
        lvcreate --name root -L $rootPrompt void || failureCheck
    fi

    if [ "$fsChoice" == "ext4" ]; then
        mkfs.ext4 /dev/void/root || failureCheck
    elif [ "$fsChoice" == "xfs" ]; then
        mkfs.xfs /dev/void/root || failureCheck
    fi

    if [ "$separateHomePossible" == "1" ]; then
        if [ "$homePrompt" == "Yes" ]; then
            if [ "$homeInput" == "full" ]; then
                lvcreate --name home -l 100%FREE void || failureCheck
            else
                lvcreate --name home -L $homeInput void || failureCheck
            fi

            if [ "$fsChoice" == "ext4" ]; then
                mkfs.ext4 /dev/void/home || failureCheck
            elif [ "$fsChoice" == "xfs" ]; then
                mkfs.xfs /dev/void/home || failureCheck
            fi

        fi
    fi

    echo -e "Mounting partitions... \n"
    commandFailure="Mounting partitions has failed."
    mount /dev/void/root /mnt || failureCheck
    for dir in dev proc sys run; do mkdir -p /mnt/$dir ; mount --rbind /$dir /mnt/$dir ; mount --make-rslave /mnt/$dir ; done || failureCheck

    case $bootloaderChoice in
        uki)
            mkdir -p /mnt/boot/efi || failureCheck
            mount $partition1 /mnt/boot/efi || failureCheck
            ;;
        efistub)
            mkdir -p /mnt/boot || failureCheck
            mount $partition1 /mnt/boot || failureCheck
            ;;
        grub)
            mkdir -p /mnt/boot/efi || failureCheck
            mount $partition1 /mnt/boot/efi
            ;;
    esac

    echo -e "Copying keys... \n"
    commandFailure="Copying XBPS keys has failed."
    mkdir -p /mnt/var/db/xbps/keys || failureCheck
    cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys || failureCheck

    echo -e "Installing base system... \n"
    commandFailure="Base system installation has failed."

    case $baseChoice in
        Custom)
            XBPS_ARCH=$ARCH xbps-install -Sy -R $installRepo -r /mnt $basesystem || failureCheck
            ;;
        base-container)
            XBPS_ARCH=$ARCH xbps-install -Sy -R $installRepo -r /mnt base-container $kernelChoice dosfstools ncurses libgcc bash file less man-pages mdocml pciutils usbutils dhcpcd kbd iproute2 iputils ethtool kmod acpid eudev lvm2 void-artwork || failureCheck

            case $fsChoice in

                xfs)
                    xbps-install -Sy -R $installRepo -r /mnt xfsprogs || failureCheck
                    ;;

                ext4)
                    xbps-install -Sy -R $installRepo -r /mnt e2fsprogs || failureCheck
                    ;;

                *)
                    failureCheck
                    ;;

            esac            
            ;;
        base-system)
            XBPS_ARCH=$ARCH xbps-install -Sy -R $installRepo -r /mnt base-system lvm2 || failureCheck

            # Ignore some packages provided by base-system and remove them to provide a choice.
            if [ $kernelChoice != "linux" ] && [ $kernelChoice != "Custom" ]; then
                echo "ignorepkg=linux" >> /mnt/etc/xbps.d/ignore.conf || failureCheck

                xbps-install -Sy -R $installRepo -r /mnt $kernelChoice || failureCheck

                xbps-remove -ROoy -r /mnt linux || failureCheck
            fi

            if [ $suChoice != "sudo" ]; then
                echo "ignorepkg=sudo" >> /mnt/etc/xbps.d/ignore.conf || failureCheck

                xbps-remove -ROoy -r /mnt sudo || failureCheck
            fi

            if [ "$installType" == "desktop" ] && [[ ! ${modulesChoice[@]} =~ "wifi-firmware" ]]; then
                echo "ignorepkg=wifi-firmware" >> /mnt/etc/xbps.d/ignore.conf || failureCheck
                echo "ignorepkg=iw" >> /mnt/etc/xbps.d/ignore.conf || failureCheck
                echo "ignorepkg=wpa_supplicant" >> /mnt/etc/xbps.d/ignore.conf || failureCheck

                xbps-remove -ROoy -r /mnt wifi-firmware iw wpa_supplicant || failureCheck
            fi
            ;;
    esac

    # The dkms package will install headers for 'linux' rather than '$kernelChoice' unless we create a virtual package here, and we do not need both.
    if [ "$kernelChoice" == "linux-lts" ]; then
        echo "virtualpkg=linux-headers:linux-lts-headers" >> /mnt/etc/xbps.d/headers.conf || failureCheck
    elif [ "$kernelChoice" == "linux-mainline" ]; then
        echo "virtualpkg=linux-headers:linux-mainline-headers" >> /mnt/etc/xbps.d/headers.conf || failureCheck
    fi

    case $bootloaderChoice in
        grub)
            echo -e "Installing grub... \n"
            commandFailure="Grub installation has failed."
            xbps-install -Sy -R $installRepo -r /mnt grub-x86_64-efi || failureCheck
            ;;
        efistub)
            echo -e "Installing efibootmgr... \n"
            commandFailure="efibootmgr installation has failed."
            xbps-install -Sy -R $installRepo -r /mnt efibootmgr || failureCheck
            ;;
        uki)
            echo -e "Installing efibootmgr and ukify... \n"
            commandFailure="efibootmgr and ukify installation has failed."
            xbps-install -Sy -R $installRepo -r /mnt efibootmgr ukify systemd-boot-efistub || failureCheck
            ;;
    esac

    if [ "$installRepo" != "https://repo-default.voidlinux.org/current" ] && [ "$installRepo" != "https://repo-default.voidlinux.org/current/musl" ]; then
        commandFailure="Repo configuration has failed."
        echo -e "Configuring mirror repo... \n"
        xmirror -s "$installRepo" -r /mnt || failureCheck
    fi

    commandFailure="$suChoice installation has failed."
    echo -e "Installing $suChoice... \n"
    if [ "$suChoice" == "sudo" ]; then
        xbps-install -Sy -R $installRepo -r /mnt sudo || failureCheck
    elif [ "$suChoice" == "doas" ]; then
        xbps-install -Sy -R $installRepo -r /mnt opendoas || failureCheck
    fi

    if [ "$encryptionPrompt" == "Yes" ]; then
        commandFailure="Cryptsetup installation has failed."
        echo -e "Installing cryptsetup... \n"
        xbps-install -Sy -R $installRepo -r /mnt cryptsetup || failureCheck
    fi

    echo -e "Base system installed... \n"

    echo -e "Configuring fstab... \n"
    commandFailure="Fstab configuration has failed."
    partVar=$(blkid -o value -s UUID $partition1)
    case $bootloaderChoice in
        grub)
            echo "UUID=$partVar     /boot/efi   vfat    defaults›   0   0" >> /mnt/etc/fstab || failureCheck
            ;;
        efistub)
            echo "UUID=$partVar     /boot       vfat    defaults    0   0" >> /mnt/etc/fstab || failureCheck
            ;;
        uki)
            echo "UUID=$partVar     /boot/efi   vfat    defaults    0   0" >> /mnt/etc/fstab || failureCheck
            ;;
    esac

    echo "/dev/void/root  /     $fsChoice     defaults              0       0" >> /mnt/etc/fstab || failureCheck

    if [ "$swapPrompt" == "Yes" ]; then
        echo "/dev/void/swap  swap  swap    defaults              0       0" >> /mnt/etc/fstab || failureCheck
    fi

    if [ "$homePrompt" == "Yes" ] && [ "$separateHomePossible" == "1" ]; then
        echo "/dev/void/home  /home $fsChoice     defaults              0       0" >> /mnt/etc/fstab || failureCheck
    fi

    case $bootloaderChoice in
        efistub)
            echo "Configuring dracut for efistub boot..."
            commandFailure="Dracut configuration has failed."
            echo 'hostonly="yes"' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck
            echo 'use_fstab="yes"' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck

            echo 'install_items+=" /etc/crypttab "' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck
            echo 'add_drivers+=" vfat nls_cp437 nls_iso8859_1 "' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck

            echo "Moving runit service for efistub boot..."
            commandFailure="Moving runit service has failed."
            mv /mnt/etc/runit/core-services/03-filesystems.sh{,.bak} || failureCheck

            echo "Configuring xbps for efistub boot..."
            commandFailure="efistub xbps configuration has failed."
            echo "noextract=/etc/runit/core-services/03-filesystems.sh" >> /mnt/etc/xbps.d/xbps.conf || failureCheck

            echo "Editing efibootmgr for efistub boot..."
            commandFailure="efibootmgr configuration has failed."
            sed -i -e 's/MODIFY_EFI_ENTRIES=0/MODIFY_EFI_ENTRIES=1/g' /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
            echo DISK="$diskInput" >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
            echo 'PART="1"' >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck

            # An empty BOOTX64.EFI file needs to exist at the default/fallback efi location to stop some motherboards from nuking our efistub boot entry
            mkdir -p /mnt/boot/EFI/BOOT || failureCheck
            touch /mnt/boot/EFI/BOOT/BOOTX64.EFI || failureCheck

            echo 'OPTIONS="loglevel=4 rd.lvm.vg=void"' >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck

            if [ "$acpi" == "false" ]; then
                commandFailure="Disabling ACPI has failed."
                echo -e "Disabling ACPI... \n"
                sed -i -e 's/OPTIONS="loglevel=4/OPTIONS="loglevel=4 acpi=off/g' /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
            fi
            ;;
        grub)
            if [ "$encryptionPrompt" == "Yes" ]; then
                commandFailure="Configuring grub for full disk encryption has failed."
                echo -e "Configuring grub for full disk encryption... \n"
                partVar=$(blkid -o value -s UUID $partition2)
                sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 rd.lvm.vg=void rd.luks.uuid='$partVar'"/g' /mnt/etc/default/grub || failureCheck
                echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub || failureCheck
            fi

            if [ "$acpi" == "false" ]; then
                commandFailure="Disabling ACPI has failed."
                echo -e "Disabling ACPI... \n"
                sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 acpi=off/g' /mnt/etc/default/grub || failureCheck
            fi
            ;;
        uki)
            commandFailure="Configuring UKI kernel parameters has failed."
            echo -e "Configuring kernel parameters... \n"
            if [ "$encryptionPrompt" == "Yes" ]; then
                partVar=$(blkid -o value -s UUID $partition2)
                echo "rd.luks.uuid=$partVar root=/dev/void/root rootfstype=$fsChoice rw loglevel=4" >> /mnt/root/kernelparams || failureCheck
            else
                echo "rd.lvm.vg=void root=/dev/void/root rootfstype=$fsChoice rw loglevel=4" >> /mnt/root/kernelparams || failureCheck
            fi

            if [ "$acpi" == "false" ]; then
                commandFailure="Disabling ACPI has failed."
                echo -e "Disabling ACPI... \n"
                sed -i -e 's/loglevel=4/loglevel=4 acpi=off' /mnt/root/kernelparams || failureCheck
            fi
            ;;
    esac

    if [ "$muslSelection" == "glibc" ]; then
        commandFailure="Locale configuration has failed."
        echo -e "Configuring locales... \n"
        echo $locale > /mnt/etc/locale.conf || failureCheck
        echo $libclocale >> /mnt/etc/default/libc-locales || failureCheck
    fi

    commandFailure="Hostname configuration has failed."
    echo -e "Setting hostname.. \n"
    echo $hostnameInput > /mnt/etc/hostname || failureCheck

    if [ "$installType" == "minimal" ]; then
        chrootFunction
    elif [ "$installType" == "desktop" ]; then

        commandFailure="Graphics driver installation has failed."

        for i in "${graphicsArray[@]}"
        do

            case $i in

                amd)
                    echo -e "Installing AMD graphics drivers... \n"
                    xbps-install -Sy -R $installRepo -r /mnt mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi mesa-vdpau || failureCheck
                    echo -e "AMD graphics drivers have been installed. \n"
                    ;;

                amd-32bit)
                    echo -e "Installing 32-bit AMD graphics drivers... \n"
                    xbps-install -Sy -R $installRepo -r /mnt void-repo-multilib || failureCheck
                    xmirror -s "$installRepo" -r /mnt || failureCheck
                    xbps-install -Sy -R $installRepo -r /mnt libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit mesa-dri-32bit || failureCheck
                    echo -e "32-bit AMD graphics drivers have been installed. \n"
                    ;;

                nvidia)
                    echo -e "Installing NVIDIA graphics drivers... \n"
                    xbps-install -Sy -R $installRepo -r /mnt void-repo-nonfree || failureCheck
                    xmirror -s "$installRepo" -r /mnt || failureCheck
                    xbps-install -Sy -R $installRepo -r /mnt nvidia || failureCheck

                    # Enabling mode setting for wayland compositors
                    if [ "$bootloaderChoice" == "grub" ]; then
                        sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4/GRUB_CMDLINE_DEFAULT="loglevel=4 nvidia_drm.modeset=1/g' /mnt/etc/default/grub || failureCheck 
                    elif [ "$bootloaderChoice" == "efistub" ]; then
                        sed -i -e 's/OPTIONS="loglevel=4/OPTIONS="loglevel=4 nvidia_drm.modeset=1/g' /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
                    fi

                    echo -e "NVIDIA graphics drivers have been installed. \n"
                    ;;

                nvidia-32bit)
                    echo -e "Installing 32-bit NVIDIA graphics drivers... \n"
                    xbps-install -Sy -R $installRepo -r /mnt void-repo-multilib-nonfree void-repo-multilib || failureCheck
                    xmirror -s "$installRepo" -r /mnt || failureCheck
                    xbps-install -Sy -R $installRepo -r /mnt nvidia-libs-32bit || failureCheck
                    echo -e "32-bit NVIDIA graphics drivers have been installed. \n"
                    ;;

                intel)
                    echo -e "Installing INTEL graphics drivers... \n"
                    xbps-install -Sy -R $installRepo -r /mnt mesa-dri vulkan-loader mesa-vulkan-intel intel-video-accel || failureCheck
                    echo -e "INTEL graphics drivers have been installed. \n"
                    ;;

                intel-32bit)
                    echo -e "Installing 32-bit INTEL graphics drivers... \n"
                    xbps-install -Sy -R $installRepo -r /mnt void-repo-multilib || failureCheck
                    xmirror -s "$installRepo" -r /mnt || failureCheck
                    xbps-install -Sy -R $installRepo -r /mnt libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit mesa-dri-32bit || failureCheck
                    echo -e "32-bit INTEL graphics drivers have been installed. \n"
                    ;;

                nvidia-nouveau)
                    echo -e "Installing NOUVEAU graphics drivers... \n"
                    xbps-install -Sy -R $installRepo -r /mnt mesa-dri mesa-nouveau-dri || failureCheck
                    echo -e "NOUVEAU graphics drivers have been installed. \n"
                    ;;

                nvidia-nouveau-32bit)
                    echo -e "Installing 32-bit NOUVEAU graphics drivers... \n"
                    xbps-install -Sy -R $installRepo -r /mnt void-repo-multilib || failureCheck
                    xmirror -s "$installRepo" -r /mnt || failureCheck
                    xbps-install -Sy -R $installRepo -r /mnt libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit mesa-dri-32bit mesa-nouveau-dri-32bit || failureCheck
                    echo -e "32-bit NOUVEAU graphics drivers have been installed. \n"
                    ;;

                *)
                    echo -e "Continuing without graphics drivers... \n"
                    ;;

            esac

        done

        if [ "$networkChoice" == "NetworkManager" ]; then
            commandFailure="NetworkManager installation has failed."
            echo -e "Installing NetworkManager... \n"
            xbps-install -Sy -R $installRepo -r /mnt NetworkManager || failureCheck
            chroot /mnt /bin/bash -c "ln -s /etc/sv/NetworkManager /var/service" || failureCheck
            echo -e "NetworkManager has been installed. \n"
        elif [ "$networkChoice" == "dhcpcd" ]; then
            chroot /mnt /bin/bash -c "ln -s /etc/sv/dhcpcd /var/service" || failureCheck
        fi

        commandFailure="Audio server installation has failed."
        if [ "$audioChoice" == "pipewire" ]; then
            echo -e "Installing pipewire... \n"
            xbps-install -Sy -R $installRepo -r /mnt pipewire alsa-pipewire wireplumber || failureCheck
            mkdir -p /mnt/etc/alsa/conf.d || failureCheck
            mkdir -p /mnt/etc/pipewire/pipewire.conf.d || failureCheck

            # This is now required to start pipewire and its session manager 'wireplumber' in an appropriate order, this should achieve a desireable result system-wide.
            echo 'context.exec = [ { path = "/usr/bin/wireplumber" args = "" } ]' > /mnt/etc/pipewire/pipewire.conf.d/10-wireplumber.conf || failureCheck

            echo -e "Pipewire has been installed. \n"
        elif [ "$audioChoice" == "pulseaudio" ]; then
            echo -e "Installing pulseaudio... \n"
            xbps-install -Sy -R $installRepo -r /mnt pulseaudio alsa-plugins-pulseaudio || failureCheck
            echo -e "Pulseaudio has been installed. \n"
        fi

        commandFailure="GUI installation has failed."

        case $desktopChoice in

            gnome)
                echo -e "Installing Gnome desktop environment... \n"
                xbps-install -Sy -R $installRepo -r /mnt gnome-core gnome-disk-utility gnome-console gnome-tweaks gnome-browser-connector gnome-text-editor xdg-user-dirs xorg-minimal xorg-video-drivers || failureCheck
                chroot /mnt /bin/bash -c "ln -s /etc/sv/gdm /var/service" || failureCheck
                echo -e "Gnome has been installed. \n"
                ;;

            kde)
                echo -e "Installing KDE desktop environment... \n"
                xbps-install -Sy -R $installRepo -r /mnt kde5 kde5-baseapps xdg-user-dirs xorg-minimal xorg-video-drivers || failureCheck
                chroot /mnt /bin/bash -c "ln -s /etc/sv/sddm /var/service" || failureCheck
                echo -e "KDE has been installed. \n"
                ;;

            xfce)
                echo -e "Installing XFCE desktop environment... \n"
                xbps-install -Sy -R $installRepo -r /mnt xfce4 lightdm lightdm-gtk3-greeter xorg-minimal xdg-user-dirs xorg-fonts xorg-video-drivers || failureCheck

                if [ "$networkChoice" == "NetworkManager" ]; then
                    xbps-install -Sy -R $installRepo -r /mnt network-manager-applet || failureCheck
                fi

                chroot /mnt /bin/bash -c "ln -s /etc/sv/lightdm /var/service" || failureCheck
                echo -e "XFCE has been installed. \n"
                ;;

            sway)
                echo -e "Installing Sway window manager... \n"
                xbps-install -Sy -R $installRepo -r /mnt sway elogind polkit polkit-elogind foot xorg-fonts || failureCheck

                if [ "$networkChoice" == "NetworkManager" ]; then
                    xbps-install -Sy -R $installRepo -r /mnt network-manager-applet || failureCheck
                fi

                chroot /mnt /bin/bash -c "ln -s /etc/sv/elogind /var/service && ln -s /etc/sv/polkitd /var/service" || failureCheck
                echo -e "Sway has been installed. \n"
                ;;

            swayfx)
                echo -e "Installing SwayFX window manager... \n"
                xbps-install -Sy -R $installRepo -r /mnt swayfx elogind polkit polkit-elogind foot xorg-fonts || failureCheck

                if [ "$networkChoice" == "NetworkManager" ]; then
                    xbps-install -Sy -R $installRepo -r /mnt network-manager-applet || failureCheck
                fi

                chroot /mnt /bin/bash -c "ln -s /etc/sv/elogind /var/service && ln -s /etc/sv/polkitd /var/service" || failureCheck
                echo -e "SwayFX has been installed. \n"
                ;;

            wayfire)
                echo -e "Installing Wayfire window manager... \n"
                xbps-install -Sy -R $installRepo -r /mnt wayfire elogind polkit polkit-elogind foot xorg-fonts || failureCheck

                if [ "$networkChoice" == "NetworkManager" ]; then
                    xbps-install -Sy -R $installRepo -r /mnt network-manager-applet || failureCheck
                fi

                # To ensure a consistent experience, I would rather provide foot with all wayland compositors. 
                # Modifying the default terminal setting so the user doesn't get stuck without a terminal is done post user setup by systemchroot.sh
                chroot /mnt /bin/bash -c "ln -s /etc/sv/elogind /var/service && ln -s /etc/sv/polkitd /var/service" || failureCheck
                echo -e "Wayfire has been installed. \n"
                ;;

            i3)
                echo -e "Installing i3wm... \n"
                xbps-install -Sy -R $installRepo -r /mnt xorg-minimal xinit xterm i3 xorg-fonts xorg-video-drivers || failureCheck

                if [ "$networkChoice" == "NetworkManager" ]; then
                    xbps-install -Sy -R $installRepo -r /mnt network-manager-applet || failureCheck
                fi

                echo -e "i3wm has been installed. \n"
                if [ "$i3prompt" == "Yes" ]; then
                    echo -e "Installing lightdm... \n"
                    xbps-install -Sy -R $installRepo -r /mnt lightdm lightdm-gtk3-greeter || failureCheck
                    chroot /mnt /bin/bash -c "ln -s /etc/sv/lightdm /var/service" || failureCheck
                    echo "lightdm has been installed."
                fi
                ;;

            *)
                echo -e "Continuing without GUI... \n"
                ;;

        esac

        clear

        echo -e "Desktop setup completed. \n"
        echo -e "The system will now chroot into the new installation for final setup... \n"
        sleep 1

        chrootFunction
    fi

}

# Passing some stuff over to the new install to be used by the secondary script
chrootFunction() {

    commandFailure="System chroot has failed."
    cp /etc/resolv.conf /mnt/etc/resolv.conf || failureCheck
    
    syschrootVarPairs=("bootloaderChoice $bootloaderChoice" \
    "suChoice $suChoice" \
    "timezonePrompt $timezonePrompt" \
    "encryptionPrompt $encryptionPrompt" \
    "diskInput $diskInput" \
    "createUser $createUser" \
    "desktopChoice $desktopChoice")

    for i in "${syschrootVarPairs[@]}"
    do
        set -- $i || failureCheck
        echo "$1='$2'" >> /mnt/tmp/installerOptions || failureCheck
    done

    cp -f $(pwd)/systemchroot.sh /mnt/tmp/systemchroot.sh || failureCheck
    chroot /mnt /bin/bash -c "/bin/bash /tmp/systemchroot.sh" || failureCheck

    postInstall

}

drawDialog() {

    commandFailure="Displaying dialog window has failed."
    dialog --stdout --cancel-label "Skip" --no-mouse --backtitle "https://github.com/kkrruumm/void-install-script" "$@"

}

checkModule() {

    # We need to make sure a few variables at minimum exist before the installer should accept it.
    # Past this, I'm going to leave verifying correctness to the author of the module.
    if grep "title="*"" "modules/$i" && ( grep "status=on" "modules/$i" || grep "status=off" "modules/$i" ) && ( grep "description="*"" "modules/$i" ) && ( grep "main()" "modules/$i" ); then
        return 0
    else
        # Skip found module file if its contents do not comply.
        return 1
    fi

}

failureCheck() {

    echo -e "${RED}$commandFailure${NC}"
    echo "Installation will not proceed."
    exit 1

}

diskCalculator() {

    diskOperand=$(echo $sizeInput | sed 's/G//g')
    diskFloat=$(echo $diskFloat - $diskOperand | bc)
    diskAvailable=$(echo $diskFloat - 0.5 | bc)
    diskAvailable+="G"

    if [ "$diskFloat" -lt 0 ]; then
        clear
        echo -e "${RED}Used disk space cannot exceed the maximum capacity of the chosen disk. Have you over-provisioned your disk? ${NC}\n"
        read -p "Press Enter to start disk configuration again." </dev/tty
        diskConfiguration
    fi

    return 0

}

partitionerOutput() {

    echo -e "Disk: $diskInput"
    echo -e "Disk size: $diskSize"
    echo -e "Available disk space: $diskAvailable \n"

    return 0

}

postInstall() {

    if [ -z "$modulesChoice" ]; then
        clear

        echo -e "${GREEN}Installation complete.${NC} \n"
        echo -e "Please remove installation media and reboot. \n"
        exit 0
    else
        commandFailure="Executing module has failed."
        for i in "${modulesChoice[@]}"
        do
            # Source and execute each module
            . "modules/$i"  || failureCheck
            main
        done

        clear

        echo -e "${GREEN}Installation complete.${NC} \n"
        echo -e "Please remove installation media and reboot. \n"
        exit 0
    fi

}

entry
