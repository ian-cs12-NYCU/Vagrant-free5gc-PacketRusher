# Policy-Based Routing (PBR) 配置

這個目錄包含了 Vagrant VM 和 Policy-Based Routing 的配置文件。

## 文件說明

- **`pbr_config.env`** - 共享配置文件，包含所有網路和路由配置
- **`Vagrantfile`** - Vagrant VM 配置，從 `pbr_config.env` 讀取設定
- **`setup_pbr.sh`** - PBR 設置腳本，從 `pbr_config.env` 讀取設定
- **`provision_ues_VM.sh`** - VM 初始化腳本

## 配置文件 (`pbr_config.env`)

所有配置集中在一個文件中，方便管理和修改。

## PBR 工作原理

### 流量路徑圖解

```
┌─────────────────────────────────────────────────────────────────────────┐
│  VM (free5GC / UEs-VM)                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ eth0: 192.168.121.164 (DHCP, 管理網)                            │   │
│  │ eth1: 192.168.121.40  (靜態 IP) ← Vagrantfile 配置的主要 IP    │   │
│  │                                                                  │   │
│  │ 路由表:                                                          │   │
│  │   default via 192.168.121.1 dev eth0                           │   │
│  │   192.168.121.0/24 dev eth1 (直連)                             │   │
│  │   192.168.121.0/24 dev eth0 (直連)                             │   │
│  │                                                                  │   │
│  │ 應用程式發送封包到 10.201.0.123:                                │   │
│  │   ┌──────────────────────────────────────────────────────────┐ │   │
│  │   │ 1️⃣ 核心選擇來源 IP                                         │ │   │
│  │   │    來源地址選擇演算法選擇: 192.168.121.40 (eth1)         │ │   │
│  │   │    原因: 這是 Vagrantfile 中配置的主要靜態 IP            │ │   │
│  │   └──────────────────────────────────────────────────────────┘ │   │
│  │                         ▼                                        │   │
│  │   ┌──────────────────────────────────────────────────────────┐ │   │
│  │   │ 2️⃣ 路由決定出口介面                                        │ │   │
│  │   │    查詢路由表: 10.201.0.123 → 走 default route          │ │   │
│  │   │    出口介面: eth0 (因為 default gateway 在 eth0)        │ │   │
│  │   └──────────────────────────────────────────────────────────┘ │   │
│  │                         ▼                                        │   │
│  │   ┌──────────────────────────────────────────────────────────┐ │   │
│  │   │ 3️⃣ 封包組成                                                │ │   │
│  │   │    src: 192.168.121.40  (來自 eth1) ← 注意這裡！         │ │   │
│  │   │    dst: 10.201.0.123                                     │ │   │
│  │   │    出口: eth0                                            │ │   │
│  │   │                                                           │ │   │
│  │   │    ⚠️  來源 IP ≠ 出口介面的 IP                            │ │   │
│  │   └──────────────────────────────────────────────────────────┘ │   │
│  └────────────────────────┬────────────────────────────────────────┘   │
└───────────────────────────┼────────────────────────────────────────────┘
                            │ 封包: src=192.168.121.40
                            │       dst=10.201.0.123
                            │       (從 eth0 發出)
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Host (Vagrant Host / Andy-PC)                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ virbr0: 192.168.121.1 (libvirt 預設網橋)                        │   │
│  │ eno2:   10.200.0.2/16 (專用網卡)                                │   │
│  │                                                                  │   │
│  │ ┌─────────────────────────────────────────────────────────────┐ │   │
│  │ │ 1️⃣ 封包到達 virbr0 (從 VM eth0 進來)                          │ │   │
│  │ │    src: 192.168.121.40  ← Host 看到這個 IP！                │ │   │
│  │ │    dst: 10.201.0.123                                        │ │   │
│  │ │                                                              │ │   │
│  │ │    💡 這就是為什麼 Host 看到的是 .40 而不是 .164            │ │   │
│  │ └───────────────────────┬─────────────────────────────────────┘ │   │
│  │                         ▼                                        │   │
│  │ ┌─────────────────────────────────────────────────────────────┐ │   │
│  │ │ 2️⃣ IP Rule 匹配 (Policy-Based Routing)                        │ │   │
│  │ │    from 192.168.121.40 to 10.0.0.0/8 lookup ues_routing    │ │   │
│  │ │                                                              │ │   │
│  │ │    ✅ 匹配成功！使用自定義路由表 "ues_routing"                 │ │   │
│  │ └───────────────────────┬─────────────────────────────────────┘ │   │
│  │                         ▼                                        │   │
│  │ ┌─────────────────────────────────────────────────────────────┐ │   │
│  │ │ 3️⃣ 查詢 ues_routing 路由表                                    │ │   │
│  │ │    10.0.0.0/8 via 10.200.0.1 dev eno2                      │ │   │
│  │ │                                                              │ │   │
│  │ │    → 決定從 eno2 發出，下一跳是 10.200.0.1                    │ │   │
│  │ └───────────────────────┬─────────────────────────────────────┘ │   │
│  │                         ▼                                        │   │
│  │ ┌─────────────────────────────────────────────────────────────┐ │   │
│  │ │ 4️⃣ NAT (POSTROUTING)                                          │ │   │
│  │ │    iptables -t nat -A POSTROUTING                           │ │   │
│  │ │      -s 192.168.121.40 -o eno2                              │ │   │
│  │ │      -j SNAT --to-source 10.200.0.2                         │ │   │
│  │ │                                                              │ │   │
│  │ │    修改封包:                                                  │ │   │
│  │ │      src: 192.168.121.40 → 10.200.0.2  (SNAT)               │ │   │
│  │ │      dst: 10.201.0.123   → 10.201.0.123 (不變)              │ │   │
│  │ └───────────────────────┬─────────────────────────────────────┘ │   │
│  └─────────────────────────┼─────────────────────────────────────────┘ │
└───────────────────────────┼─────────────────────────────────────────────┘
                            │ 封包: src=10.200.0.2
                            │       dst=10.201.0.123
                            ▼
                    ┌───────────────────┐
                    │   Gateway         │
                    │   10.200.0.1      │
                    └─────────┬─────────┘
                              │
                              ▼
                    ┌───────────────────┐
                    │   Target          │
                    │   10.201.0.123    │
                    │                   │
                    │ 看到的來源 IP:     │
                    │   10.200.0.2 ✅   │
                    └───────────────────┘
```

