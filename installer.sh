#!/bin/bash

# echo -e 是用于在 Bash 脚本中输出文本的命令，其中 -e 选项用于启用对反斜杠转义字符的解释。
if [ "$USER" != root ]; then
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
    echo -e "正在加载隐藏的选项文件... \n"
    commandFailure="加载隐藏的选项文件失败。"
    . "$1" || failureCheck
fi

entry() {

    # 这段代码的作用是在安装程序扫描模块时，确保不会出现重复的模块项。
    # 它首先检查一个名为 modulesDialogArray 的变量是否已定义，如果已定义则将其取消定义，以防止后续操作中出现重复的模块。
    if [ -n "$modulesDialogArray" ]; then
        unset modulesDialogArray
    fi

    # 这段代码的作用是检查系统是否通过 UEFI 启动，如果系统是通过 BIOS 启动的，则会提示错误信息并执行相应的错误处理函数。
    if [ ! -e "/sys/firmware/efi" ]; then
        commandFailure="此脚本仅支持 UEFI 系统，但似乎本机器是通过 BIOS 启动的。"
        failureCheck
    fi

    # 这段代码的作用是自动检测系统使用的 C 标准库是 glibc 还是 musl，并根据结果设置变量 muslSelection。
    if ldd --version | grep GNU ; then
        muslSelection="glibc"
    else
        muslSelection="musl"
    fi

    if [ "$(uname -m)" != "x86_64" ]; then
        commandFailure="此安装脚本当前不支持该系统的 CPU 架构。"
        failureCheck
    fi

    # 这段代码的作用是检查当前目录下是否存在名为 systemchroot.sh 的脚本文件。
    # 如果文件不存在，则设置一个错误信息，并调用 failureCheck 函数处理错误。
    if [ ! -e "$(pwd)/systemchroot.sh" ]; then
        commandFailure="systemchroot脚本似乎缺失。这可能是因为它的名称不正确，或者它在 $(pwd) 中不存在。"
        failureCheck
    fi

    # 这段代码的作用是检查当前工作目录下是否存在名为 modules 的目录。
    # 如果目录不存在，则设置一个错误信息，并调用 failureCheck 函数处理错误。
    if [ ! -e "$(pwd)/modules" ]; then
        commandFailure="模块目录似乎缺失。它在 $(pwd) 中并不存在，可能是因为名称不正确。"
        failureCheck
    fi

    echo -e "正在测试网络连接...\n"

    # 注意我们的国内版才这样ping
    if ping -c 1 baidu.com &>/dev/null || ping -c 1 qq.com &>/dev/null ; then
        echo -e "网络已经正常运行。\n"
    else
        commandFailure="网络检测失败。请确保您的网络处于活动状态。"
        failureCheck
    fi

    echo -e "开始 HourglassOS 安装程序... \n"

    echo -e "正在获取安装程序的依赖项... \n"

    commandFailure="依赖项安装失败。"
    
    xbps-install -Suy xbps || failureCheck # 以防 ISO 中的 xbps 过时
    xbps-install -Suy dialog bc parted || failureCheck

    echo -e "正在创建 .dialogrc... \n"
    dialog --create-rc ~/.dialogrc
    # 我觉得 dialog 默认的蓝色背景有点刺眼，这里将它改成黑色。
    sed -i -e 's/screen_color = (CYAN,BLUE,ON)/screen_color = (BLACK,BLACK,ON)/g' ~/.dialogrc
    # 顺便调整一些其他设置...
    sed -i -e 's/title_color = (BLUE,WHITE,ON)/title_color = (BLACK,WHITE,ON)/g' ~/.dialogrc

    diskConfiguration

}

