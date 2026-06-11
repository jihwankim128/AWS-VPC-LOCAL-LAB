# STEP2. VPC / Subnet / ENI 재현

## 목표

AWS VPC 내부의 Subnet과 ENI를 Linux 기능으로 재현한다.

Step 1에서 실행한 `app-server`, `database` 컨테이너에 직접 네트워크 인터페이스를 붙인다.

이번 단계에서는 다음까지만 구성한다.

```text
Public Subnet bridge 생성
Private DB Subnet bridge 생성
app-server 컨테이너에 10.10.1.10 할당
database 컨테이너에 10.10.2.10 할당
```

아직 VPC Router, Route Table, Internet Gateway, Security Group은 구성하지 않는다.

## 구성 매핑

| AWS 개념 | 로컬 실습에서의 대응 |
| --- | --- |
| VPC | VPC VM 내부의 전체 실습 네트워크 |
| Public Subnet | `br-public` Linux bridge |
| Private DB Subnet | `br-private-db` Linux bridge |
| ENI | veth pair |
| EC2 | `app-server` 컨테이너 |
| RDS | `database` 컨테이너 |

## IP 계획

| 대상 | 값 |
| --- | --- |
| Public Subnet | `10.10.1.0/24` |
| Private DB Subnet | `10.10.2.0/24` |
| AppServer ENI | `10.10.1.10/24` |
| Database ENI | `10.10.2.10/24` |

## 진행 전 확인

VPC VM에 접속한다.

```bash
ssh if@192.168.56.2
```

Step 1에서의 컨테이너가 떠 있어야 한다.

```bash
docker ps
```

확인할 컨테이너:

```text
app-server
database
```

## 진행 순서

아래 명령은 직접 한 줄씩 실행해도 되고, 같은 내용을 담은 [setup.sh](./setup.sh)를 VPC VM에 복사해서 실행해도 된다.

```bash
chmod +x setup.sh check.sh clean.sh
./setup.sh
./check.sh
```

처음 학습할 때는 수동 명령으로 진행하는 편이 각 Linux 네트워크 객체를 이해하기 좋다.

### 1. 실습 디렉터리 준비

VPC VM 안에서 Step 2 디렉터리를 준비한다.

```bash
mkdir -p ~/aws-vpc-local-lab/step/step2
cd ~/aws-vpc-local-lab/step/step2
```

### 2. 컨테이너 network namespace 등록

Docker 컨테이너의 network namespace를 `ip netns` 명령으로 다룰 수 있게 연결한다.

```bash
APP_PID=$(docker inspect -f '{{.State.Pid}}' app-server)
DB_PID=$(docker inspect -f '{{.State.Pid}}' database)

sudo mkdir -p /var/run/netns
sudo ln -sfT /proc/${APP_PID}/ns/net /var/run/netns/app-server
sudo ln -sfT /proc/${DB_PID}/ns/net /var/run/netns/database

ip netns list
```

예상 결과:

```text
app-server
database
```

### 3. Subnet 역할 bridge 생성

Public Subnet과 Private DB Subnet에 해당하는 bridge를 만든다.

```bash
sudo ip link add br-public type bridge
sudo ip link set br-public up

sudo ip link add br-private-db type bridge
sudo ip link set br-private-db up
```

확인한다.

```bash
ip link show br-public
ip link show br-private-db
```

### 4. AppServer ENI 생성

`veth-app-host`는 VPC VM 쪽 인터페이스이고, `eth0`는 app-server 컨테이너 안의 ENI 역할이다.

```bash
sudo ip link add veth-app-host type veth peer name veth-app
sudo ip link set veth-app-host master br-public
sudo ip link set veth-app-host up

sudo ip link set veth-app netns app-server
sudo ip netns exec app-server ip link set veth-app name eth0
sudo ip netns exec app-server ip addr add 10.10.1.10/24 dev eth0
sudo ip netns exec app-server ip link set eth0 up
sudo ip netns exec app-server ip link set lo up
```

확인한다.

```bash
sudo ip netns exec app-server ip addr show eth0
```

예상 결과:

```text
inet 10.10.1.10/24 포함
```

### 5. Database ENI 생성

`veth-db-host`는 VPC VM 쪽 인터페이스이고, `eth0`는 database 컨테이너 안의 ENI 역할이다.

```bash
sudo ip link add veth-db-host type veth peer name veth-db
sudo ip link set veth-db-host master br-private-db
sudo ip link set veth-db-host up

sudo ip link set veth-db netns database
sudo ip netns exec database ip link set veth-db name eth0
sudo ip netns exec database ip addr add 10.10.2.10/24 dev eth0
sudo ip netns exec database ip link set eth0 up
sudo ip netns exec database ip link set lo up
```

확인한다.

```bash
sudo ip netns exec database ip addr show eth0
```

예상 결과:

```text
inet 10.10.2.10/24 포함
```

## 접근 확인

### 1. app-server 내부 nginx 확인

VPC VM에서 app-server namespace 안의 nginx에 접근한다.

```bash
sudo ip netns exec app-server curl -I http://10.10.1.10
```

예상 결과:

```text
HTTP/1.1 200 OK
```

### 2. database 내부 MySQL 확인

기존 Docker exec로 MySQL 프로세스를 확인한다.

```bash
docker exec database mysqladmin ping -uroot -plocalpass
```

예상 결과:

```text
mysqld is alive
```

### 3. Host Browser에서 app-server 직접 접근

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
아직 Internet Gateway 역할의 DNAT를 구성하지 않았다.
VPC VM 외부 IP 192.168.56.2:80이 10.10.1.10:80으로 연결되지 않는다.
```

### 4. app-server에서 database 접근

app-server에서 database IP로 ping을 시도한다.

```bash
sudo ip netns exec app-server ping -c 2 10.10.2.10
```

예상 결과:

```text
실패가 정상
```

이유:

```text
app-server는 10.10.1.0/24에 있다.
database는 10.10.2.0/24에 있다.
아직 두 Subnet 사이를 연결하는 VPC Router와 Route Table을 구성하지 않았다.
```

## 정리 명령

다시 구성하고 싶으면 아래 순서로 삭제한다.

```bash
sudo ip link delete br-public
sudo ip link delete br-private-db
sudo rm -f /var/run/netns/app-server
sudo rm -f /var/run/netns/database
```

또는 [clean.sh](./clean.sh)를 사용할 수 있다.

```bash
./clean.sh
```

bridge를 삭제하면 bridge에 연결된 host 쪽 veth도 함께 삭제된다.

컨테이너를 다시 만들었다면 Step 2도 다시 수행해야 한다.

## 완료 기준

```text
br-public bridge 생성 확인
br-private-db bridge 생성 확인
app-server eth0에 10.10.1.10/24 할당 확인
database eth0에 10.10.2.10/24 할당 확인
app-server namespace에서 nginx 응답 확인
database MySQL 프로세스 확인
Host Browser -> app-server 직접 접근 실패 확인
app-server -> database 접근 실패 확인
```

## 학습 기록

진행하면서 아래 항목을 기록한다.

```text
br-public 생성 결과:
br-private-db 생성 결과:
app-server ENI 생성 결과:
database ENI 생성 결과:
app-server nginx 확인 결과:
database MySQL 확인 결과:
Host Browser -> AppServer 접근 결과:
app-server -> database 접근 결과:
막힌 부분:
정리한 개념:
```