### 關鍵理解

#### 1. 為什麼 Host 看到的 src IP 是 192.168.121.40 而不是 192.168.121.164？

**答案：來源 IP 選擇 ≠ 出口介面的 IP**

**即使你沒有在 ping 中指定 `-I` 或 `src`，Linux 核心也會自動選擇來源 IP！**

這是 Linux 核心的 **Source Address Selection（來源地址選擇）** 機制，遵循 RFC 3484 規則：

```
當應用程式（如 ping）發送封包時，核心做兩個獨立的決定：

┌─────────────────────────────────────────────────────────────────┐
│ 步驟 1: 選擇來源 IP (Source Address Selection)                  │
│                                                                 │
│ 核心會查看所有網卡的 IP，並根據以下規則選擇：                    │
│                                                                 │
│ 規則 1: 優先選擇同網段的 IP                                      │
│   - 目標是 10.201.0.123 (10.0.0.0/8)                           │
│   - eth0: 192.168.121.164 (不同網段) ✗                         │
│   - eth1: 192.168.121.40  (不同網段) ✗                         │
│   → 兩者都不在目標網段，進入下一規則                             │
│                                                                 │
│ 規則 2: 選擇「主要」(primary) IP                                 │
│   - eth0: 192.168.121.164 (DHCP 動態取得，secondary)           │
│   - eth1: 192.168.121.40  (Vagrantfile 靜態配置，primary) ✓    │
│   → 選擇 192.168.121.40                                        │
│                                                                 │
│ 為什麼 eth1 是 primary？                                        │
│   - Vagrantfile 中明確配置: private_network, ip: "192.168.121.40" │
│   - 這是靜態配置，優先級高於 DHCP                                │
│   - 可用 `ip addr` 查看，沒有 "secondary" 標記的就是 primary    │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 步驟 2: 根據路由表選擇出口介面                                    │
│                                                                 │
│ 查詢路由表: ip route get 10.201.0.123                          │
│   → default via 192.168.121.1 dev eth0                        │
│   → 出口介面: eth0                                             │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 結果: 封包配置                                                   │
│   - 來源 IP: 192.168.121.40  (來自 eth1，步驟 1 選擇)          │
│   - 目標 IP: 10.201.0.123                                      │
│   - 出口介面: eth0           (步驟 2 選擇)                      │
│                                                                 │
│   ⚠️  來源 IP 的網卡 ≠ 出口介面                                 │
└─────────────────────────────────────────────────────────────────┘
```