diskConfiguration() {

    # 先定义所有磁盘选项，让用户在修改磁盘前验证磁盘布局。如果发现有问题，用户可以返回重新选择。
    diskPrompt=$(lsblk -d -o NAME,SIZE -n -e7)
    diskReadout=$(lsblk -o NAME,SIZE,TYPE -e7)

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
 

    if drawDialog --begin 2 2 --title "磁盘详情" --infobox "$partOutput" 0 0 --and-widget --title "分区工具" --yesno "您想要创建一个交换分区吗？" 0 0 ; then
        swapPrompt="Yes"
        partOutput=$(partitionerOutput)
        
        swapInput=$(drawDialog --begin 2 2 --title "磁盘详情" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "分区工具" --inputbox "您想要多大的交换分区？\n（例如：'4G')" 0 0)

        sizeInput=$swapInput
        diskCalculator
        partOutput=$(partitionerOutput)
    fi


    rootPrompt=$(drawDialog --begin 2 2 --title "磁盘详情" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "分区工具" --inputbox "如果您希望限制根文件系统的大小（例如为了创建单独的 /home 分区），请在此输入一个值，例如 '50G'。\n\n否则，如果您希望根分区占用整个磁盘空间，请输入 'full'。" 0 0)
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



    if drawDialog --title "加密" --yesno "是否对本次安装进行加密？" 0 0 ; then
        encryptionPrompt="Yes"
        if drawDialog --title "擦除磁盘" --yesno "您是否希望在设置前安全擦除所选磁盘？\n\n根据您选择的擦除次数，这个过程可能会非常耗时。" 0 0 ; then
            wipePrompt="Yes"
            passInput=$(drawDialog --title "擦除磁盘" --inputbox "您希望对该磁盘进行几次擦除？\n\n合理的次数包括1-3次。次数越多，耗时越长。" 0 0)
        else
            wipePrompt="No"
            passInput=0
        fi
    else
        encryptionPrompt="No"
    fi

    if [ -z "$basesystem" ]; then
        baseChoice=$(drawDialog --no-cancel --title "基础系统元包选择" --menu "如果不确定，请选择 'base-system'" 0 0 0 "base-system" "- 传统基础系统包" "base-container" "- 面向容器和chroots的最小化基础系统包")
    else
        baseChoice="Custom"
    fi


    fsChoice=$(drawDialog --no-cancel --title "文件系统选择" --menu "如果不确定，请选择 'ext4'" 0 0 0 "ext4" "" "xfs" "")

    suChoice=$(drawDialog --no-cancel --title "超级用户工具选择" --menu "如果不确定，请选择 'sudo'" 0 0 0 "sudo" "" "doas" "" "none" "")

    if [ -z "$basesystem" ]; then
        kernelChoice=$(drawDialog --no-cancel --title "内核选择" --menu "如果不确定，请选择 'linux'" 0 0 0 "linux" "- 常规 Void 内核" "linux-lts" "- 老版本 LTS 内核" "linux-mainline" "- 最新前沿内核")
    else
        kernelChoice="Custom"
    fi

    bootloaderChoice=$(drawDialog --no-cancel --title "引导加载程序选择" --menu "如果不确定，请选择 'grub'" 0 0 0 "grub" "- 传统引导加载程序" "efistub" "- 直接引导内核" "uki" "- 统一内核镜像（实验性）" "none" "- 不安装引导加载程序（高级选项）")

    hostnameInput=$(drawDialog --no-cancel --title "系统主机名" --inputbox "设置您的系统主机名。" 0 0)

    createUser=$(drawDialog --title "创建用户" --inputbox "您希望您的用户名是什么？\n\n如果您不想设置用户，请选择 '跳过'\n\n稍后您将被要求设置密码。" 0 0)



    # Most of this timezone section is taken from the normal Void installer.
    areas=(Africa America Antarctica Arctic Asia Atlantic Australia Europe Indian Pacific)

    # 使用 drawDialog 显示一个对话框，供用户选择一个大区域（例如：美洲、亚洲等）。
    # 这个 if 语句执行时，用户可以从显示的菜单中选择他们所在的区域。如果选择成功，变量 area 将保存所选的区域。
    # `IFS='|'` 设置了内部字段分隔符，使多个选项之间用竖线分隔。`drawDialog` 是一个函数，它展示了一个带有标题和菜单的对话框。
    if area=$(IFS='|'; drawDialog --title "设置时区" --menu "" 0 0 0 $(printf '%s||' "${areas[@]}")) ; then
        # 如果用户选择了一个区域，接下来会读取该区域下的具体时区。
        # `find /usr/share/zoneinfo/$area` 查找该区域下的所有时区文件，并将它们按字母顺序排序。
        # 使用 `-printf '%P\n'` 仅输出相对路径，而不是完整路径。`sort` 用来对输出结果进行排序。
        # 结果保存到 `locations` 数组中，供下一个对话框使用。
        read -a locations -d '\n' < <(find /usr/share/zoneinfo/$area -type f -printf '%P\n' | sort) || echo "忽略退出代码"

        # 继续展示一个对话框，供用户选择具体的时区位置。
        # 例如，用户如果选择了 "美洲"，接下来可以选择具体的城市或时区（如纽约、洛杉矶等）。
        # 此时用户选择的时区将存储在 `location` 变量中。
        location=$(IFS='|'; drawDialog --no-cancel --title "设置时区" --menu "" 0 0 0 $(printf '%s||' "${locations[@]//_/ }"))
    fi

    # 将用户选择的时区名中的空格替换为下划线。`tr ' ' '_'` 用于将空格替换为下划线。
    # 这一步是为了确保时区名称的格式正确，例如 "Los_Angeles" 而不是 "Los Angeles"。
    location=$(echo $location | tr ' ' '_')

    # 拼接最终的时区字符串，将 `area`（例如 "America"）和 `location`（例如 "New_York"）组合成完整的时区路径。
    # 最终的结果可能是 "America/New_York" 这样的格式，并存储在 `timezonePrompt` 变量中，供后续使用。
    timezonePrompt="$area/$location"


    # 这一行也来自于普通的 Void 安装程序。
    localeList=$(grep -E '\.UTF-8' /etc/default/libc-locales | awk '{print $1}' | sed -e 's/^#//')

    for i in $localeList
    do
        # 我们在这里不需要指定项，只需要一个标签并将其打印到标准输出即可
        tmp+=("$i" $(printf '\u200b')) # 使用一个零宽度的 Unicode 字符作为项目
    done

    localeChoice=$(drawDialog --no-cancel --title "语言环境选择" --menu "请选择您的系统语言环境。" 0 0 0 ${tmp[@]})

    locale="LANG=$localeChoice"
    libclocale="$localeChoice UTF-8"

    if drawDialog --title "镜像源设置" --yesno "您想要设置您的软件源镜像吗？" 0 0 ; then
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



    # installType=$(drawDialog --no-cancel --title "Profile Choice" --menu "Choose your installation profile:" 0 0 0 "minimal" " - Installs base system only, dhcpcd included for networking." "desktop" "- Provides extra optional install choices.")
    installType=$(drawDialog --no-cancel --title "安装配置选择" --menu "请选择您的安装配置：" 0 0 0 "minimal" " - 仅安装基础系统，包含用于网络的 dhcpcd。" "desktop" "- 提供额外的可选安装选项。")
    



    # 额外安装选项
    if [ "$installType" == "desktop" ]; then

        if [ "$muslSelection" == "glibc" ]; then
            graphicsChoice=$(drawDialog --title '图形驱动程序' --checklist '选择图形驱动程序: ' 0 0 0 'intel' '' 'off' 'intel-32bit' '' 'off' 'amd' '' 'off' 'amd-32bit' '' 'off' 'nvidia' '- 专有驱动程序' 'off' 'nvidia-32bit' '' 'off' 'nvidia-nouveau' '- Nvidia Nouveau 驱动（实验性）' 'off' 'nvidia-nouveau-32bit' '' 'off')
        elif [ "$muslSelection" == "musl" ]; then
            graphicsChoice=$(drawDialog --title '图形驱动程序' --checklist '选择图形驱动程序: ' 0 0 0 'intel' '' 'off' 'amd' '' 'off' 'nvidia-nouveau' '- Nvidia Nouveau 驱动（实验性）' 'off') 
        fi

        if [ ! -z "$graphicsChoice" ]; then
            IFS=" " read -r -a graphicsArray <<< "$graphicsChoice"
        fi

        networkChoice=$(drawDialog --title "网络" --menu "如果不确定，请选择 'NetworkManager'\n\n如果想跳过，请选择 '跳过'。" 0 0 0 "NetworkManager" "" "dhcpcd" "")

        audioChoice=$(drawDialog --title "音频服务" --menu "如果不确定，推荐选择 'pipewire'。\n\n如果想跳过，请选择 '跳过'。" 0 0 0 "pipewire" "" "pulseaudio" "")

        desktopChoice=$(drawDialog --title "桌面环境" --menu "如果想跳过，请选择 '跳过'。" 0 0 0 "gnome" "" "kde" "" "xfce" "" "sway" "" "swayfx" "" "wayfire" "" "i3" "")

        case $desktopChoice in
            sway)
                drawDialog --msgbox "Sway 需要在登录时手动启动。您可以在新系统中登录后输入 'dbus-run-session sway' 启动。" 0 0
                ;;

            swayfx)
                drawDialog --msgbox "SwayFX 需要在登录时手动启动。您可以在新系统中登录后输入 'dbus-run-session sway' 启动。" 0 0
                ;;

            wayfire)
                drawDialog --msgbox "Wayfire 需要在登录时手动启动。您可以在新系统中登录后输入 'dbus-run-session wayfire' 启动。" 0 0
                ;;

            i3)
                if drawDialog --title "" --yesno "是否要与 i3 一起安装 lightdm?" 0 0 ; then
                    i3prompt="Yes"
                fi
                ;;
        esac

        # Extras
        read -a modulesList -d '\n' < <(ls modules/ | sort)
        commandFailure="导入模块失败。"
        for i in "${modulesList[@]}"
        do
            if [ -e "modules/$i" ] && checkModule ; then
                . "modules/$i" || failureCheck
                modulesDialogArray+=("'$title' '$description' '$status'")
            fi
        done

        # Using sh here as a simple solution to it misbehaving when ran normally
        # 这里使用 sh -c 是为了在一个新的 sh 进程中执行命令。这样做的好处是确保命令能够在独立的 shell 环境中运行，避免影响到当前脚本的环境变量或其它上下文。
        modulesChoice=( $(sh -c "dialog --stdout --title 'Extra Options' --no-mouse --backtitle "https://github.com/kkrruumm/void-install-script" --checklist 'Enable or disable extra install options: ' 0 0 0 $(echo "${modulesDialogArray[@]}")") )
        # modulesChoice=( $(sh -c "dialog --stdout --title '额外选项' --no-mouse --backtitle 'https://github.com/kkrruumm/void-install-script' --checklist '启用或禁用额外的安装选项：' 0 0 0 $(echo \"${modulesDialogArray[@]}\")") )

            confirmInstallationOptions
        elif [ "$installType" == "minimal" ]; then
            confirmInstallationOptions
        fi

}

confirmInstallationOptions() {  

    drawDialog --yes-label "安装" --no-label "退出" --extra-button --extra-label "重新开始" --title "Hourglass OS 安装选项总结" --yesno "    选择 '安装' 将使用以下选项进行安装。 \n\n
    基础系统: $baseChoice \n
    软件源镜像: $installRepo \n
    引导加载程序: $bootloaderChoice \n
    内核: $kernelChoice \n
    安装磁盘: $diskInput \n
    加密: $encryptionPrompt \n
    擦除磁盘: $wipePrompt \n
    擦除次数: $passInput \n
    文件系统: $fsChoice \n
    超级用户工具选择: $suChoice \n
    创建交换分区: $swapPrompt \n
    交换分区大小: $swapInput \n
    根分区大小: $rootPrompt \n
    创建单独的/home分区: $homePrompt \n
    /home分区大小: $homeInput \n
    主机名: $hostnameInput \n
    时区: $timezonePrompt \n
    用户: $createUser \n
    安装类型: $installType \n\n
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
            # commandFailure="Invalid confirm settings exit code"
            commandFailure="程序收到了一个未预期的或无效的退出码（exit code）"
            failureCheck
            ;;
    esac
    
}



# Define a helper function for installing services
install_service() {
    service_name=$1
    chroot /mnt /bin/bash -c "ln -s /etc/sv/$service_name /var/service" || failureCheck
}

# Define desktop installation logic
install_desktop_environment() {
    echo -e "Installing $1 desktop environment... \n"
    xbps-install -Sy -R $installRepo -r /mnt $2 || failureCheck
    install_service $3
    echo -e "$1 has been installed. \n"
}


install() {


    # 如果选择了擦除磁盘，执行擦除操作
    if [ "$wipePrompt" == "Yes" ]; then
    commandFailure="磁盘擦除失败。"
    clear
    echo -e "开始对磁盘进行安全擦除，共 $passInput 次擦除，并将数据覆盖为零。\n"
    shred --verbose --random-source=/dev/urandom -n$passInput --zero $diskInput || failureCheck
    fi

    clear
    echo "开始磁盘分区..."

        # 检查是否存在卷组，如果存在则删除
    deviceVG=$(pvdisplay $diskInput* | grep "VG Name" | while read c1 c2; do echo $c2; done | sed 's/Name//g')

    if [ -z $deviceVG ]; then
        echo -e "未找到现有的逻辑卷卷组，不需要执行任何操作...\n"
    else
        commandFailure="逻辑卷卷组删除失败。"
        echo -e "找到现有的逻辑卷卷组...\n"
        echo -e "正在清除现有的逻辑卷卷组...\n"
        
        vgchange -a n $deviceVG || failureCheck
        vgremove $deviceVG || failureCheck
    fi

    # 创建 EFI 启动分区和数据分区
    commandFailure="磁盘分区失败。"
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

    # 格式化 EFI 分区
    mkfs.vfat $partition1 || failureCheck

    clear2

    # 配置加密，如果选择了加密选项
    if [ "$encryptionPrompt" == "Yes" ]; then
        echo "配置加密安装的分区..."

        # 使用默认或指定的加密参数
        if [ -z "$hash" ]; then
            hash="sha512"
        fi
        if [ -z "$keysize" ]; then
            keysize="512"
        fi
        if [ -z "$itertime" ]; then
            itertime="10000"
        fi

        echo -e "${YELLOW}请输入您的加密密码短语。${NC}\n"

        # 配置加密，根据引导加载程序选择不同的加密方式
        case $bootloaderChoice in
            uki|efistub|none)
                cryptsetup luksFormat --type luks2 --batch-mode --verify-passphrase --hash $hash --key-size $keysize --iter-time $itertime --pbkdf argon2id --use-urandom $partition2 || failureCheck
                cryptsetup luksOpen --type luks2 $partition2 cryptpart || failureCheck
                ;;
            grub)
                cryptsetup luksFormat --type luks1 --batch-mode --verify-passphrase --hash $hash --key-size $keysize --iter-time $itertime --pbkdf pbkdf2 --use-urandom $partition2 || failureCheck
                cryptsetup luksOpen --type luks1 $partition2 cryptpart || failureCheck
                ;;
        esac

        partition2="/dev/mapper/cryptpart"  # 加密后直接使用加密容器
    fi

    # 如果未选择加密，直接使用物理分区
    if [ "$encryptionPrompt" != "Yes" ]; then
        echo -e "直接使用分区 $partition2 ... \n"
    fi

    # 格式化根分区
    if [ "$fsChoice" == "ext4" ]; then
        mkfs.ext4 $partition2 || failureCheck
    elif [ "$fsChoice" == "xfs" ]; then
        mkfs.xfs $partition2 || failureCheck
    fi

    # 如果需要交换分区，创建并启用
    if [ "$swapPrompt" == "Yes" ]; then
        echo -e "正在创建交换分区..."
        fallocate -l $swapInput /swapfile || failureCheck
        chmod 600 /swapfile
        mkswap /swapfile || failureCheck
        swapon /swapfile || failureCheck
    fi

    # 如果需要单独的 /home 分区，可以在这里创建
    if [ "$separateHomePossible" == "1" ] && [ "$homePrompt" == "Yes" ]; then
        echo -e "正在创建 /home 分区..."
        parted $diskInput mkpart primary 100M 100% --script || failureCheck
        mkfs.$fsChoice $partition2 || failureCheck
    fi

    echo -e "正在挂载分区...\n"
    commandFailure="挂载分区失败。"
    mount $partition2 /mnt || failureCheck  # 挂载根分区
    for dir in dev proc sys run; do 
        mkdir -p /mnt/$dir
        mount --rbind /$dir /mnt/$dir
        mount --make-rslave /mnt/$dir
    done || failureCheck

    # 根据引导加载程序选择挂载 EFI 分区
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
            mount $partition1 /mnt/boot/efi || failureCheck
            ;;
    esac

    # 复制 XBPS 密钥
    echo -e "正在复制密钥...\n"
    commandFailure="复制 XBPS 密钥失败。"
    mkdir -p /mnt/var/db/xbps/keys || failureCheck
    cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys || failureCheck

    # 安装基础系统
    echo -e "正在安装基础系统...\n"
    commandFailure="基础系统安装失败。"

    case $baseChoice in
        Custom)
            XBPS_ARCH=$ARCH xbps-install -Sy -R $installRepo -r /mnt $basesystem || failureCheck
            ;;
        base-container)
            XBPS_ARCH=$ARCH xbps-install -Sy -R $installRepo -r /mnt base-container $kernelChoice dosfstools ncurses libgcc bash file less man-pages mdocml pciutils usbutils dhcpcd kbd iproute2 iputils ethtool kmod acpid eudev void-artwork || failureCheck

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
            XBPS_ARCH=$ARCH xbps-install -Sy -R $installRepo -r /mnt base-system || failureCheck  # 删除 lvm2

            # 如果选择的 kernel 并非默认的 linux，处理 kernel 的替换
            if [ $kernelChoice != "linux" ] && [ $kernelChoice != "Custom" ]; then
                echo "ignorepkg=linux" >> /mnt/etc/xbps.d/ignore.conf || failureCheck
                xbps-install -Sy -R $installRepo -r /mnt $kernelChoice || failureCheck
                xbps-remove -ROoy -r /mnt linux || failureCheck
            fi

            # 处理 su 工具的选择
            if [ $suChoice != "sudo" ]; then
                echo "ignorepkg=sudo" >> /mnt/etc/xbps.d/ignore.conf || failureCheck
                xbps-remove -ROoy -r /mnt sudo || failureCheck
            fi

            # 如果是桌面安装并且不需要 wifi-firmware，移除相关包
            if [ "$installType" == "desktop" ] && [[ ! ${modulesChoice[@]} =~ "wifi-firmware" ]]; then
                echo "ignorepkg=wifi-firmware" >> /mnt/etc/xbps.d/ignore.conf || failureCheck
                echo "ignorepkg=iw" >> /mnt/etc/xbps.d/ignore.conf || failureCheck
                echo "ignorepkg=wpa_supplicant" >> /mnt/etc/xbps.d/ignore.conf || failureCheck

                xbps-remove -ROoy -r /mnt wifi-firmware iw wpa_supplicant || failureCheck
            fi
            ;;
    esac

    # dkms 包将安装 'linux' 的头文件，而不是 '$kernelChoice'，除非我们在这里创建一个虚拟包，而且我们不需要两者。
    if [ "$kernelChoice" == "linux-lts" ]; then
        echo "virtualpkg=linux-headers:linux-lts-headers" >> /mnt/etc/xbps.d/headers.conf || failureCheck
    elif [ "$kernelChoice" == "linux-mainline" ]; then
        echo "virtualpkg=linux-headers:linux-mainline-headers" >> /mnt/etc/xbps.d/headers.conf || failureCheck
    fi

    case $bootloaderChoice in
        grub)
            echo -e "正在安装 grub... \n"
            commandFailure="Grub 安装失败。"
            xbps-install -Sy -R $installRepo -r /mnt grub-x86_64-efi || failureCheck
            ;;
        efistub)
            echo -e "正在安装 efibootmgr... \n"
            commandFailure="efibootmgr 安装失败。"
            xbps-install -Sy -R $installRepo -r /mnt efibootmgr || failureCheck
            ;;
        uki)
            echo -e "正在安装 efibootmgr 和 ukify... \n"
            commandFailure="efibootmgr 和 ukify 安装失败。"
            xbps-install -Sy -R $installRepo -r /mnt efibootmgr ukify systemd-boot-efistub || failureCheck
            ;;
    esac


    if [ "$installRepo" != "https://repo-default.voidlinux.org/current" ] && [ "$installRepo" != "https://repo-default.voidlinux.org/current/musl" ]; then
        commandFailure="仓库配置失败。"
        echo -e "正在配置镜像仓库... \n"
        xmirror -s "$installRepo" -r /mnt || failureCheck
    fi


    commandFailure="$suChoice 安装失败。"
    echo -e "正在安装 $suChoice... \n"
    if [ "$suChoice" == "sudo" ]; then
        xbps-install -Sy -R $installRepo -r /mnt sudo || failureCheck
    elif [ "$suChoice" == "doas" ]; then
        xbps-install -Sy -R $installRepo -r /mnt opendoas || failureCheck
    fi

    if [ "$encryptionPrompt" == "Yes" ]; then
        commandFailure="Cryptsetup 安装失败。"
        echo -e "正在安装 cryptsetup... \n"
        xbps-install -Sy -R $installRepo -r /mnt cryptsetup || failureCheck
    fi


    echo -e "基础系统已安装... \n"

    echo -e "正在配置 fstab... \n"
    commandFailure="Fstab 配置失败。"
    partVar=$(blkid -o value -s UUID $partition1)
    case $bootloaderChoice in
        grub)
            echo "UUID=$partVar     /boot/efi   vfat    defaults    0   0" >> /mnt/etc/fstab || failureCheck
            ;;
        efistub)
            echo "UUID=$partVar     /boot       vfat    defaults    0   0" >> /mnt/etc/fstab || failureCheck
            ;;
        uki)
            echo "UUID=$partVar     /boot/efi   vfat    defaults    0   0" >> /mnt/etc/fstab || failureCheck
            ;;
    esac

    # 修改 fstab，使用直接分区路径
    echo "$partition2  /     $fsChoice     defaults              0       0" >> /mnt/etc/fstab || failureCheck

    if [ "$swapPrompt" == "Yes" ]; then
        echo "$partition2  swap  swap    defaults              0       0" >> /mnt/etc/fstab || failureCheck
    fi

    if [ "$homePrompt" == "Yes" ] && [ "$separateHomePossible" == "1" ]; then
        echo "$partition2  /home $fsChoice     defaults              0       0" >> /mnt/etc/fstab || failureCheck
    fi

    # 配置引导加载程序
    case $bootloaderChoice in
        efistub)
            echo "正在为 efistub 引导配置 dracut..."
            commandFailure="Dracut 配置失败。"
            echo 'hostonly="yes"' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck
            echo 'use_fstab="yes"' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck
            echo 'install_items+=" /etc/crypttab "' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck
            echo 'add_drivers+=" vfat nls_cp437 nls_iso8859_1 "' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck

            echo "正在移动 efistub 引导的 runit 服务..."
            commandFailure="移动 runit 服务失败。"
            mv /mnt/etc/runit/core-services/03-filesystems.sh{,.bak} || failureCheck

            echo "正在为 efistub 引导配置 xbps..."
            commandFailure="efistub xbps 配置失败。"
            echo "noextract=/etc/runit/core-services/03-filesystems.sh" >> /mnt/etc/xbps.d/xbps.conf || failureCheck

            echo "正在编辑 efibootmgr 以适应 efistub 引导..."
            commandFailure="efibootmgr 配置失败。"
            sed -i -e 's/MODIFY_EFI_ENTRIES=0/MODIFY_EFI_ENTRIES=1/g' /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
            echo DISK="$diskInput" >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
            echo 'PART="1"' >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck

            # 创建空的 BOOTX64.EFI 文件
            mkdir -p /mnt/boot/EFI/BOOT || failureCheck
            touch /mnt/boot/EFI/BOOT/BOOTX64.EFI || failureCheck

            echo 'OPTIONS="loglevel=4"' >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck

            if [ "$acpi" == "false" ]; then
                commandFailure="Disabling ACPI has failed."
                echo -e "Disabling ACPI... \n"
                sed -i -e 's/OPTIONS="loglevel=4/OPTIONS="loglevel=4 acpi=off/g' /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
            fi
            ;;
        grub)
            if [ "$encryptionPrompt" == "Yes" ]; then
                commandFailure="配置 grub 以支持全盘加密失败。"
                echo -e "正在为全盘加密配置 grub... \n"
                partVar=$(blkid -o value -s UUID $partition2)
                sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 rd.luks.uuid='$partVar'"/g' /mnt/etc/default/grub || failureCheck
                echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub || failureCheck
            fi

            if [ "$acpi" == "false" ]; then
                commandFailure="禁用 ACPI 失败。"
                echo -e "正在禁用 ACPI... \n"
                sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 acpi=off/g' /mnt/etc/default/grub || failureCheck
            fi
            ;;
        uki)
            commandFailure="配置 UKI 内核参数失败。"
            echo -e "正在配置内核参数... \n"
            if [ "$encryptionPrompt" == "Yes" ]; then
                partVar=$(blkid -o value -s UUID $partition2)
                echo "rd.luks.uuid=$partVar root=$partition2 rootfstype=$fsChoice rw loglevel=4" >> /mnt/root/kernelparams || failureCheck
            else
                echo "root=$partition2 rootfstype=$fsChoice rw loglevel=4" >> /mnt/root/kernelparams || failureCheck
            fi

            if [ "$acpi" == "false" ]; then
                commandFailure="Disabling ACPI has failed."
                echo -e "Disabling ACPI... \n"
                sed -i -e 's/loglevel=4/loglevel=4 acpi=off/g' /mnt/root/kernelparams || failureCheck
            fi
            ;;
    esac


    if [ "$muslSelection" == "glibc" ]; then
        commandFailure="区域设置配置失败。"
        echo -e "正在配置区域设置... \n"
        echo $locale > /mnt/etc/locale.conf || failureCheck
        echo $libclocale >> /mnt/etc/default/libc-locales || failureCheck
    fi

    commandFailure="主机名配置失败。"
    echo -e "正在设置主机名... \n"
    echo $hostnameInput > /mnt/etc/hostname || failureCheck
    
    if [ "$installType" == "minimal" ]; then
        chrootFunction
    elif [ "$installType" == "desktop" ];then

        commandFailure="图形驱动程序安装失败。"

        # 刷新仓库配置一次，避免在每个 case 中重复运行
        echo -e "正在刷新仓库配置... \n"
        xmirror -s "$installRepo" -r /mnt || failureCheck

        # 统一配置 multilib 和 nonfree 仓库（仅在需要时）
        if [[ "${graphicsArray[@]}" =~ "32bit" ]]; then
            xbps-install -Sy -R $installRepo -r /mnt void-repo-multilib || failureCheck
            if [[ "${graphicsArray[@]}" =~ "nvidia" ]]; then
                xbps-install -Sy -R $installRepo -r /mnt void-repo-multilib-nonfree || failureCheck
            fi
        fi

        if [[ "${graphicsArray[@]}" =~ "nvidia" ]]; then
            xbps-install -Sy -R $installRepo -r /mnt void-repo-nonfree || failureCheck
        fi

        for i in "${graphicsArray[@]}"
        do
            case $i in
                amd)
                    echo -e "正在安装 AMD 图形驱动... \n"
                    xbps-install -Sy -R $installRepo -r /mnt mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi mesa-vdpau || failureCheck
                    echo -e "AMD 图形驱动安装完成。 \n"
                    ;;
                amd-32bit)
                    echo -e "正在安装 32 位 AMD 图形驱动... \n"
                    xbps-install -Sy -R $installRepo -r /mnt libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit mesa-dri-32bit || failureCheck
                    echo -e "32 位 AMD 图形驱动安装完成。 \n"
                    ;;
                nvidia)
                    echo -e "正在安装 NVIDIA 图形驱动... \n"
                    xbps-install -Sy -R $installRepo -r /mnt nvidia || failureCheck
                    if [ "$bootloaderChoice" == "grub" ]; then
                        sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4/GRUB_CMDLINE_DEFAULT="loglevel=4 nvidia_drm.modeset=1/g' /mnt/etc/default/grub || failureCheck 
                    elif [ "$bootloaderChoice" == "efistub" ]; then
                        sed -i -e 's/OPTIONS="loglevel=4/OPTIONS="loglevel=4 nvidia_drm.modeset=1/g' /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
                    fi
                    echo -e "NVIDIA 图形驱动安装完成。 \n"
                    ;;
                nvidia-32bit)
                    echo -e "正在安装 32 位 NVIDIA 图形驱动... \n"
                    xbps-install -Sy -R $installRepo -r /mnt nvidia-libs-32bit || failureCheck
                    echo -e "32 位 NVIDIA 图形驱动安装完成。 \n"
                    ;;
                intel)
                    echo -e "正在安装 Intel 图形驱动... \n"
                    xbps-install -Sy -R $installRepo -r /mnt mesa-dri vulkan-loader mesa-vulkan-intel intel-video-accel || failureCheck
                    echo -e "Intel 图形驱动安装完成。 \n"
                    ;;
                intel-32bit)
                    echo -e "正在安装 32 位 Intel 图形驱动... \n"
                    xbps-install -Sy -R $installRepo -r /mnt libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit mesa-dri-32bit || failureCheck
                    echo -e "32 位 Intel 图形驱动安装完成。 \n"
                    ;;
                nvidia-nouveau)
                    echo -e "正在安装 Nouveau 图形驱动... \n"
                    xbps-install -Sy -R $installRepo -r /mnt mesa-dri mesa-nouveau-dri || failureCheck
                    echo -e "Nouveau 图形驱动安装完成。 \n"
                    ;;
                nvidia-nouveau-32bit)
                    echo -e "正在安装 32 位 Nouveau 图形驱动... \n"
                    xbps-install -Sy -R $installRepo -r /mnt mesa-dri-32bit mesa-nouveau-dri-32bit || failureCheck
                    echo -e "32 位 Nouveau 图形驱动安装完成。 \n"
                    ;;
                *)
                    echo -e "继续安装，没有图形驱动... \n"
                    ;;
            esac
        done
    fi

    if [ "$networkChoice" == "NetworkManager" ]; then
        commandFailure="NetworkManager 安装失败。"
        echo -e "正在安装 NetworkManager... \n"
        xbps-install -Sy -R $installRepo -r /mnt NetworkManager || failureCheck
        chroot /mnt /bin/bash -c "ln -s /etc/sv/NetworkManager /var/service" || failureCheck
        echo -e "NetworkManager 已安装。 \n"
    elif [ "$networkChoice" == "dhcpcd" ]; then
        commandFailure="dhcpcd 安装失败。"
        echo -e "正在安装 dhcpcd... \n"
        xbps-install -Sy -R $installRepo -r /mnt dhcpcd || failureCheck
        chroot /mnt /bin/bash -c "ln -s /etc/sv/dhcpcd /var/service" || failureCheck
        echo -e "dhcpcd 已安装。 \n"
    fi

    commandFailure="音频服务器安装失败。"
    if [ "$audioChoice" == "pipewire" ]; then
        echo -e "正在安装 Pipewire... \n"
        xbps-install -Sy -R $installRepo -r /mnt pipewire alsa-pipewire wireplumber || failureCheck
        mkdir -p /mnt/etc/alsa/conf.d || failureCheck
        mkdir -p /mnt/etc/pipewire/pipewire.conf.d || failureCheck

        # 现在需要以合适的顺序启动 pipewire 及其会话管理器 'wireplumber'，以实现系统范围内的理想结果。
        echo 'context.exec = [ { path = "/usr/bin/wireplumber" args = "" } ]' > /mnt/etc/pipewire/pipewire.conf.d/10-wireplumber.conf || failureCheck
        echo -e "Pipewire 已安装。 \n"
    elif [ "$audioChoice" == "pulseaudio" ]; then
        echo -e "正在安装 Pulseaudio... \n"
        xbps-install -Sy -R $installRepo -r /mnt pulseaudio alsa-plugins-pulseaudio || failureCheck
        echo -e "Pulseaudio 已安装。 \n"
    fi


    case $desktopChoice in
        gnome)
            install_desktop_environment "Gnome" "gnome-core gnome-disk-utility gnome-console gnome-tweaks gnome-browser-connector gnome-text-editor xdg-user-dirs xorg-minimal xorg-video-drivers" "gdm"
            ;;
        
        kde)
            install_desktop_environment "KDE" "kde5 kde5-baseapps xdg-user-dirs xorg-minimal xorg-video-drivers" "sddm"
            ;;
        
        xfce)
            install_desktop_environment "XFCE" "xfce4 lightdm lightdm-gtk3-greeter xorg-minimal xdg-user-dirs xorg-fonts xorg-video-drivers" "lightdm"
            ;;

        sway)
            install_desktop_environment "Sway" "sway elogind polkit polkit-elogind foot xorg-fonts" "elogind && ln -s /etc/sv/polkitd /var/service"
            ;;

        swayfx)
            install_desktop_environment "SwayFX" "swayfx elogind polkit polkit-elogind foot xorg-fonts" "elogind && ln -s /etc/sv/polkitd /var/service"
            ;;

        wayfire)
            install_desktop_environment "Wayfire" "wayfire elogind polkit polkit-elogind foot xorg-fonts" "elogind && ln -s /etc/sv/polkitd /var/service"
            ;;

        i3)
            install_desktop_environment "i3wm" "xorg-minimal xinit xterm i3 xorg-fonts xorg-video-drivers" ""
            if [ "$i3prompt" == "Yes" ]; then
                echo -e "Installing lightdm for i3... \n"
                xbps-install -Sy -R $installRepo -r /mnt lightdm lightdm-gtk3-greeter || failureCheck
                install_service "lightdm"
                echo "lightdm has been installed."
            fi
            ;;

        *)
            echo -e "Continuing without GUI... \n"
            ;;
    esac

    clear

    # chroot 是 Linux 和类 Unix 系统中的一个命令，它将当前或某个进程的根目录更改为一个新的目录，从而创建一个“受限的”运行环境。
    # 在这个环境中，程序无法访问新根目录以外的文件系统部分。chroot 的名称来源于“change root”（改变根目录）。

    echo -e "桌面环境设置完成。 \n"
    echo -e "系统将 chroot 进入新安装的环境进行最终设置... \n"
    sleep 1

    chrootFunction  

}


