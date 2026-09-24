#!/bin/bash

skip_rdboot=false
unameOut="$(uname -s)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-rdboot)
      skip_rdboot=true
      ;;
    *)
      echo "未知选项: $1"
      exit 1
      ;;
  esac
  shift
done

script_path="$(cd "$(dirname "$0")" && pwd)"

printg() {
  printf "\e[32m$1\e[m\n"
}

printy() {
  printf "\e[33;1m%s\n" "$1"
}

printr() {
  echo -e "\033[1;31m$1\033[0m"
}


if [ -d "$script_path/knownhosts" ]; then
    cd $script_path
else
    cd $script_path && mkdir knownhosts
fi

if [ -f "${HOME}/.ssh/known_hosts" ]; then
    printg "[*] 自动获取主机文件位置并复制到脚本路径"

    cd $script_path && cp "${HOME}/.ssh/known_hosts" "$script_path/"

    cd $script_path && cp "$script_path/known_hosts" "$script_path/knownhosts/"  

    

    rm -rf ${HOME}/.ssh/known_hosts
fi

chmod +x "$script_path"/SSHRD_Script/Darwin/sshpass
rm -rf ${HOME}/.ssh/known_hosts

if [ "$skip_rdboot" = true ]; then
    printg "[*] 用户已选择跳过 sshrd 启动，请确保设备已启动 sshrd 并运行 mount_filesystems"
else
    printg "[?] 你的设备当前是什么系统版本？"
    read ios1
    printg
fi

if [ ! -f "$script_path/sshpass" ]; then
    cp "$script_path/SSHRD_Script/$unameOut/sshpass" "$script_path/"
    printg "[*] 正在复制 sshpass 到脚本路径（稍后需要用到）"
else
    cd $script_path
fi

if [ ! -f "$script_path/iproxy" ]; then
    cp "$script_path/SSHRD_Script/$unameOut/iproxy" "$script_path/"
    printg "[*] 正在复制 iproxy 到脚本路径（稍后需要用到）"

else
    cd $script_path
fi

printg "[*] 正在创建 Ramdisk，请确保设备处于 DFU 模式"


if [ "$skip_rdboot" = true ]; then
    printg "[*] 已按要求跳过 ramdisk 启动"
else
    printg "[*] 正在创建 Ramdisk"
    cd "$script_path/SSHRD_Script" && chmod +x sshrd.sh && ./sshrd.sh "$ios1"
    printg "[*] 正在启动 ramdisk"
    cd "$script_path/SSHRD_Script" && ./sshrd.sh boot
fi

printg "[*] 打开新终端窗口时可能需要点击“允许”"

if [ "$skip_rdboot" = true ]; then
    printg "[*] 如果你使用的是 Mac，应已自动打开带 ssh 的终端窗口"
else
  
  case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    sleep 5 && osascript -e "tell application \"Terminal\" to do script \"cd $script_path/SSHRD_Script && ./sshrd.sh ssh\"";;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    MSYS_NT*)   machine=Git;;
    *)          machine="UNKNOWN:${unameOut}"
   esac
  
fi

printr "[!] 不要关闭它，并确保 ssh 已成功连接！如果你使用 Linux，请打开新终端并手动运行下面的命令"
printg  "sudo su root -c 'cd $script_path/SSHRD_Script && ./sshrd.sh ssh'"
printg "[*] 一切就绪后按回车。"
read rdbready

cd $script_path			
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mount_filesystems

printg "[*] 正在删除旧的激活文件（如果报错也没关系）"

./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 rm -rf /mnt2/mobile/Library/FairPlay/
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 rm -rf /mnt2/mobile/Media/Downloads/1
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 rm -rf /mnt2/mobile/Media/1

printg "[*] 正在创建目录 /mnt2/mobile/Media/Downloads/1"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mkdir -p /mnt2/mobile/Media/Downloads/1/Activation
printg "[*] 正在创建目录 /mnt2/mobile/Media/1"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mkdir -p /mnt2/mobile/Media/1
printg "[*] 正在推送激活文件到 /mnt2/mobile/Media/Downloads/1"
./sshpass -p alpine scp -rP 2222 -o StrictHostKeyChecking=no $script_path/Activation root@localhost:/mnt2/mobile/Media/Downloads/1
sleep 1

printg "[*] 正在移动激活文件到 /mnt2/mobile/Media/1"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mv -f /mnt2/mobile/Media/Downloads/1 /mnt2/mobile/Media

chown_path="/usr/sbin/chown"

printg "[*] 正在修复激活文件夹的权限"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 "$chown_path" -R mobile:mobile /mnt2/mobile/Media/1
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chmod -R 755 /mnt2/mobile/Media/1

printg "[*] 正在修复所有激活文件的权限"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chmod 644 /mnt2/mobile/Media/1/Activation/activation_record.plist 
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chmod 644 /mnt2/mobile/Media/1/Activation/data_ark.plist 
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chmod 644 /mnt2/mobile/Media/1/Activation/com.apple.commcenter.device_specific_nobackup.plist 


printg "[*] 正在移动 FairPlay 文件夹到 /mnt2/mobile/Library/FairPlay"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mv -f /mnt2/mobile/Media/1/Activation/FairPlay /mnt2/mobile/Library/FairPlay 
printg "[*] 正在修复 FairPlay 权限"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chmod 755 /mnt2/mobile/Library/FairPlay

printg "[*] 正在查找 internal 文件夹"
ACT1=$(./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 find /mnt2/containers/Data/System -name internal) 
ACT2=$(./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 find /mnt2/containers/Data/System -name activation_records) 


ACT2=${ACT1%?????????????????}

ACT3=$ACT2/Library/internal/data_ark.plist

printg "[*] 正在设置 data_ark.plist 的权限"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chflags nouchg $ACT3 

printg "[*] 正在替换 data_ark.plist"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mv -f /mnt2/mobile/Media/1/Activation/data_ark.plist $ACT3 
printg "[*] 正在修复权限"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chmod 755 $ACT3 
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chflags uchg $ACT3

ACT4=$ACT2/Library/activation_records 

printg "[*] 正在创建目录 activation_records"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 rm -rf $ACT4 
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mkdir $ACT4 

printg "[*] 正在复制 activation_record.plist 到 activation_records 文件夹"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mv -f /mnt2/mobile/Media/1/Activation/activation_record.plist $ACT4/activation_record.plist 

printg "[*] 正在修复权限"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chmod 755 $ACT4/activation_record.plist 
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chflags uchg $ACT4/activation_record.plist 

printg "[*] 正在替换 com.apple.commcenter.device_specific_nobackup.plist"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chflags nouchg /mnt2/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 mv -f /mnt2/mobile/Media/1/Activation/com.apple.commcenter.device_specific_nobackup.plist /mnt2/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist 


printg "[*] 正在修复权限"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 $chown_path root:mobile /mnt2/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist

./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chmod 755 /mnt2/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist 

./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 chflags uchg /mnt2/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist


printg "[*] 正在重启"
./sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 /sbin/reboot


printg "[*] 脚本执行完成，设备即将重启，可像平时一样完成设置向导"
printg "[*] 设备将正常工作，但侧载只能使用 TrollStore。如需安装，请参考 TrollStore 教程"

if [ -f "$script_path/knownhosts/known_hosts" ]; then
    echo "[*] 正在恢复 known_hosts 文件"
    cd "$script_path/knownhosts" && cp "$script_path/knownhosts/known_hosts" "${HOME}/.ssh/known_hosts"
fi


printg "[*] 全部完成！尽情使用吧！"

exit 1
