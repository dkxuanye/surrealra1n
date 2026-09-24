#!/bin/bash
error=0
unameOut="$(uname -s)"
script_path="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$script_path/sshpass" ];
then
    printg "正在删除 $script_path/sshpass"
    rm -rf "$script_path/sshpass"
fi
cp "$script_path/SSHRD_Script/$unameOut/sshpass" "$script_path/"
printg() {
  printf "\e[32m$1\e[m\n"
}

printy() {
  printf "\e[33;1m%s\n" "$1"
}

printr() {
  echo -e "\033[1;31m$1\033[0m"
}

if [ -d "$script_path/Activation/" ];
then
    printy "[*] 激活备份已存在！"
    printy "备份位于 $script_path/Activation"
    printy "如果继续操作，它将被删除。"
    printy "是否继续 [Y/N] (Y)"
    read wannadelete
    if [ "$wannadelete" == no ] || [ "$wannadelete" == No ] || [ "$wannadelete" == n ] || [ "$wannadelete" == N ];
    then
        exit
    fi
fi

printg "[*] 正在删除目录 $script_path/Activation"
rm -rf "$script_path/Activation"

printg "[*] 正在创建目录 $script_path/Activation"
mkdir "$script_path/Activation"

printy "[*] 请确保设备与电脑连接在同一 Wi-Fi 网络下"
printg "[*] 请输入设备的 IP 地址"
read devip

printg "[*] 请输入设备的终端密码"
read termpw

if [ -f "${HOME}/.ssh/known_hosts" ];
then
    printg "[*] 自动获取主机文件位置并复制到脚本路径"
    if [ ! -d "$script_path/knownhosts" ];
    then
        mkdir "$script_path"/knownhosts
    fi
    cd $script_path && cp "${HOME}/.ssh/known_hosts" "$script_path/knownhosts/"  
fi

sleep 2 

printy "[*] 正在删除旧的 known_hosts"         
rm -rf ${HOME}/.ssh/known_hosts

printg "[*] 正在下载 FairPlay 文件夹"
./sshpass -p "$termpw" sftp -o StrictHostKeyChecking=no -r mobile@$devip:/private/var/mobile/Library/FairPlay ./Activation

sidb=$(./sshpass -p "$termpw" ssh -o StrictHostKeyChecking=no mobile@$devip find /private/var/mobile/Library/FairPlay -name "IC-Info.sidb")
sido=$(./sshpass -p "$termpw" ssh -o StrictHostKeyChecking=no mobile@$devip find /private/var/mobile/Library/FairPlay -name "IC-Info.sido")
sidt=$(./sshpass -p "$termpw" ssh -o StrictHostKeyChecking=no mobile@$devip find /private/var/mobile/Library/FairPlay -name "IC-Info.sidt")
sisb=$(./sshpass -p "$termpw" ssh -o StrictHostKeyChecking=no mobile@$devip find /private/var/mobile/Library/FairPlay -name "IC-Info.sisb")

if [ -e "$script_path/Activation/FairPlay/iTunes_Control/iTunes/IC-Info.sidb" ]; then
    printg "[*] IC-Info.sidb 下载成功"
elif [[ "$sidb" == *"fairplay"* ]]; then
    printr "[!] IC-Info.sidb 下载失败。请手动下载。"
    error=1
fi

if [ -e "$script_path/Activation/FairPlay/iTunes_Control/iTunes/IC-Info.sido" ]; then
    printg "[*] IC-Info.sido 下载成功"
elif [[ "$sido" == *"fairplay"* ]]; then
    printr "[!] IC-Info.sido 下载失败。请手动下载。"
    error=1
fi

if [ -e "$script_path/Activation/FairPlay/iTunes_Control/iTunes/IC-Info.sidt" ]; then
    printg "[*] IC-Info.sidt 下载成功"
elif [[ "$sidt" == *"fairplay"* ]]; then
    printr "[!] IC-Info.sidt 下载失败。请手动下载。"
    error=1
fi 

if [ -e "$script_path/Activation/FairPlay/iTunes_Control/iTunes/IC-Info.sisb" ]; then
    printg "[*] IC-Info.sisb 下载成功"
elif [[ "$sisb" == *"fairplay"* ]]; then
    printr "[!] IC-Info.sisb 下载失败。请手动下载。"
    error=1
fi

if [ -e "$script_path/Activation/FairPlay/iTunes_Control/iTunes/IC-Info.sisv" ]; then
    printg "[*] IC-Info.sisv 下载成功"
else 
    printr "[!] IC-Info.sisv 下载失败。请手动下载。"
    error=1
fi

printg "[*] 正在查找 data_ark.plist"
data_arkpath=$(./sshpass -p "$termpw" ssh -o StrictHostKeyChecking=no mobile@$devip find /private/var/containers/Data/System -name "data_ark.plist")

printg "[*] 正在下载 data_ark.plist"
./sshpass -p "$termpw" sftp -o StrictHostKeyChecking=no -r mobile@$devip:$data_arkpath ./Activation

if [ -e "$script_path/Activation/data_ark.plist" ]; then
    printg "[*] data_ark.plist 下载成功"
else
    printr "[!] data_ark.plist 下载失败。请手动下载。"
    error=1
fi

printg "[*] 正在下载 com.apple.commcenter.device_specific_nobackup.plist"
./sshpass -p "$termpw" ssh -o StrictHostKeyChecking=no mobile@$devip "echo "$termpw" | sudo -S cp /private/var/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist /private/var/containers/Data/System/"
./sshpass -p "$termpw" ssh -o StrictHostKeyChecking=no mobile@$devip "echo "$termpw" | sudo -S chown mobile:mobile /private/var/containers/Data/System/com.apple.commcenter.device_specific_nobackup.plist"
./sshpass -p "$termpw" sftp -oPort=2222 -o "StrictHostKeyChecking=no" mobile@$devip:/private/var/containers/Data/System/com.apple.commcenter.device_specific_nobackup.plist "$script_path/Activation"


if [ -e "$script_path/Activation/com.apple.commcenter.device_specific_nobackup.plist" ]; then
    printg "[*] com.apple.commcenter.device_specific_nobackup.plist 下载成功"
else
    printr "[!] com.apple.commcenter.device_specific_nobackup.plist 下载失败。请手动下载。"
    error=1
fi

printg "[*] 正在查找 activation_record.plist"
actrecpath=$(./sshpass -p "$termpw" ssh -o StrictHostKeyChecking=no mobile@$devip find /private/var/containers/Data/System -name "activation_record.plist")

printg "[*] 正在下载 activation_record.plist"
./sshpass -p "$termpw" sftp -o StrictHostKeyChecking=no -r mobile@$devip:$actrecpath ./Activation

if [ -e "$script_path/Activation/activation_record.plist" ]; then
    printg "[*] activation_record.plist 下载成功"
else
    printr "[!] activation_record.plist 下载失败。请手动下载。"
    error=1
fi
if [ "$error" -eq 1 ]; then
    printr "备份完成，但存在错误 :("
else
    printg "备份完成，无错误 :)"
fi
exit
