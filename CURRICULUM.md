# CURRICULUM.md

# AWS VPC 네트워크 로컬 재현 커리큘럼

## 1. 학습 목표

본 학습은 AWS VPC의 핵심 네트워크 구성 요소를 로컬 VM 환경에서 재현하는 것을 목표로 한다.

단순히 Docker 컨테이너를 실행하는 것이 아니라, AWS에서 제공하는 다음 개념들이 실제로 어떤 네트워크 역할을 하는지 직접 구성하고 검증한다.

```text
VPC
Subnet
ENI
Route Table
Internet Gateway
Security Group
EC2
RDS
Route53
```

최종적으로 다음 요청 흐름을 만든다.

```text
Host Browser
  -> DNS VM
  -> VPC VM
  -> Internet Gateway 역할
  -> Public Subnet
  -> ENI
  -> Security Group
  -> AppServer
  -> Private DB
```

---

## 2. 실습 환경

본 학습은 Ubuntu Server 22.04 Release로 진행한다.

* 다운로드 링크: https://cdimage.ubuntu.com/releases/22.04/release/

실습은 두 개의 Ubuntu Server VM을 사용한다.

```text
VM 1: VPC VM
  - AWS VPC 역할
  - Subnet, ENI, Route Table, IGW, SG, EC2, RDS 재현

VM 2: DNS VM
  - Route53 역할
  - api.local.test 도메인을 VPC VM의 IP로 응답
```

---

## 3. 전체 구조

```text
Host OS
  - macOS
  - Windows
  - Linux

  |
  | DNS Query: api.local.test
  v

[DNS VM]
  Role: Route53
  api.local.test -> <VPC_VM_IP>

  |
  | HTTP Request: http://api.local.test
  v

[VPC VM]
  External IP: <VPC_VM_IP>

  [Internet Gateway 역할]
    <VPC_VM_IP>:80
      -> DNAT
      -> 10.10.1.10:80

  [Public Subnet]
    CIDR: 10.10.1.0/24
    AppServer ENI: 10.10.1.10

  [VPC Router / Local Route]
    Public side: 10.10.1.1
    DB side:     10.10.2.1

  [Private DB Subnet]
    CIDR: 10.10.2.0/24
    Database ENI: 10.10.2.10
```

---

## 4. 왜 VM을 2개로 나누는가?

Route53과 VPC는 역할이 다르다.

Route53은 도메인 이름을 IP 주소로 변환한다.

VPC는 해당 IP로 들어온 요청을 내부 네트워크 리소스로 전달한다.

따라서 실습에서도 이를 분리한다.

```text
DNS VM
  = Route53 역할

VPC VM
  = AWS VPC 역할
```

이렇게 나누면 다음 흐름을 명확히 확인할 수 있다.

```text
Browser
  -> Route53 역할 DNS VM
  -> VPC 역할 VM
  -> IGW 역할
  -> EC2 역할 AppServer
```

---

## 5. IP 주소 정책

VM의 IP는 UTM, VMware, VirtualBox, Windows 환경에 따라 달라질 수 있다.

따라서 커리큘럼에서는 VM의 실제 IP를 고정값으로 가정하지 않는다.

다음 값을 실습자가 자신의 환경에 맞게 확인해서 사용한다.

```text
<VPC_VM_IP>
  - VPC VM이 Host와 DNS VM에서 접근 가능한 IP
  - 예: 192.168.64.20, 192.168.56.20, 172.16.x.x

<DNS_VM_IP>
  - DNS VM이 Host에서 접근 가능한 IP
  - 예: 192.168.64.10, 192.168.56.10, 172.16.x.x
```

반면 VPC VM 내부의 실습용 VPC 대역은 고정한다.

```text
VPC CIDR:
  10.10.0.0/16

Public Subnet:
  10.10.1.0/24

Private DB Subnet:
  10.10.2.0/24

AppServer Private IP:
  10.10.1.10

Database Private IP:
  10.10.2.10

Router Public Side:
  10.10.1.1

Router DB Side:
  10.10.2.1
```

---

## 6. Public DNS 표현

실제 AWS에서는 Public Route53이 Public IP 또는 공개 엔드포인트를 가리킨다.

이번 실습에서 Host Browser가 접근할 수 있는 공개 엔드포인트는 VPC VM의 외부 IP다.

따라서 DNS VM은 다음처럼 응답한다.

```text
api.local.test -> <VPC_VM_IP>
```

예를 들어 VPC VM의 IP가 `192.168.64.20`이면 다음처럼 응답한다.

```text
api.local.test -> 192.168.64.20
```

주의할 점은 다음과 같다.

