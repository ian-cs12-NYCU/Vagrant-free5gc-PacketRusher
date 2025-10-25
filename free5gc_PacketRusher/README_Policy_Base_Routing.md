# Policy-Based Routing (PBR) 配置

這個目錄包含了 Vagrant VM 和 Policy-Based Routing 的配置文件。

## 文件說明

- **`pbr_config.env`** - 共享配置文件，包含所有網路和路由配置
- **`Vagrantfile`** - Vagrant VM 配置，從 `pbr_config.env` 讀取設定
- **`setup_pbr.sh`** - PBR 設置腳本，從 `pbr_config.env` 讀取設定
- **`provision.sh`** - VM 初始化腳本

## 配置文件 (`pbr_config.env`)

所有配置集中在一個文件中，方便管理和修改：



## 使用方法

### 1. 修改配置

編輯 `pbr_config.env` 文件來修改所有相關配置：

```bash
vim pbr_config.env
```

### 2. 啟動 Vagrant VM

```bash
vagrant up
```

Vagrantfile 會自動從 `pbr_config.env` 讀取配置。

### 3. 設置 Policy-Based Routing

在主機上執行（設置模式）：

```bash
sudo ./setup_pbr.sh
```

這會：
- ✅ 確保 eno2 有正確的 IP 地址
- ✅ 創建自定義路由表
- ✅ 設置路由規則
- ✅ 配置 NAT

### 4. 刪除 Policy-Based Routing

如果需要移除所有 PBR 配置：
```
sudo ./setup_pbr.sh -D
```

# Policy-Based Routing (PBR) 配置與驗證

此檔說明如何使用 `setup_pbr.sh` 及 `pbr_config.env` 來設定 Policy-Based Routing (PBR)，並提供由「近」到「遠」的逐步驗證與排查流程，方便確認流量是否經由 `eno2` 並被 NAT。

## 檔案清單

- `pbr_config.env` — 共享設定檔（VM / network / routing）
- `Vagrantfile` — VM 配置（會讀取 `pbr_config.env`）
- `setup_pbr.sh` — PBR 設定與刪除腳本
- `provision.sh` — VM 初始化腳本（如有）


## 使用方法

1. 編輯 `pbr_config.env`，確認值正確。

2. 若使用 Vagrant，啟動 VM：

```bash
vagrant up
vagrant status
```

3. 在 Host 上執行設定（會讀取 `pbr_config.env`）：

```bash
sudo ./setup_pbr.sh
```

4. 刪除設定（清除 route / rule / NAT）：

```bash
sudo ./setup_pbr.sh -D
```

5. 臨時覆寫 UEs VM IP（不用修改 config）：

```bash
UES_VM_IP=192.168.121.99 sudo -E ./setup_pbr.sh
```

## 驗證（從近到遠）

以下步驟依序檢查：先驗證本地設定，再確認封包是否經過 host，最後確認目標端看到的來源 IP（NAT）。

1) 本機介面與 IP（Host）

```bash
ip link show ${ENO2_INTERFACE:-eno2}
ip addr show ${ENO2_INTERFACE:-eno2}
```

期待：`ENO2_IP` 已配置（例如 `10.200.0.2/16`）。若沒有：

```bash
sudo ip addr add ${ENO2_IP:-10.200.0.2/16} dev ${ENO2_INTERFACE:-eno2}
sudo ip link set ${ENO2_INTERFACE:-eno2} up
```

2) 自訂路由表是否存在與內容（Host）

```bash
grep -E "^${RT_TABLE_ID:-100}\s+${RT_TABLE_NAME:-ues_routing}" /etc/iproute2/rt_tables || cat /etc/iproute2/rt_tables
sudo ip route show table ${RT_TABLE_NAME:-ues_routing}
```

期待：有一條 `DEST_NETWORK via GATEWAY_IP dev ENO2_INTERFACE`。

3) 檢查 policy rule（Host）

```bash
ip rule list | grep ${RT_TABLE_NAME:-ues_routing} -n || ip rule list
```

期待：包含 `from <UES_VM_IP> to <DEST_NETWORK> lookup ${RT_TABLE_NAME}`。

4) ip_forward 與 NAT 規則（Host）

```bash
sysctl net.ipv4.ip_forward
sudo iptables -t nat -L POSTROUTING -n -v | grep ${UES_VM_IP:-192.168.121.50} || true
```

期待：`net.ipv4.ip_forward = 1`，且 NAT 規則將來源轉為 `ENO2_IP_ONLY`。

5) 在 VM 內測試發送（VM）

```bash
vagrant ssh -c "ip -4 addr show"
vagrant ssh -c "ip route show"
vagrant ssh -c "ping -c 3 ${GATEWAY_IP:-10.200.0.1}"
vagrant ssh -c "ping -c 3 10.0.0.1"   # 如果目標可達
```

若 VM 端 ping 失敗，先在 VM 端執行 `ip route get <target>`（或 `ip route get ${GATEWAY_IP} from <VM-IP>`）檢查路由。

6) 在 Host 用 tcpdump 監聽 NIC（Host），同時在 VM 觸發封包

```bash
# 在 Host 上執行（需 sudo）
sudo tcpdump -n -i ${ENO2_INTERFACE:-eno2} host ${GATEWAY_IP:-10.200.0.1} and icmp

# 在另一個 shell 或 VM 裡面執行
vagrant ssh -c "ping -c 3 ${GATEWAY_IP:-10.200.0.1}"
```

期待：Host 上能看到從 `UES_VM_IP` 發出的封包經過 `eno2`（ICMP 顯示來源為 VM IP，出站時會被 NAT 成 `ENO2_IP_ONLY`）。

7) 用 `ip route get` 在 Host 模擬來源路由決策

```bash
sudo ip route get ${GATEWAY_IP:-10.200.0.1} from ${UES_VM_IP:-192.168.121.50}
```

期待：該命令顯示會使用 `ues_routing` 並走向 `GATEWAY_IP`（或下一跳）。

8) 若目標端可控，檢查目標端看到的來源 IP（驗證 NAT）

- 在目標主機上使用 tcpdump 或系統日誌檢查来源 IP，應為 `ENO2_IP_ONLY`（而非 `UES_VM_IP`）。
    ```bash
    sudo tcpdump -i enp3s0 src 10.200.0.2
    ```

## 常見錯誤與對應

- "Invalid prefix for given prefix length." → 檢查 `DEST_NETWORK` 是否為合法的 network address 與對應的 CIDR（例如不要用 `10.201.0.0/8`，應改為 `10.0.0.0/8` 或 `10.201.0.0/16`）。
- 無法偵測 VM IP → 先 `vagrant up`，或在執行時以 `UES_VM_IP=` 環境變數覆寫。
- NAT 不生效 → 檢查 `iptables -t nat -L POSTROUTING`、`sysctl net.ipv4.ip_forward` 與其他 firewall（ufw/iptables raw table）。

## 建議延伸

- 若希望 `-D` 一併移除 `ENO2_IP`，可在 `setup_pbr.sh` 的刪除函式取消註解對應的 `ip addr del` 行。
- 如果需要更動態的 VM 偵測，可新增 `--ip` CLI 參數或整合 Vagrant 的 IP 讀取。

---

若要我把常用的驗證步驟寫成一個小腳本（例如 `check_pbr.sh` 自動跑上述命令並回報差異），我可以幫你實作。要我幫忙嗎？
