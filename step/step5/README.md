# STEP5. Internet Gateway 재현

## 목표

VPC VM의 외부 IP로 들어온 요청을 Public Subnet의 AppServer로 전달한다.

실습에서는 VPC VM의 외부 IP가 Public Endpoint 역할을 한다.

```text
192.168.56.2:80
  -> DNAT
  -> 10.10.1.10:80
```

이번 단계에서는 VPC VM의 host namespace가 Internet Gateway 역할을 한다.

## 구성 매핑

| AWS 개념 | 로컬 실습에서의 대응 |
| --- | --- |
| Internet Gateway | VPC VM host namespace |
| Public Endpoint | `192.168.56.2:80` |
| AppServer Private IP | `10.10.1.10:80` |
| DNAT | host namespace의 iptables nat |
| IGW internal side | `br-public`의 `10.10.1.254/24` |

## 진행 전 확인

Step 4까지 정상이어야 한다.

```bash
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 blocked"'
sudo ip netns exec app-server iptables -S
sudo ip netns exec database iptables -S
```

예상 결과:

```text
database 3306 reachable
app-server INPUT에 80/tcp 허용 규칙 존재
database INPUT에 10.10.1.10 -> 3306/tcp 허용 규칙 존재
```

## 진행 순서

아래 명령은 직접 한 줄씩 실행해도 되고, 같은 내용을 담은 [setup.sh](./setup.sh)를 VPC VM에 복사해서 실행해도 된다.

```bash
chmod +x setup.sh check.sh clean.sh
./setup.sh
./check.sh
```

처음 학습할 때는 수동 명령으로 진행하는 편이 DNAT와 응답 경로를 이해하기 좋다.

### 1. 실습 디렉터리 준비

VPC VM 안에서 Step 5 디렉터리를 준비한다.

```bash
mkdir -p ~/aws-vpc-local-lab/step/step5
cd ~/aws-vpc-local-lab/step/step5
```

### 2. host namespace에서 IP forwarding 활성화

VPC VM host namespace가 패킷을 전달할 수 있게 한다.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

확인한다.

```bash
sysctl net.ipv4.ip_forward
```

예상 결과:

```text
net.ipv4.ip_forward = 1
```

### 3. IGW internal side IP 추가

`br-public`에 IGW 내부 IP 역할의 주소를 추가한다.

```bash
sudo ip addr add 10.10.1.254/24 dev br-public
```

이미 추가되어 있다면 `File exists`가 나올 수 있다. 이 경우는 무시해도 된다.

확인한다.

```bash
ip addr show br-public
```

예상 결과:

```text
10.10.1.254/24
```

### 4. app-server 기본 route 추가

AppServer가 Public Subnet 밖으로 응답할 수 있도록 기본 route를 추가한다.

```bash
sudo ip netns exec app-server ip route replace default via 10.10.1.254 dev eth0
```

확인한다.

```bash
sudo ip netns exec app-server ip route
```

예상 결과:

```text
default via 10.10.1.254 dev eth0
10.10.2.0/24 via 10.10.1.1 dev eth0
```

### 5. DNAT 규칙 추가

Host 또는 외부에서 `192.168.56.2:80`으로 들어온 요청을 `10.10.1.10:80`으로 전달한다.

```bash
sudo iptables -t nat -A PREROUTING -d 192.168.56.2 -p tcp --dport 80 -j DNAT --to-destination 10.10.1.10:80
```

VPC VM 내부에서 `curl http://192.168.56.2`로 확인하는 요청은 local output 경로를 타므로 `OUTPUT`에도 같은 DNAT를 추가한다.

```bash
sudo iptables -t nat -A OUTPUT -d 192.168.56.2 -p tcp --dport 80 -j DNAT --to-destination 10.10.1.10:80
```

확인한다.

```bash
sudo iptables -t nat -S
```

### 6. FORWARD 허용 규칙 추가

VPC VM host namespace가 AppServer로 HTTP 패킷을 전달할 수 있게 한다.