```text
203.0.113.10 같은 문서용 Public IP는 개념 설명에는 사용할 수 있지만,
Host Browser가 실제로 접근하려면 Host가 라우팅 가능한 IP를 사용해야 한다.

따라서 이 실습에서는 api.local.test을 <VPC_VM_IP>로 매핑한다.
```

---

## 7. 단계별 커리큘럼

## Step 0. VM 준비

### 목표

VPC VM과 DNS VM을 준비한다.

### 구성

```text
VPC VM:
  Ubuntu Server 22.04
  Docker 설치
  iproute2 설치
  iptables 설치

DNS VM:
  Ubuntu Server 22.04
  DNS 서버 설치 또는 CoreDNS 실행
```

### 확인할 것

```text
VPC VM IP 확인
DNS VM IP 확인
Host에서 VPC VM ping 가능
Host에서 DNS VM ping 가능
DNS VM에서 VPC VM ping 가능
```

---

## Step 1. VPC VM에 AppServer와 Database 실행

### 목표

VPC VM 안에서 EC2 역할의 AppServer와 RDS 역할의 Database를 실행한다.

Docker는 애플리케이션 프로세스를 실행하는 용도로만 사용한다.

네트워크는 Docker Compose에 맡기지 않는다.

### 구성

```text
app-server container
  역할: EC2
  프로세스: nginx
  네트워크: 직접 구성 예정

database container
  역할: RDS
  프로세스: MySQL
  네트워크: 직접 구성 예정
```

### 학습 개념

```text
EC2
RDS
Docker container
Process
```

---

## Step 2. VPC / Subnet / ENI 재현

### 목표

AWS VPC 내부의 Subnet과 ENI를 Linux 기능으로 재현한다.

### 매핑

```text
VPC
  = VPC VM 내부의 전체 실습 네트워크

Subnet
  = Linux bridge

ENI
  = veth pair

EC2
  = app-server container

RDS
  = database container
```

### 구성

```text
Public Subnet:
  bridge: br-public
  CIDR: 10.10.1.0/24
  app-server ENI: 10.10.1.10

Private DB Subnet:
  bridge: br-private-db
  CIDR: 10.10.2.0/24
  database ENI: 10.10.2.10
```

### 성공해야 하는 것

```text
app-server 컨테이너에 10.10.1.10 할당
database 컨테이너에 10.10.2.10 할당
app-server 내부에서 nginx 응답 확인
database 내부에서 MySQL 실행 확인
```

### 실패해야 하는 것

```text
Host Browser -> app-server 직접 접근 실패
app-server -> database 접근 실패
```

아직 Route Table과 IGW를 구성하지 않았으므로 위 실패가 정상이다.

---

## Step 3. VPC Router / Local Route 재현

### 목표

VPC 내부의 local routing을 재현한다.

AWS VPC에서는 VPC CIDR에 대한 local route가 기본으로 존재한다.

```text
10.10.0.0/16 -> local
```

이를 Linux에서는 router namespace와 route 설정으로 재현한다.

### 구성

```text
router namespace
  public side: 10.10.1.1/24
  db side:     10.10.2.1/24
```

### Linux 재현 방식

Public Subnet에 있는 AppServer가 Private DB Subnet으로 가려면, 같은 Public Subnet에 있는 router interface로 패킷을 보낸다.

```text
Destination:
  10.10.2.0/24

Next Hop:
  10.10.1.1
```

Private DB Subnet에서 Public Subnet으로 응답할 때는, 같은 Private DB Subnet에 있는 router interface로 패킷을 보낸다.

```text
Destination:
  10.10.1.0/24

Next Hop:
  10.10.2.1
```

주의할 점은 이것이 AWS Route Table의 표현은 아니라는 점이다.

AWS 개념상으로는 다음이 더 정확하다.

```text
VPC Local Route:
  10.10.0.0/16 -> local
```

Linux로 이를 재현하기 위해 next hop IP를 명시하는 것이다.

### 성공해야 하는 것

```text
app-server -> database ping 성공
app-server -> database:3306 접근 성공
```

---

## Step 4. Security Group 재현

### 목표

Security Group을 ENI 단위의 방화벽 규칙으로 재현한다.

Security Group은 라우터가 아니라 ENI에 연결되는 보안 정책으로 이해한다.

### AppServer Security Group

```text
Inbound:
  80/tcp 허용

Outbound:
  3306/tcp to Database 허용
  DNS 허용
```

### Database Security Group

```text
Inbound:
  3306/tcp from AppServer 허용

Outbound:
  established / related 응답 허용
```

### 학습 개념

```text
Security Group
ENI 단위 보안 정책
Inbound Rule
Outbound Rule
Stateful Firewall
```

### 성공해야 하는 것

```text
app-server -> database:3306 접근 성공
```

### 실패해야 하는 것

```text
허용되지 않은 source에서 database:3306 접근 실패
허용되지 않은 port 접근 실패
```

