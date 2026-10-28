#### 此固件为 ARM64 虚拟机专用（armsr-armv8，支持 24.10.x / 25.12.x）
#### 产出格式为 qcow2 / vmdk，可在虚拟机里自由扩展大小 无需添加另一块虚拟硬盘
#### 固件地址 `10.0.0.1`
#### 用户名 `root` 密码：无
#### 默认软件包大小 2GB

##### 该固件导入单网口虚拟机的时候 默认采用DHCP模式 在虚拟机终端输入`ip a` 查看ip 后访问web
##### 该固件导入多网口虚拟机的时候 默认第一个网口采用DHCP模式 视为wan 其他网口自动br-lan 
##### 25.12.x 版本预装 honk（daeuniverse）+ LuCI，精简配置位于 `/etc/honk/config.dae`，首次启动自动对齐 LAN 网卡；默认未启用，请在「服务 → daehonk」中填入订阅后启用，面板 `http://10.0.0.1:9090/ui/`（honk 与 daed 不要同时启用）
##### 若release中下载吃力 可在国内加速站下载 https://wkdaily.cpolar.top/archives/1

- 你可以理解为这是一种ARM64 通用型OpenWrt ,产出格式为qcow2,适合所有ARM64平台的虚拟机
- 举例来说 目前有哪些arm64虚拟机？
- 比如斐讯N1刷了armbian系统,armbian系统里安装了PVE虚拟机 可用
- 比如新款Apple Silicon芯片的苹果电脑里的虚拟机UTM 可用
- 比如友善NanoPi R3S、R5S 官方推出的预装了PVE的debian系统 可用
- 比如瑞莎E20C刷了Armbian系统，自己安装了QEMU+原生的KVM虚拟机 可用