chrootFunction() {

    commandFailure="系统 chroot 失败。"
    
    # 复制 resolv.conf 用于 chroot 后的网络连接
    cp /etc/resolv.conf /mnt/etc/resolv.conf || failureCheck

    # 将需要传递的变量键值对写入到 /mnt/tmp/installerOptions 文件
    syschrootVarPairs=(
        "bootloaderChoice=$bootloaderChoice"
        "suChoice=$suChoice"
        "timezonePrompt=$timezonePrompt"
        "encryptionPrompt=$encryptionPrompt"
        "diskInput=$diskInput"
        "createUser=$createUser"
        "desktopChoice=$desktopChoice"
    )

    for pair in "${syschrootVarPairs[@]}"; do
        printf "%s\n" "$pair" >> /mnt/tmp/installerOptions || failureCheck
    done

    # 将 systemchroot.sh 脚本复制到 chroot 环境中并执行
    cp -f "$(pwd)/systemchroot.sh" /mnt/tmp/systemchroot.sh || failureCheck
    chroot /mnt /bin/bash -c "/bin/bash /tmp/systemchroot.sh" || failureCheck

    # 调用 postInstall 函数进行后续操作
    postInstall
}

drawDialog() {
    commandFailure="显示对话框窗口失败。"
    dialog --stdout --cancel-label "跳过" --no-mouse --backtitle "HourglassOS 模块化集成安装器" "$@"

}