---

## Step 5. Internet Gateway 재현

### 목표

VPC VM의 외부 IP로 들어온 요청을 Public Subnet의 AppServer로 전달한다.

실습에서는 VPC VM의 외부 IP가 Public Endpoint 역할을 한다.

```text
<VPC_VM_IP>:80
  -> DNAT
  -> 10.10.1.10:80
```

### 학습 개념

```text
Internet Gateway
Public Endpoint
Public IP
Private IP
DNAT
```

### 성공해야 하는 것

VPC VM 내부에서 다음 접근이 성공해야 한다.

```text
curl http://<VPC_VM_IP>
```

Host에서 다음 접근이 성공해야 한다.

```text
curl http://<VPC_VM_IP>
```

또는 브라우저에서 다음 접근이 성공해야 한다.

```text
http://<VPC_VM_IP>
```

### 실패해야 하는 것

```text
Host -> Database 직접 접근 실패
Host -> Private DB Subnet 직접 접근 실패
```

---

## Step 6. DNS VM으로 Route53 재현

### 목표

DNS VM을 Route53처럼 사용해 `api.local.test` 도메인을 VPC VM의 외부 IP로 응답하게 한다.

### 구성

```text
DNS VM:
  api.local.test -> <VPC_VM_IP>
```

### Host DNS 설정

Host가 `api.local.test` 질의를 DNS VM으로 보내도록 설정한다.

macOS에서는 특정 도메인만 DNS VM으로 보내도록 다음 방식을 사용할 수 있다.

```text
/etc/resolver/lab.test

nameserver <DNS_VM_IP>
```

Windows에서는 네트워크 어댑터 DNS 서버를 DNS VM IP로 지정하거나, 실습 중에만 DNS 설정을 변경한다.

### 성공해야 하는 것

Host에서 다음 명령이 VPC VM IP를 반환해야 한다.

```text
nslookup api.local.test <DNS_VM_IP>
```

또는:

```text
dig @<DNS_VM_IP> api.local.test
```

이후 브라우저에서 다음 접근이 성공해야 한다.

```text
http://api.local.test
```

---

## Step 7. 최종 요청 흐름 검증

최종적으로 다음 흐름이 성립해야 한다.

```text
Host Browser
  -> api.local.test DNS 조회
  -> DNS VM이 <VPC_VM_IP> 반환
  -> Host Browser가 <VPC_VM_IP>:80으로 HTTP 요청
  -> VPC VM의 IGW 역할 규칙이 요청 수신
  -> 10.10.1.10:80으로 DNAT
  -> AppServer nginx 응답
```

AppServer가 Database에 접근하는 흐름은 다음과 같다.

```text
AppServer
  -> Database Private IP 또는 Private DNS
  -> VPC local routing
  -> Database Security Group
  -> MySQL
```

---

## 8. 최종 성공 기준

성공해야 하는 것:

```text
Host -> api.local.test -> AppServer 접근 성공
AppServer -> Database:3306 접근 성공
AppServer -> Database query 성공
```

실패해야 하는 것:

```text
Host -> Database 직접 접근 실패
Host -> Private DB Subnet 직접 접근 실패
허용되지 않은 port 접근 실패
```

---

## 9. 제외하는 개념

이번 커리큘럼에서는 다음 개념을 제외한다.

```text
VyOS
RIP
OSPF
Mail Server
NAT Gateway
```

제외 이유는 다음과 같다.

```text
VyOS:
  이번 목표는 라우터 OS 사용법이 아니라 AWS VPC 리소스 모델 재현이다.

RIP / OSPF:
  일반적인 AWS VPC 기초 실습에서 사용자가 직접 다루는 개념이 아니다.

Mail Server:
  VPC 구조 이해의 핵심이 아니다.

NAT Gateway:
  Private Subnet의 리소스가 외부 인터넷으로 나갈 때 필요하다.
  이번 핵심 흐름은 Host -> AppServer, AppServer -> Database이므로 필수 범위에서 제외한다.
```

---

## 10. 핵심 정리

이번 학습은 두 VM을 사용한다.

```text
DNS VM
  = Route53 역할

VPC VM
  = VPC 역할
```

VPC VM 내부에서는 Linux 네트워크 기능으로 AWS VPC 구성 요소를 재현한다.

```text
Linux bridge
  = Subnet

veth pair
  = ENI

network namespace
  = Router / IGW 격리 공간

iptables / nftables
  = Security Group / DNAT 규칙
```

최종적으로 사용자는 브라우저에서 다음 주소로 접근한다.

```text
http://api.local.test
```

그리고 내부적으로는 다음 흐름이 동작한다.

```text
api.local.test
  -> DNS VM
  -> VPC VM
  -> IGW 역할
  -> AppServer
  -> Database
```
