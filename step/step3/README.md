# STEP3. VPC Router / Local Route 재현

## 목표

VPC 내부의 local routing을 재현한다.

Step 2에서 만든 Public Subnet과 Private DB Subnet 사이에 router namespace를 추가한다.

AWS VPC에서는 VPC CIDR에 대한 local route가 기본으로 존재한다.

```text
10.10.0.0/16 -> local
```

이번 로컬 실습에서는 Linux router namespace와 route 명령으로 이를 재현한다.

## 구성 매핑

| AWS 개념 | 로컬 실습에서의 대응 |
| --- | --- |
| VPC Router | `router` network namespace |
| VPC Local Route | 컨테이너 namespace의 `ip route add` |
| Public Subnet router interface | `10.10.1.1/24` |
| Private DB Subnet router interface | `10.10.2.1/24` |

## IP 계획

| 대상 | 값 |
| --- | --- |
| AppServer | `10.10.1.10/24` |
| Database | `10.10.2.10/24` |
| Router Public Side | `10.10.1.1/24` |
| Router DB Side | `10.10.2.1/24` |

## 진행 전 확인

Step 2 구성이 유지되어 있어야 한다.

```bash
ip link show br-public
ip link show br-private-db
sudo ip netns exec app-server ip addr show eth0
sudo ip netns exec database ip addr show eth0
```

예상 확인 값:

```text
app-server eth0: 10.10.1.10/24
database eth0: 10.10.2.10/24
```

## 진행 순서

아래 명령은 직접 한 줄씩 실행해도 되고, 같은 내용을 담은 [setup.sh](./setup.sh)를 VPC VM에 복사해서 실행해도 된다.

```bash
chmod +x setup.sh check.sh clean.sh
./setup.sh
./check.sh
```

처음 학습할 때는 수동 명령으로 진행하는 편이 router namespace와 route table을 이해하기 좋다.

### 1. 실습 디렉터리 준비

VPC VM 안에서 Step 3 디렉터리를 준비한다.

```bash
mkdir -p ~/aws-vpc-local-lab/step/step3
cd ~/aws-vpc-local-lab/step/step3
```

### 2. router namespace 생성

VPC Router 역할을 할 network namespace를 만든다.

```bash
sudo ip netns add router
sudo ip netns exec router ip link set lo up
```

확인한다.

```bash
ip netns list
```

예상 결과:

```text
router
app-server
database
```

### 3. router를 Public Subnet에 연결

router의 public side를 `br-public`에 연결한다.

Linux 인터페이스 이름은 최대 15자라서 veth 이름은 짧게 작성한다.

```bash
sudo ip link add vrpubh type veth peer name vrpub
sudo ip link set vrpubh master br-public
sudo ip link set vrpubh up

sudo ip link set vrpub netns router
sudo ip netns exec router ip link set vrpub name eth-public
sudo ip netns exec router ip addr add 10.10.1.1/24 dev eth-public
sudo ip netns exec router ip link set eth-public up
```

확인한다.

```bash
sudo ip netns exec router ip addr show eth-public
```

예상 결과:

```text
inet 10.10.1.1/24 포함
```

### 4. router를 Private DB Subnet에 연결

router의 db side를 `br-private-db`에 연결한다.

여기서도 15자 이하의 짧은 veth 이름을 사용한다.

```bash
sudo ip link add vrdbh type veth peer name vrdb
sudo ip link set vrdbh master br-private-db
sudo ip link set vrdbh up

sudo ip link set vrdb netns router
sudo ip netns exec router ip link set vrdb name eth-db
sudo ip netns exec router ip addr add 10.10.2.1/24 dev eth-db
sudo ip netns exec router ip link set eth-db up
```

확인한다.

```bash
sudo ip netns exec router ip addr show eth-db
```

예상 결과:

```text
inet 10.10.2.1/24 포함 
```

### 5. router namespace에서 IP forwarding 활성화

router namespace가 패킷을 전달할 수 있게 한다.

```bash
sudo ip netns exec router sysctl -w net.ipv4.ip_forward=1
```

확인한다.

```bash
sudo ip netns exec router sysctl net.ipv4.ip_forward
```