**實際驗證**：
```bash
# 在 VM 內查看來源地址選擇
vagrant ssh -c "ip route get 10.201.0.123"
# 輸出:
# 10.201.0.123 via 192.168.121.1 dev eth0 src 192.168.121.40
#              ^^^^^^^^^^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^
#              出口是 eth0                    來源是 eth1 的 IP

# 查看完整路由表，注意 src 參數
vagrant ssh -c "ip route show"
# default via 192.168.121.1 dev eth0 proto dhcp src 192.168.121.164 metric 100 
# 192.168.121.0/24 dev eth1 proto kernel scope link src 192.168.121.40 
# 192.168.121.0/24 dev eth0 proto kernel scope link src 192.168.121.164 metric 100
```

**重要發現**：路由表中的 `src` 參數！

實際上，來源 IP 的選擇主要由 **路由表中的 `src` 參數** 決定：

1. **如果路由條目有 `src` 參數**：直接使用該 IP
2. **如果沒有 `src` 參數**：使用 Source Address Selection 演算法

在您的情況下：
- Default route 有明確的 `src 192.168.121.164`
- 但如果實際看到的是 `192.168.121.40`，可能是：
  - 應用程式綁定了特定 IP
  - 有其他 ip rule 在起作用
  - 或者封包實際走的不是 default route（可能有其他更具體的路由）

**驗證您的實際情況**：
```bash
# 看實際使用哪個 IP
vagrant ssh -c "ip route get 10.201.0.123"

# 檢查是否有 policy routing 規則
vagrant ssh -c "ip rule list"
```
# eth0: 
#     inet 192.168.121.164/24 ...  (DHCP, 可能標記 dynamic)
# eth1: 
#     inet 192.168.121.40/24 ...   (靜態配置, 沒有 secondary 標記)

# 手動指定來源 IP 的對比
vagrant ssh -c "ping -c 1 -I eth0 10.201.0.123"  # 強制使用 eth0 的 IP
vagrant ssh -c "ping -c 1 10.201.0.123"          # 讓核心自動選擇 (會選 eth1 的 IP)
```

**為什麼會這樣設計？**

1. **靜態配置 > 動態配置**：Vagrantfile 中明確配置的 IP (eth1: 192.168.121.40) 被視為「主要身份」
2. **管理網 vs 資料網**：eth0 是 Vagrant 管理網（隨機 DHCP），eth1 是你指定的工作網路
3. **一致性**：確保來自同一 VM 的封包總是使用相同的來源 IP，即使路由改變

**如何改變這個行為？**

方法 1: 明確指定來源 IP
```bash
ping -I 192.168.121.164 10.201.0.123  # 使用 eth0 的 IP
```

方法 2: 明確指定來源介面
```bash
ping -I eth0 10.201.0.123
```

方法 3: 修改路由表，加入 `src` 參數
```bash
# 在 VM 內執行
sudo ip route add 10.0.0.0/8 via 192.168.121.1 dev eth0 src 192.168.121.164
```

方法 4: 調整 IP 優先級（把 eth0 設為 primary）
```bash
# 這需要修改網路配置，比較複雜
```

#### 2. VM 不知道 PBR 的存在

- VM 只根據自己的路由表決定：發往 `10.201.0.123` → 走 default route
- VM 將封包發給 default gateway (`192.168.121.1`，即 Host 的 `virbr0`)
- 封包的 src IP 是 `192.168.121.40`（eth1 的 IP），但從 eth0 發出

#### 3. PBR 在 Host 端生效

- 當 Host 收到來自 `192.168.121.40` 的封包時
- `ip rule` 檢查：來源是 `192.168.121.40`，目的地是 `10.0.0.0/8` → 匹配！
- 使用自定義路由表 `ues_routing`，而非主路由表

#### 4. 為什麼 VM 內 `ip route get` 顯示走 eth0？

- 這是 **正確的**！VM 確實透過 eth0 發出封包
- 但封包到達 Host 後，PBR 會「改變主意」，從 eno2 送出

#### 5. NAT 的作用

- Host 將來源 IP 從 `192.168.121.40` 轉換為 `10.200.0.2`
- 這樣目標端看到的來源是合法的外部 IP

### 為什麼需要這樣設計？

```
情境 1: 沒有 PBR (使用 VM 預設路由)
┌─────┐         ┌──────┐         ┌─────────┐
│ VM  │────────▶│ Host │────────▶│ 外部網路 │
└─────┘         └──────┘         └─────────┘
192.168.121.40  主路由表          可能無法路由
                (可能走錯 NIC)    (私有 IP)

情境 2: 使用 PBR + NAT
┌─────┐         ┌──────┐         ┌─────────┐
│ VM  │────────▶│ Host │────────▶│ 外部網路 │
└─────┘         └──────┘         └─────────┘
192.168.121.40  ues_routing      10.200.0.2
                (強制走 eno2)     (合法外部 IP)