checkModule() {
    # 验证模块的必备字段
    if grep -q "title=" "modules/$i" && (grep -q "status=on" "modules/$i" || grep -q "status=off" "modules/$i") && grep -q "description=" "modules/$i" && grep -q "main()" "modules/$i"; then
        return 0
    else
        echo -e "模块 $i 缺少必要字段，跳过。"
        return 1
    fi
}

failureCheck() {
    echo -e "${RED}$commandFailure${NC}"
    echo "安装将不会继续。"
    exit 1
}

diskCalculator() {
    diskOperand=$(echo $sizeInput | sed 's/G//g')
    if [[ -z $diskOperand ]]; then
        echo "无效的磁盘大小输入: $sizeInput"
        return 1
    fi
    diskFloat=$(echo "$diskFloat - $diskOperand" | bc)
    diskAvailable=$(echo "$diskFloat - 0.5" | bc)
    diskAvailable+="G"

    if (( $(echo "$diskFloat < 0" | bc -l) )); then
        clear
        echo -e "${RED}使用的磁盘空间不能超过所选磁盘的最大容量。您的磁盘是否超额分配了？${NC}\n"
        read -p "按回车键重新开始磁盘配置。" </dev/tty
        diskConfiguration
    fi

    return 0
}

partitionerOutput() {
    echo -e "磁盘: $diskInput"
    echo -e "磁盘大小: $diskSize"
    echo -e "可用磁盘空间: $diskAvailable \n"

    return 0
}

postInstall() {
    if [ -z "$modulesChoice" ]; then
        clear
        echo -e "${GREEN}安装完成。${NC} \n"
        echo -e "请移除安装介质并重启。 \n"
        exit 0
    else
        commandFailure="执行模块失败。"
        for i in "${modulesChoice[@]}"; do
            if . "modules/$i" && main; then
                echo "模块 $i 执行成功。"
            else
                echo "模块 $i 执行失败。"
                failureCheck
            fi
        done

        clear
        echo -e "${GREEN}安装完成。${NC} \n"
        echo -e "请移除安装介质并重启。 \n"
        exit 0
    fi
}

entry