예상 결과:

```text
net.ipv4.ip_forward = 1
```

### 6. app-server route 추가

app-server가 `10.10.2.0/24`로 갈 때 router의 public side를 next hop으로 사용하게 한다.

```bash
sudo ip netns exec app-server ip route add 10.10.2.0/24 via 10.10.1.1 dev eth0
```

확인한다.

```bash
sudo ip netns exec app-server ip route
```

예상 결과:

```text
10.10.2.0/24 via 10.10.1.1 dev eth0
```

### 7. database route 추가

database가 `10.10.1.0/24`로 응답할 때 router의 db side를 next hop으로 사용하게 한다.

```bash
sudo ip netns exec database ip route add 10.10.1.0/24 via 10.10.2.1 dev eth0
```

확인한다.

```bash
sudo ip netns exec database ip route
```

예상 결과:

```text
10.10.1.0/24 via 10.10.2.1 dev eth0
```

## 접근 확인

### 1. app-server에서 router public side 확인

```bash
sudo ip netns exec app-server ping -c 2 10.10.1.1
```

예상 결과:

```text
성공
```

### 2. database에서 router db side 확인

```bash
sudo ip netns exec database ping -c 2 10.10.2.1
```

예상 결과:

```text
성공
```

### 3. app-server에서 database ping 확인

```bash
sudo ip netns exec app-server ping -c 2 10.10.2.10
```

예상 결과:

```text
성공
```

### 4. app-server에서 database 3306 접근 확인

VPC VM에서 실행해 database 3306 연결을 확인한다.

```bash
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 unreachable"'
```

예상 결과:

```text
database 3306 reachable
```

### 5. Host Browser에서 app-server 직접 접근

Host 브라우저에서 아래 주소로 접근한다.

```text
http://192.168.56.2
```

예상 결과:

```text
실패가 정상
```

이유:

```text
Subnet 사이 local routing은 구성했지만 Internet Gateway 역할의 DNAT는 아직 구성하지 않았다.
```

## 흐름 정리

app-server에서 database로 가는 패킷 흐름은 다음과 같다.

```text
app-server 10.10.1.10
  -> next hop 10.10.1.1
  -> router namespace
  -> eth-db 10.10.2.1
  -> database 10.10.2.10
```

database가 응답하는 흐름은 다음과 같다.

```text
database 10.10.2.10
  -> next hop 10.10.2.1
  -> router namespace
  -> eth-public 10.10.1.1
  -> app-server 10.10.1.10
```

AWS 개념상으로는 `10.10.0.0/16 -> local` route에 가깝다.

Linux에서는 이를 재현하기 위해 각 namespace에 구체적인 next hop route를 추가했다.

## 정리 명령

다시 구성하고 싶으면 아래 순서로 삭제한다.

```bash
sudo ip netns exec app-server ip route del 10.10.2.0/24 via 10.10.1.1 dev eth0
sudo ip netns exec database ip route del 10.10.1.0/24 via 10.10.2.1 dev eth0
sudo ip netns delete router
```

또는 [clean.sh](./clean.sh)를 사용할 수 있다.

```bash
./clean.sh
```

router namespace를 삭제하면 router에 연결된 veth pair도 함께 제거된다.

## 완료 기준

```text
router namespace 생성 확인
router eth-public에 10.10.1.1/24 할당 확인
router eth-db에 10.10.2.1/24 할당 확인
router namespace IP forwarding 활성화 확인
app-server route에 10.10.2.0/24 via 10.10.1.1 추가 확인
database route에 10.10.1.0/24 via 10.10.2.1 추가 확인
app-server -> database ping 성공
app-server -> database:3306 접근 성공
Host Browser -> app-server 직접 접근 실패 확인
```

## 학습 기록

진행하면서 아래 항목을 기록한다.

```text
router namespace 생성 결과:
router public side 설정 결과:
router db side 설정 결과:
IP forwarding 설정 결과:
app-server route 추가 결과:
database route 추가 결과:
app-server -> database ping 결과:
app-server -> database:3306 접근 결과:
Host Browser -> AppServer 접근 결과:
막힌 부분:
정리한 개념:
```
