# Vagrant free5GC + PacketRusher Setup

本專案使用 Vagrant 配置兩台 VM：
- **free5GC VM**: 運行 free5GC v4.0.0 核心網路
- **UEs-VM (PacketRusher)**: 運行 PacketRusher 模擬 UE 設備

## 系統架構

```
Ian-PC (遠端開發機) <--SSH--> Andy-PC (Vagrant Host) <--libvirt--> VMs (free5GC, UEs-VM)
```

## 前置需求

### Andy-PC (Vagrant Host)
- Vagrant
- libvirt/KVM
- Ubuntu 或相容的 Linux 系統

### Ian-PC (遠端開發機)
- VSCode
- Remote-SSH 擴展
- SSH 客戶端

## VM 配置

### free5GC VM
- IP: `192.168.121.40`
- Hostname: `free5GC`
- Memory: 4096 MB
- CPUs: 4
- 安裝內容：Go 1.24.5, MongoDB 7.0, gtp5g kernel module, free5GC v4.0.0

### UEs-VM (PacketRusher)
- IP: `192.168.121.50`
- Hostname: `UEs-VM`
- Memory: 4096 MB
- CPUs: 4

## 快速開始

### 在 Andy-PC 上啟動 VM

```bash
cd /path/to/vagrant-practice/free5gc_PacketRusher

# 啟動 free5GC VM
vagrant up free5GC

# 啟動 UEs-VM
vagrant up UEs-VM

# 或同時啟動兩台
vagrant up
```

### 檢查 VM 狀態

```bash
vagrant status
```

## 從 Ian-PC 使用 VSCode 連接到 VM

由於 VM 運行在 Andy-PC 上，需要透過 SSH Port Forwarding 或 SSH Jump Host 來從 Ian-PC 連接。

### 方法 1: SSH Port Forwarding (推薦用於臨時連接)

#### 步驟 1: 在 Andy-PC 上獲取 VM 的 SSH 配置

```bash
cd /path/to/vagrant-practice/free5gc_PacketRusher

# 獲取 free5GC VM 的 SSH 配置
vagrant ssh-config free5GC

# 獲取 UEs-VM 的 SSH 配置
vagrant ssh-config UEs-VM
```

輸出範例：
```
Host free5GC
  HostName 127.0.0.1
  User vagrant
  Port 2222
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile /path/to/.vagrant/machines/free5GC/libvirt/private_key
  IdentitiesOnly yes
  LogLevel FATAL
```

#### 步驟 2: 在 Andy-PC 上設置 Port Forwarding

在 Andy-PC 上執行以下命令，將 VM 的 SSH port 轉發到 Andy-PC 的公開端口：

```bash
# 轉發 free5GC VM (假設 Vagrant SSH port 是 2222)
ssh -N -L 0.0.0.0:2222:127.0.0.1:2222 localhost &

# 轉發 UEs-VM (假設 Vagrant SSH port 是 2200)
ssh -N -L 0.0.0.0:2200:127.0.0.1:2200 localhost &
```

**或者使用 socat (更簡單的方法):**

```bash
# 轉發 free5GC VM
sudo socat TCP-LISTEN:2222,fork,reuseaddr TCP:127.0.0.1:2222 &

# 轉發 UEs-VM
sudo socat TCP-LISTEN:2200,fork,reuseaddr TCP:127.0.0.1:2200 &
```

#### 步驟 3: 在 Ian-PC 上配置 SSH

在 Ian-PC 上編輯 `~/.ssh/config`:

```bash
vim ~/.ssh/config
```

添加以下配置：

```ssh-config
# free5GC VM (透過 Andy-PC)
Host free5gc-vm
  HostName <Andy-PC-IP>
  User vagrant
  Port 2222
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile ~/.ssh/vagrant_free5gc_key
  IdentitiesOnly yes
  LogLevel FATAL
  PubkeyAcceptedKeyTypes +ssh-rsa
  HostKeyAlgorithms +ssh-rsa

# UEs-VM (透過 Andy-PC)
Host ues-vm
  HostName <Andy-PC-IP>
  User vagrant
  Port 2200
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile ~/.ssh/vagrant_ues_key
  IdentitiesOnly yes
  LogLevel FATAL
  PubkeyAcceptedKeyTypes +ssh-rsa
  HostKeyAlgorithms +ssh-rsa
```

**注意**: 
- 將 `<Andy-PC-IP>` 替換為 Andy-PC 的實際 IP 地址
- 需要從 Andy-PC 複製 private key 到 Ian-PC

#### 步驟 4: 複製 SSH Private Key

在 Andy-PC 上找到 private key：

```bash
cd /path/to/vagrant-practice/free5gc_PacketRusher

# 找到 free5GC 的 private key
ls .vagrant/machines/free5GC/libvirt/private_key

# 找到 UEs-VM 的 private key
ls .vagrant/machines/UEs-VM/libvirt/private_key
```

將這些 key 複製到 Ian-PC 的 `~/.ssh/` 目錄：

```bash
# 在 Ian-PC 上執行
scp andy@<Andy-PC-IP>:/path/to/.vagrant/machines/free5GC/libvirt/private_key ~/.ssh/vagrant_free5gc_key
scp andy@<Andy-PC-IP>:/path/to/.vagrant/machines/UEs-VM/libvirt/private_key ~/.ssh/vagrant_ues_key

# 設置正確的權限
chmod 600 ~/.ssh/vagrant_free5gc_key
chmod 600 ~/.ssh/vagrant_ues_key
```

