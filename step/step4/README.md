# STEP4. Security Group 재현

## 목표

Security Group을 ENI 단위의 방화벽 규칙으로 재현한다.

Step 3까지 만든 VPC local routing은 유지하고, 이번 단계에서는 `app-server`와 `database` namespace에 iptables 규칙을 적용한다.

Security Group은 라우터가 아니라 ENI에 연결되는 보안 정책으로 이해한다.

## 구성 매핑

| AWS 개념 | 로컬 실습에서의 대응 |
| --- | --- |
| AppServer Security Group | `app-server` namespace의 iptables |
| Database Security Group | `database` namespace의 iptables |
| Inbound Rule | iptables `INPUT` chain |
| Outbound Rule | iptables `OUTPUT` chain |
| Stateful 응답 허용 | `conntrack --ctstate ESTABLISHED,RELATED` |

## Security Group 정책

### AppServer Security Group

| 방향 | 규칙 |
| --- | --- |
| Inbound | `80/tcp` 허용 |
| Outbound | `10.10.2.10:3306/tcp` 허용 |
| Outbound | DNS `53/tcp`, `53/udp` 허용 |
| 양방향 | established / related 허용 |

### Database Security Group

| 방향 | 규칙 |
| --- | --- |
| Inbound | `10.10.1.10`에서 오는 `3306/tcp` 허용 |
| Outbound | established / related 응답 허용 |

## 진행 전 확인

Step 3까지 정상이어야 한다.

```bash
sudo ip netns exec app-server ping -c 2 10.10.2.10
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 unreachable"'
```

예상 결과:

```text
ping 성공
database 3306 reachable
```

## 진행 순서

아래 명령은 직접 한 줄씩 실행해도 되고, 같은 내용을 담은 [setup.sh](./setup.sh)를 VPC VM에 복사해서 실행해도 된다.

```bash
chmod +x setup.sh check.sh clean.sh
./setup.sh
./check.sh
```

처음 학습할 때는 수동 명령으로 진행하는 편이 Security Group의 inbound/outbound 방향을 이해하기 좋다.

### 1. 실습 디렉터리 준비

VPC VM 안에서 Step 4 디렉터리를 준비한다.

```bash
mkdir -p ~/aws-vpc-local-lab/step/step4
cd ~/aws-vpc-local-lab/step/step4
```

### 2. app-server Security Group 적용

기존 규칙을 비우고 기본 정책을 `DROP`으로 설정한다.

```bash
sudo ip netns exec app-server iptables -F
sudo ip netns exec app-server iptables -X
sudo ip netns exec app-server iptables -P INPUT DROP
sudo ip netns exec app-server iptables -P OUTPUT DROP
sudo ip netns exec app-server iptables -P FORWARD DROP
```

loopback과 stateful 응답을 허용한다.

```bash
sudo ip netns exec app-server iptables -A INPUT -i lo -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -o lo -j ACCEPT
sudo ip netns exec app-server iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

AppServer inbound `80/tcp`를 허용한다.

```bash
sudo ip netns exec app-server iptables -A INPUT -p tcp --dport 80 -j ACCEPT
```

AppServer outbound에서 Database `3306/tcp`와 DNS를 허용한다.

```bash
sudo ip netns exec app-server iptables -A OUTPUT -p tcp -d 10.10.2.10 --dport 3306 -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo ip netns exec app-server iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
```

확인한다.

```bash
sudo ip netns exec app-server iptables -S
```

### 3. database Security Group 적용

기존 규칙을 비우고 기본 정책을 `DROP`으로 설정한다.

```bash
sudo ip netns exec database iptables -F
sudo ip netns exec database iptables -X
sudo ip netns exec database iptables -P INPUT DROP
sudo ip netns exec database iptables -P OUTPUT DROP
sudo ip netns exec database iptables -P FORWARD DROP
```

loopback과 stateful 응답을 허용한다.

```bash
sudo ip netns exec database iptables -A INPUT -i lo -j ACCEPT
sudo ip netns exec database iptables -A OUTPUT -o lo -j ACCEPT
sudo ip netns exec database iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec database iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

Database inbound에서 AppServer의 `3306/tcp` 접근만 허용한다.

```bash
sudo ip netns exec database iptables -A INPUT -p tcp -s 10.10.1.10 --dport 3306 -j ACCEPT
```

확인한다.

```bash
sudo ip netns exec database iptables -S
```

## 접근 확인

### 1. app-server에서 database 3306 접근

```bash
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 blocked"'
```

예상 결과:

```text
database 3306 reachable
```

### 2. app-server에서 database ping 확인

```bash
sudo ip netns exec app-server ping -c 2 10.10.2.10
```

예상 결과:

```text
실패가 정상
```

이유:

```text
Security Group에 ICMP 허용 규칙을 추가하지 않았다.
Step 3에서는 ping이 성공했지만 Step 4부터는 허용된 트래픽만 통과한다.
```

### 3. 허용되지 않은 source에서 database 3306 접근

router namespace에서 database `3306/tcp` 접근을 시도한다.

```bash
sudo ip netns exec router bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "router source allowed" || echo "router source blocked"'
```

예상 결과:

```text
router source blocked
```

이유:

```text
Database Security Group은 10.10.1.10에서 오는 3306/tcp만 허용한다.
router namespace의 source IP는 허용 대상이 아니다.
```

### 4. 허용되지 않은 port 접근

app-server에서 database의 허용되지 않은 port로 접근을 시도한다.

```bash
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3307" && echo "database 3307 reachable" || echo "database 3307 blocked"'
```

예상 결과:

```text
database 3307 blocked
```

이유:

```text
AppServer outbound는 10.10.2.10:3306/tcp만 허용한다.
Database inbound도 3306/tcp만 허용한다.
```

### 5. database MySQL 프로세스 확인

local loopback은 허용했기 때문에 `docker exec`로 MySQL 상태 확인은 가능해야 한다.

```bash
docker exec database mysqladmin ping -uroot -plocalpass
```

예상 결과:

```text
mysqld is alive
```

## 정리 명령

Security Group 규칙을 지우고 기본 허용 상태로 되돌리려면 다음을 실행한다.

```bash
sudo ip netns exec app-server iptables -P INPUT ACCEPT
sudo ip netns exec app-server iptables -P OUTPUT ACCEPT
sudo ip netns exec app-server iptables -P FORWARD ACCEPT
sudo ip netns exec app-server iptables -F
sudo ip netns exec app-server iptables -X

sudo ip netns exec database iptables -P INPUT ACCEPT
sudo ip netns exec database iptables -P OUTPUT ACCEPT
sudo ip netns exec database iptables -P FORWARD ACCEPT
sudo ip netns exec database iptables -F
sudo ip netns exec database iptables -X
```

또는 [clean.sh](./clean.sh)를 사용할 수 있다.

```bash
./clean.sh
```

## 완료 기준

```text
app-server namespace에 iptables 규칙 적용 확인
database namespace에 iptables 규칙 적용 확인
app-server -> database:3306 접근 성공
app-server -> database ping 실패 확인
router source -> database:3306 접근 실패 확인
app-server -> database:3307 접근 실패 확인
database MySQL 프로세스 정상 확인
```

## 학습 기록

진행하면서 아래 항목을 기록한다.

```text
app-server Security Group 적용 결과:
database Security Group 적용 결과:
app-server -> database:3306 접근 결과:
app-server -> database ping 결과:
router source -> database:3306 접근 결과:
app-server -> database:3307 접근 결과:
막힌 부분:
정리한 개념:
```