```

## 使用方法

### 1. 修改配置

編輯 `pbr_config.env` 文件來修改所有相關配置：

```bash
vim pbr_config.env
```

**重要配置選項**：

```bash
# 選擇 PBR 模式
NETWORK_MODE=specific   # 或 "subnet"

# specific 模式：只允許特定的 VM（較安全）
#   - 只有 UES_VM_IP 和 FREE5GC_VM_IP 的流量會被路由
#   - 需要為每個 VM 添加規則

# subnet 模式：允許整個私有網段（較簡便）
#   - 整個 VAGRANT_PRIVATE_NETWORK (192.168.121.0/24) 的流量都會被路由
#   - 一條規則涵蓋所有 VM
#   - 適合有多個 VM 或頻繁新增 VM 的情況
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
- ✅ 設置路由規則（根據 NETWORK_MODE）
  - **specific 模式**：為 UEs-VM 和 free5GC VM 分別添加規則
  - **subnet 模式**：為整個 192.168.121.0/24 網段添加規則
- ✅ 配置 NAT

### 4. 刪除 Policy-Based Routing

如果需要移除所有 PBR 配置：
```bash
sudo ./setup_pbr.sh -D
```

這會自動偵測當前的 `NETWORK_MODE` 並刪除對應的規則（specific 或 subnet）。

### 5. 切換模式

如果要從 specific 模式切換到 subnet 模式（或反之）：

```bash
# 1. 先刪除舊配置
sudo ./setup_pbr.sh -D

# 2. 修改 pbr_config.env
vim pbr_config.env
# 將 NETWORK_MODE=specific 改為 NETWORK_MODE=subnet

# 3. 重新設置
sudo ./setup_pbr.sh
```

### 6. 臨時覆寫配置

不用修改 config 文件：

```bash
# 覆寫 VM IP
UES_VM_IP=192.168.121.99 sudo -E ./setup_pbr.sh

# 覆寫模式
NETWORK_MODE=subnet sudo -E ./setup_pbr.sh
```

## 兩種模式比較

| 特性 | specific 模式 | subnet 模式 |
|------|--------------|------------|
| **安全性** | ✅ 高 - 只允許特定 VM | ⚠️ 中 - 允許整個網段 |
| **配置複雜度** | 📝 每個 VM 需要一條規則 | ✨ 一條規則涵蓋所有 |
| **適用場景** | 固定數量的 VM | 多個或動態增減的 VM |
| **IP 規則數** | 2 條 (UEs + free5GC) | 1 條 (整個網段) |
| **NAT 規則數** | 2 條 | 1 條 |
| **新增 VM** | 需要修改腳本 | 自動支援 |

**建議**：
- 🔒 **生產環境或安全要求高**：使用 `specific` 模式
- 🚀 **測試環境或快速部署**：使用 `subnet` 模式

## 驗證（從近到遠）

以下步驟依序檢查：先驗證本地設定，再確認封包是否經過 host，最後確認目標端看到的來源 IP（NAT）。

### 1) 本機介面與 IP（Host）

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

### 3) 檢查 policy rule（Host）

```bash
ip rule list | grep ${RT_TABLE_NAME:-ues_routing} -n || ip rule list
```

**specific 模式**期待：
- 包含 `from <UES_VM_IP> to <DEST_NETWORK> lookup ${RT_TABLE_NAME}`
- 包含 `from <FREE5GC_VM_IP> to <DEST_NETWORK> lookup ${RT_TABLE_NAME}`

**subnet 模式**期待：
- 包含 `from <VAGRANT_PRIVATE_NETWORK> to <DEST_NETWORK> lookup ${RT_TABLE_NAME}`

### ### 4) ip_forward 與 NAT 規則（Host）

```bash
sysctl net.ipv4.ip_forward
sudo iptables -t nat -L POSTROUTING -n -v
```

期待：
- `net.ipv4.ip_forward = 1`
- **specific 模式**：NAT 規則將 UES_VM_IP 和 FREE5GC_VM_IP 轉為 `ENO2_IP_ONLY`
- **subnet 模式**：NAT 規則將整個 VAGRANT_PRIVATE_NETWORK 轉為 `ENO2_IP_ONLY`

### 5) 在 VM 內測試發送（VM）

**重要**：VM 內的路由顯示走 eth0 是正常的！

```bash
vagrant ssh -c "ip -4 addr show"
vagrant ssh -c "ip route show"
vagrant ssh -c "ip route get 10.201.0.123"  # 會顯示: via 192.168.121.1 dev eth0 src 192.168.121.40
vagrant ssh -c "ping -c 3 ${GATEWAY_IP:-10.200.0.1}"
vagrant ssh -c "ping -c 3 10.201.0.123"
```