#### 步驟 5: 在 VSCode 中連接

1. 打開 VSCode
2. 安裝 **Remote - SSH** 擴展 (如果尚未安裝)
3. 按 `F1` 或 `Ctrl+Shift+P` 打開命令面板
4. 輸入 `Remote-SSH: Connect to Host...`
5. 選擇 `free5gc-vm` 或 `ues-vm`

### 方法 2: SSH Jump Host (推薦用於長期使用)

這種方法不需要在 Andy-PC 上設置 port forwarding。

#### 步驟 1: 在 Ian-PC 上配置 SSH

編輯 `~/.ssh/config`:

```ssh-config
# Andy-PC (Jump Host)
Host andy-pc
  HostName <Andy-PC-IP>
  User <your-username-on-andy-pc>
  IdentityFile ~/.ssh/id_rsa

# free5GC VM (透過 Andy-PC 跳轉)
Host free5gc-vm
  HostName 127.0.0.1
  User vagrant
  Port 2222
  ProxyJump andy-pc
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile ~/.ssh/vagrant_free5gc_key
  IdentitiesOnly yes
  LogLevel FATAL
  PubkeyAcceptedKeyTypes +ssh-rsa
  HostKeyAlgorithms +ssh-rsa

# UEs-VM (透過 Andy-PC 跳轉)
Host ues-vm
  HostName 127.0.0.1
  User vagrant
  Port 2200
  ProxyJump andy-pc
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile ~/.ssh/vagrant_ues_key
  IdentitiesOnly yes
  LogLevel FATAL
  PubkeyAcceptedKeyTypes +ssh-rsa
  HostKeyAlgorithms +ssh-rsa
```

**重要**: 
- `ProxyJump andy-pc` 會先連接到 Andy-PC，再跳轉到 VM
- Port 需要與 `vagrant ssh-config` 顯示的一致
- 需要將 VM 的 private key 複製到 Ian-PC

#### 步驟 2: 測試連接

```bash
# 在 Ian-PC 上測試
ssh free5gc-vm
ssh ues-vm
```

#### 步驟 3: 在 VSCode 中連接

操作同方法 1 的步驟 5。

## 防火牆設置 (如需要)

如果 Andy-PC 上有防火牆，需要開放相應端口：

```bash
# UFW 範例
sudo ufw allow 2222/tcp comment 'free5GC VM SSH'
sudo ufw allow 2200/tcp comment 'UEs-VM SSH'

# firewalld 範例
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --permanent --add-port=2200/tcp
sudo firewall-cmd --reload
```

## 故障排除

### 無法連接到 VM

1. 確認 VM 正在運行：
   ```bash
   # 在 Andy-PC 上
   vagrant status
   ```

2. 確認 SSH port：
   ```bash
   # 在 Andy-PC 上
   vagrant ssh-config free5GC | grep Port
   ```

3. 測試從 Andy-PC 連接 VM：
   ```bash
   # 在 Andy-PC 上
   vagrant ssh free5GC
   ```

4. 檢查 port forwarding 是否運行：
   ```bash
   # 在 Andy-PC 上
   sudo netstat -tlnp | grep 2222
   ```

### Private Key 權限錯誤

```bash
chmod 600 ~/.ssh/vagrant_free5gc_key
chmod 600 ~/.ssh/vagrant_ues_key
```

### SSH 版本兼容性問題

如果遇到 "no matching host key type found" 錯誤，在 `~/.ssh/config` 中添加：

```ssh-config
PubkeyAcceptedKeyTypes +ssh-rsa
HostKeyAlgorithms +ssh-rsa
```

## 配置文件位置

- VM 配置: `free5gc_PacketRusher/pbr_config.env`
- Vagrantfile: `free5gc_PacketRusher/Vagrantfile`
- free5GC 安裝腳本: `free5gc_PacketRusher/provision_free5gc.sh`
- PacketRusher 安裝腳本: `free5gc_PacketRusher/provision_ues_VM.sh`

## 常用命令

```bash
# 啟動 VM
vagrant up [vm-name]

# 停止 VM
vagrant halt [vm-name]

# 重新載入配置
vagrant reload [vm-name]

# 重新執行 provision 腳本
vagrant provision [vm-name]

# SSH 進入 VM
vagrant ssh [vm-name]

# 刪除 VM
vagrant destroy [vm-name]

# 查看 VM 狀態
vagrant status
```

## 注意事項

1. **安全性**: Port forwarding 會將 VM SSH 暴露到網路上，建議只在可信網路中使用
2. **Private Key**: 妥善保管 SSH private key，不要提交到版本控制
3. **資源**: 兩台 VM 共需要 8GB RAM 和 8 個 CPU 核心
4. **網路**: 確保 Andy-PC 和 Ian-PC 在同一網路或 Ian-PC 可以訪問 Andy-PC 的 IP

## 參考資料

- [free5GC 官方文檔](https://free5gc.org/)
- [Vagrant 官方文檔](https://www.vagrantup.com/docs)
- [VSCode Remote-SSH](https://code.visualstudio.com/docs/remote/ssh)