```bash
sudo iptables -A FORWARD -p tcp -d 10.10.1.10 --dport 80 -j ACCEPT
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

확인한다.

```bash
sudo iptables -S FORWARD
```

## 접근 확인

### 1. VPC VM 내부에서 Public Endpoint 접근

VPC VM 안에서 확인한다.

```bash
curl -I http://192.168.56.2
```

예상 결과:

```text
HTTP/1.1 200 OK
```

### 2. Host에서 Public Endpoint 접근

Host 터미널에서 확인한다.

```bash
curl -I http://192.168.56.2
```

또는 브라우저에서 접근한다.

```text
http://192.168.56.2
```

예상 결과:

```text
nginx 응답 성공
```

### 3. Host에서 Database 직접 접근

Host에서 VPC VM의 `3306`으로 접근을 시도한다.

```bash
nc -vz 192.168.56.2 3306
```

예상 결과:

```text
실패가 정상
```

이유:

```text
3306/tcp에 대한 DNAT 규칙을 만들지 않았다.
Database는 Private DB Subnet에 있고 Public Endpoint가 없다.
```

### 4. VPC VM에서 Private DB Subnet 직접 접근

VPC VM host namespace에서 database private IP로 접근을 시도한다.

```bash
timeout 3 bash -c 'cat < /dev/null > /dev/tcp/10.10.2.10/3306' && echo "database direct reachable" || echo "database direct blocked"
```

예상 결과:

```text
database direct blocked
```

이유:

```text
Step 5에서는 Public Endpoint를 AppServer에만 연결했다.
Database Security Group도 10.10.1.10에서 오는 3306/tcp만 허용한다.
```

### 5. app-server에서 database 접근 유지 확인

Step 4의 AppServer -> Database 접근은 계속 성공해야 한다.

```bash
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "database 3306 reachable" || echo "database 3306 blocked"'
```

예상 결과:

```text
database 3306 reachable
```

## 흐름 정리

Host Browser에서 AppServer로 가는 흐름은 다음과 같다.

```text
Host Browser
  -> 192.168.56.2:80
  -> VPC VM host namespace
  -> DNAT
  -> 10.10.1.10:80
  -> app-server nginx
```

응답 흐름은 다음과 같다.

```text
app-server 10.10.1.10
  -> default route 10.10.1.254
  -> VPC VM host namespace
  -> connection tracking reverse NAT
  -> Host Browser
```

## 정리 명령

DNAT와 IGW 설정을 제거하려면 다음을 실행한다.

```bash
sudo iptables -t nat -D PREROUTING -d 192.168.56.2 -p tcp --dport 80 -j DNAT --to-destination 10.10.1.10:80
sudo iptables -t nat -D OUTPUT -d 192.168.56.2 -p tcp --dport 80 -j DNAT --to-destination 10.10.1.10:80
sudo iptables -D FORWARD -p tcp -d 10.10.1.10 --dport 80 -j ACCEPT
sudo iptables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec app-server ip route del default via 10.10.1.254 dev eth0
sudo ip addr del 10.10.1.254/24 dev br-public
```

또는 [clean.sh](./clean.sh)를 사용할 수 있다.

```bash
./clean.sh
```

## 완료 기준

```text
VPC VM host namespace에서 ip_forward=1 확인
br-public에 10.10.1.254/24 추가 확인
app-server default route가 10.10.1.254인지 확인
192.168.56.2:80 -> 10.10.1.10:80 DNAT 규칙 확인
VPC VM 내부에서 curl http://192.168.56.2 성공
Host에서 curl http://192.168.56.2 성공
Host -> Database 직접 접근 실패 확인
VPC VM host namespace -> Database 직접 접근 실패 확인
app-server -> database:3306 접근 유지 확인
```

## 학습 기록

진행하면서 아래 항목을 기록한다.

```text
host ip_forward 설정 결과:
br-public IGW IP 설정 결과:
app-server default route 설정 결과:
DNAT 규칙 설정 결과:
VPC VM -> 192.168.56.2:80 접근 결과:
Host -> 192.168.56.2:80 접근 결과:
Host -> Database 직접 접근 결과:
VPC VM -> Database 직접 접근 결과:
app-server -> database:3306 접근 결과:
막힌 부분:
정리한 개념:
```