**解釋 `ip route get` 的輸出**：
```
10.201.0.123 via 192.168.121.1 dev eth0 src 192.168.121.40
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^    ^^^^^^^^^^^^^^^^
             出口介面是 eth0                來源 IP 是 eth1 的
```

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

## 常見問題 FAQ

### Q1: 為什麼 Host 看到的 src IP 是 192.168.121.40 而不是 192.168.121.164？我又沒有指定！

**A**: 這是 Linux 核心的 **自動來源地址選擇** 機制！

即使你沒有在 `ping` 中指定來源 IP，核心也會自動選擇。選擇規則：

1. **優先選擇同網段的 IP**
   - 如果目標是 `10.201.0.123`，兩個網卡的 IP 都不在同網段
   
2. **選擇 "primary" IP**
   - `eth0: 192.168.121.164` (DHCP 動態取得) → secondary
   - `eth1: 192.168.121.40` (Vagrantfile 靜態配置) → **primary** ✓
   
3. **路由決定出口介面（獨立決策）**
   - 查詢路由表 → 走 default route → `eth0`

**結果**：來源 IP 是 eth1 的，但封包從 eth0 出去！

**更精確的說明**：

Linux 核心選擇來源 IP 的優先順序：
1. **路由表中的 `src` 參數**（最高優先級） - 如果匹配的路由有明確指定 src
2. **Source Address Selection 演算法**（RFC 3484） - 如果路由沒有 src 參數
3. **應用程式綁定** - 應用可以明確 bind 到某個 IP

查看您的路由表會發現關鍵：
```bash
vagrant ssh -c "ip route show"
# default via 192.168.121.1 dev eth0 src 192.168.121.164 metric 100 
# 192.168.121.0/24 dev eth1 src 192.168.121.40 metric 0
```

- 如果目標在 `192.168.121.0/24` → 走 eth1，src = 192.168.121.40
- 如果目標在其他網段（如 10.201.0.123）→ 走 default (eth0)，src = 192.168.121.164

**但是**，如果您看到不同的結果，請使用 `ip route get` 確認實際行為！

**驗證**：
```bash
vagrant ssh -c "ip route get 10.201.0.123"
# 輸出: 10.201.0.123 via 192.168.121.1 dev eth0 src 192.168.121.40
#       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^    ^^^^^^^^^^^^^^^^
#       出口是 eth0                                來源是 eth1 的 IP

# 強制使用 eth0 的 IP
vagrant ssh -c "ping -I eth0 10.201.0.123"  # 來源會變成 192.168.121.164
```

詳細說明請參考「關鍵理解」章節。

### Q2: 為什麼 VM 內 `ip route get 10.201.0.123` 顯示走 eth0？

**A**: 這是正常的！
- VM 根據自己的路由表決定封包出口（eth0）
- PBR 是在 Host 端生效，VM 不知道也不需要知道
- 封包到達 Host 後才會被 PBR 規則重新路由

### Q3: 如何確認 PBR 真的有效？

**A**: 使用 tcpdump 在 Host 的 eno2 上監聽：
```bash
sudo tcpdump -n -i eno2 src 10.200.0.2
```
然後在 VM 內 ping 目標 IP，如果在 eno2 上看到封包，就證明 PBR 生效。

### Q4: VM 需要添加靜態路由嗎？

**A**: 不需要！這正是 PBR 的優勢：
- VM 保持標準配置（使用 default route）
- 所有路由策略在 Host 端集中管理
- 便於管理多個 VM

## 常見錯誤與對應

- "Invalid prefix for given prefix length." → 檢查 `DEST_NETWORK` 是否為合法的 network address 與對應的 CIDR（例如不要用 `10.201.0.0/8`，應改為 `10.0.0.0/8` 或 `10.201.0.0/16`）。
- 無法偵測 VM IP → 先 `vagrant up`，或在執行時以 `UES_VM_IP=` 環境變數覆寫。
- NAT 不生效 → 檢查 `iptables -t nat -L POSTROUTING`、`sysctl net.ipv4.ip_forward` 與其他 firewall（ufw/iptables raw table）。

## 建議延伸

- 若希望 `-D` 一併移除 `ENO2_IP`，可在 `setup_pbr.sh` 的刪除函式取消註解對應的 `ip addr del` 行。
- 如果需要更動態的 VM 偵測，可新增 `--ip` CLI 參數或整合 Vagrant 的 IP 讀取。

---

若要我把常用的驗證步驟寫成一個小腳本（例如 `check_pbr.sh` 自動跑上述命令並回報差異），我可以幫你實作。要我幫忙嗎？
