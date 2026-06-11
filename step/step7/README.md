# STEP7. 최종 Simple AWS Infra 재현

## 목표

Host Browser에서 `api.local.test`로 접근했을 때 AppServer 응답까지 도달하는 최종 흐름을 검증한다.

이번 단계에서는 기존 nginx AppServer를 EC2 역할의 Ubuntu 컨테이너로 교체한다.

새 AppServer 컨테이너는 계속 부팅되어 있는 EC2처럼 유지한다.

그 Ubuntu 안에 접속해서 웹 애플리케이션을 실행하고, RDS 역할의 MySQL Database에 접속해서 저장된 HTML 내용을 조회한 뒤 브라우저에 보여준다.

또한 이번 단계에서 외부 주소를 역할별로 분리한다.

```text
192.168.56.2
  - VPC VM 관리용 Address
  - ssh if@192.168.56.2

192.168.56.3
  - AppServer EC2 Public Address 역할
  - http://192.168.56.3

10.10.1.10
  - AppServer EC2 Private IP

10.10.2.10
  - Database RDS Private IP
```

```text
Host Browser
  -> http://api.local.test
  -> DNS VM
  -> VPC VM IGW
  -> AppServer EC2 Container
  -> Database RDS Container
  -> DB content를 HTML로 렌더링
```

주의:

```text
app-server 컨테이너를 교체하면 Docker 컨테이너 PID와 network namespace가 바뀐다.
따라서 Step 2~5의 네트워크 설정을 다시 적용해야 한다. (복습!)
```

## 구성 매핑

| AWS 개념 | 로컬 실습에서의 대응 |
| --- | --- |
| EC2 AppServer | 계속 실행되는 Ubuntu 컨테이너 |
| RDS | MySQL 컨테이너 |
| App Deploy | Ubuntu 컨테이너 내부에서 실행하는 Flask 앱 |
| App -> RDS 연결 | `10.10.2.10:3306` |
| VPC 관리 접속 | `ssh if@192.168.56.2` |
| EC2 HTTP Public Access | `api.local.test -> 192.168.56.3 -> 10.10.1.10:80` |

## Step 7 산출물

| 파일 | 역할 |
| --- | --- |
| [vpc/docker-compose.yml](./vpc/docker-compose.yml) | VPC VM에서 실행할 AppServer, Database 실행 명세 |
| [vpc/app-server/Dockerfile](./vpc/app-server/Dockerfile) | Ubuntu 기반 AppServer 이미지 |
| [vpc/app-server/app.py](./vpc/app-server/app.py) | DB 조회 후 HTML 렌더링 |
| [vpc/database/init/001-content.sql](./vpc/database/init/001-content.sql) | DB 테이블과 화면 표시 데이터 생성 |
| [vpc/reapply-network.sh](./vpc/reapply-network.sh) | VPC VM에서 내부 VPC 네트워크, router, security group 재구성 |
| [vpc/publish-app-server.sh](./vpc/publish-app-server.sh) | 별도 단계로 EC2 Public Address와 HTTP DNAT 구성 |
| [vpc/start-app.sh](./vpc/start-app.sh) | VPC VM에서 Ubuntu AppServer 내부 웹앱 실행 |
| [vpc/check.sh](./vpc/check.sh) | VPC VM 최종 검증 |
| [dns/Corefile](./dns/Corefile) | DNS VM에서 사용할 Step 7 DNS 레코드 |
| [dns/docker-compose.yml](./dns/docker-compose.yml) | DNS VM에서 실행할 CoreDNS 명세 |
| [dns/setup.sh](./dns/setup.sh) | DNS VM에서 Step 7 CoreDNS 실행 |
| [dns/check.sh](./dns/check.sh) | DNS VM에서 Step 7 DNS 응답 확인 |

## 진행 전 확인

Step 6까지 성공한 상태여야 한다.

Host에서 DNS와 HTTP 접근이 동작하는지 확인한다.

```bash
dig @192.168.56.6 api.local.test +short
curl -I http://api.local.test
```

예상 결과:

```text
192.168.56.2
HTTP/1.1 200 OK
```

Step 7을 적용하면 DNS 응답을 `192.168.56.3`으로 변경한다.

## 진행 순서

먼저 VPC VM에서 AppServer와 Database를 교체한다.

### 1. VPC VM 파일 준비

VPC VM에 Step 7 VPC 디렉터리를 준비한다.

```bash
mkdir -p ~/aws-vpc-local-lab/step/step7
cd ~/aws-vpc-local-lab/step/step7
```

Host의 Step 7 VPC 파일들을 VPC VM의 같은 경로에 작성한다.

저장소에서는 `step/step7/vpc/` 아래에 있지만, VPC VM 안에서는 아래 파일들을 `~/aws-vpc-local-lab/step/step7/` 바로 아래에 둔다.

HTTP 최종 요청 흐름까지 필요한 기본 디렉토리 구조:

```text
if@custom-vpc:~/aws-vpc-local-lab/step/step7/
├── app-server/
│   ├── app.py
│   └── Dockerfile
├── database/
│   └── init/
│       └── 001-content.sql
├── docker-compose.yml
├── clean.sh
├── check.sh
├── publish-app-server.sh
├── start-app.sh
└── reapply-network.sh
```

### 2. 기존 Step 1 컨테이너 교체

기존 `app-server`, `database` 컨테이너를 Step 7용 컨테이너로 교체한다.
* 주의: 새로운 [step/step7/vpc/docker-compose.yml](./vpc/docker-compose.yml)이 꼭 필요하다.
  * vpc vm 내부 `~/aws-vpc-local-lab/step/step7`에 존재해야 됨.

```bash
cd ~/aws-vpc-local-lab/step/step7
docker-compose down
docker rm -f app-server database 2>/dev/null || true
docker-compose up -d --build
```

확인한다.

```bash
docker ps
docker logs app-server --tail 30
docker logs database --tail 30
```

이 시점의 `app-server`는 계속 실행 중인 Ubuntu 컨테이너다.

처음에는 VPC VM에서 Docker exec로 접속해 확인한다.

```bash
docker exec -it app-server bash
```

컨테이너 안에서 확인하면 `/app/app.py`가 준비되어 있다.

```bash
ls -la /app
python3 --version
```

### 3. DB 초기화 확인

MySQL 초기화가 끝날 때까지 잠시 기다린 뒤 확인한다.

```bash
docker exec database mysqladmin ping -uroot -plocalpass
docker exec database mysql -uroot -plocalpass appdb -e 'select id, title from page_contents;'
```

예상 결과:

```text
mysqld is alive
AWS VPC Local Lab
```

### 4. 내부 VPC 네트워크 재적용

컨테이너가 새로 만들어졌으므로 network namespace 연결, bridge, router, security group 설정을 다시 적용한다.

Step 7에는 이를 한 번에 수행하는 [vpc/reapply-network.sh](./vpc/reapply-network.sh)를 둔다.

```bash
chmod +x reapply-network.sh clean.sh
./reapply-network.sh
```

`sudo` password를 물어보면 VPC VM 계정 비밀번호 `0000`을 입력한다.

`reapply-network.sh`는 이전 Step 2~5의 `setup.sh`, `clean.sh`를 참조하지 않는다.

따라서 Step 7 VPC 파일만 위 구조대로 준비하면 네트워크를 다시 구성할 수 있다.

여기서는 아직 Host에서 접근할 수 있는 `192.168.56.3` public endpoint를 만들지 않는다.

이 스크립트는 다음을 다시 구성한다.

```text
Step 2: app-server 10.10.1.10, database 10.10.2.10
Step 3: router namespace, local route
Step 4: Security Group
```

재적용 후 bridge와 AppServer IP를 확인한다.

```bash
ip -br link show dev br-public
ip -br link show dev veth-app-host
sudo ip netns exec app-server ip -br addr show eth0
sudo ip netns exec app-server ip route
```

예상 결과:

```text
br-public      UP
veth-app-host  UP
eth0           UP 10.10.1.10/24
```

### 5. AppServer EC2 Public Address 게시

이번 단계는 내부 VPC 구성이 끝난 뒤 진행하는 별도 내용이다.

AppServer의 HTTP 서비스를 외부에서 접근할 수 있게 하기 위해 [vpc/publish-app-server.sh](./vpc/publish-app-server.sh)를 실행한다.

```bash
chmod +x publish-app-server.sh
./publish-app-server.sh
```

이 스크립트는 다음을 구성한다.

```text
Step 5: IGW internal IP 10.10.1.254
Step 7: AppServer Public IP alias 192.168.56.3
Step 7: HTTP DNAT 192.168.56.3:80 -> 10.10.1.10:80
```

Step 5에서 만들었던 `192.168.56.2:80 -> 10.10.1.10:80` DNAT가 남아 있으면 제거한다.

이후 역할은 다음처럼 분리된다.

```text
192.168.56.2
  - VPC VM 관리용

192.168.56.3
  - EC2 AppServer public endpoint
```

게시 결과를 확인한다.

```bash
ip -br addr show | grep 192.168.56.3
ip -br addr show dev br-public
sudo ip netns exec app-server ip route
sudo iptables -t nat -S | grep '192.168.56.3/32.*dport 80'
```

예상 결과:

```text
enp0s1 ... 192.168.56.3/24
br-public ... 10.10.1.254/24
default via 10.10.1.254 dev eth0
DNAT --to-destination 10.10.1.10:80
```

아직 Flask 앱을 실행하지 않았다면 `http://192.168.56.3` 접속은 실패할 수 있다.

HTTP 화면 확인은 Step 8에서 앱을 실행한 뒤 진행한다.

### 6. DNS 레코드 변경

Step 6에서는 `api.local.test -> 192.168.56.2`였다.

Step 7에서는 AppServer EC2 Public Address를 분리했으므로 DNS VM의 CoreDNS 설정을 다음처럼 바꾼다.

```text
api.local.test -> 192.168.56.3
```

DNS VM에 Step 7 DNS 파일을 준비한다.

```bash
mkdir -p ~/aws-vpc-local-lab/step/step7
cd ~/aws-vpc-local-lab/step/step7
```

Host의 [dns/Corefile](./dns/Corefile), [dns/docker-compose.yml](./dns/docker-compose.yml)을 DNS VM의 같은 경로에 작성한 뒤 CoreDNS를 실행한다.

Step 6에서 사용하던 `route53-dns` 컨테이너가 남아 있으면 이름이 충돌한다.

Step 7의 `setup.sh`는 기존 `route53-dns` 컨테이너를 제거한 뒤 새 DNS 설정으로 다시 실행한다.

DNS VM 디렉토리 구조:

```text
if@custom-dns:~/aws-vpc-local-lab/step/step7/
├── Corefile
├── docker-compose.yml
├── clean.sh
├── check.sh
└── setup.sh
```

```bash
chmod +x setup.sh check.sh clean.sh
./setup.sh
```

Host에서 확인한다.

```bash
dig @192.168.56.6 api.local.test +short
```

예상 결과:

```text
192.168.56.3
```

### 7. Host에서 AppServer Ubuntu로 SSH 접속

이 단계의 목적은 Host에서 EC2 역할의 Ubuntu 컨테이너로 직접 SSH 접속하는 흐름을 만드는 것이다.

여기서부터 SSH 접속을 위한 추가 설정을 진행한다.

이전 단계까지는 HTTP 요청 흐름만 열었다.

SSH 접속에는 다음 두 파일이 추가로 필요하다.

```text
publish-app-ssh.sh
install-ssh-key.sh
```

두 파일은 Host 저장소의 `step/step7/vpc/` 아래에 있다.

VPC VM에서는 아래 위치에 둔다.

```text
~/aws-vpc-local-lab/step/step7/publish-app-ssh.sh
~/aws-vpc-local-lab/step/step7/install-ssh-key.sh
```

흐름은 다음과 같다.

```text
Host
  -> ssh -i local-keys/app-server-key ubuntu@192.168.56.3
  -> AppServer EC2 Public Address
  -> VPC VM이 192.168.56.3을 수신
  -> DNAT
  -> app-server 10.10.1.10:22
  -> Ubuntu 컨테이너 내부 shell
```

```text
192.168.56.3:22
  -> DNAT
  -> 10.10.1.10:22
```

먼저 `192.168.56.3:22 -> 10.10.1.10:22` DNAT를 연다.
VPC VM의 Step 7 디렉터리에 [./step/step7/vpc/publish-app-ssh.sh](./vpc/publish-app-ssh.sh) 파일을 준비한 뒤 실행 권한을 부여한다.

```bash
cd ~/aws-vpc-local-lab/step/step7
chmod +x publish-app-ssh.sh
./publish-app-ssh.sh
```

#### 1. key pair 생성 전 SSH 시도

key pair를 만들기 전에 아래처럼 먼저 접속을 시도해볼 수 있다.

```bash
ssh ubuntu@192.168.56.3
```

이때 이전에 `192.168.56.3`을 다른 SSH 서버로 사용한 적이 있으면, key 인증 단계까지 가기 전에 아래 경고가 먼저 나올 수 있다.

```text
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Host key verification failed.
```

이 경고는 Host의 `~/.ssh/known_hosts`에 저장된 `192.168.56.3`의 기존 SSH host key와, 현재 AppServer Ubuntu 컨테이너의 SSH host key가 다르기 때문에 발생한다.

이번 실습에서는 `192.168.56.3`을 EC2 Public Address처럼 재사용하므로 자연스럽게 경험할 수도 있다.

Host가 macOS인 경우 터미널에서 기존 항목을 지우면 된다.

```bash
ssh-keygen -R 192.168.56.3
```

그 다음 다시 key 없이 접속을 시도한다.

```bash
ssh ubuntu@192.168.56.3
```

이 단계에서는 아직 전용 key를 등록하지 않았으므로 접속이 실패해야 정상이다.

```text
Permission denied (publickey).
```

이때 password 입력 프롬프트가 나오면 AppServer Ubuntu의 SSH 설정이 아직 AWS EC2 방식으로 정리되지 않은 것이다.

Step 7의 AppServer는 password 인증을 사용하지 않고 public key 인증만 허용한다.

이제 AWS EC2처럼 전용 key pair를 만들고, AppServer의 `authorized_keys`를 그 public key 하나로 덮어쓴다.

#### 2. Host에서 key pair 생성

Host(macOS인 경우) 터미널에서 EC2 key pair처럼 사용할 SSH key를 만든다.

이번 실습에서는 `~/.ssh`가 아니라 저장소 root의 `local-keys/` 아래에 key를 둔다.

이 디렉터리는 `.gitignore`에 등록되어 있어 Git에 올라가지 않는다.

이렇게 하면 Host SSH가 기본 key를 자동으로 찾는 상황과 분리해서, `-i` 옵션으로 지정한 key만 사용하는 흐름을 확인하기 쉽다.

```bash
mkdir -p local-keys
ssh-keygen -t ed25519 -f local-keys/app-server-key -C "aws-vpc-local-lab-app"
chmod 700 local-keys
chmod 600 local-keys/app-server-key
```

생성되는 파일:

```text
local-keys/app-server-key
  - private key
  - Host에만 보관
  - Git에 올리지 않음

local-keys/app-server-key.pub
  - public key
  - AppServer Ubuntu에 등록
```

#### 3. public key를 VPC VM에 복사

Host에서 VPC VM으로 public key만 복사한다.

```bash
scp local-keys/app-server-key.pub if@192.168.56.2:~/aws-vpc-local-lab/step/step7/app-server-key.pub
```

private key는 복사하지 않는다.

#### 4. VPC VM에서 AppServer Ubuntu에 public key 등록

[./step/step7/vpc/install-ssh-key.sh](./vpc/install-ssh-key.sh)를 VPC VM에서 실행한다.

```bash
cd ~/aws-vpc-local-lab/step/step7
chmod +x install-ssh-key.sh
./install-ssh-key.sh
```

`install-ssh-key.sh`는 AppServer Ubuntu의 `/home/ubuntu/.ssh/authorized_keys`를 `app-server-key.pub` 내용으로 덮어쓴다.

또한 AppServer Ubuntu의 SSH 설정을 public key 인증만 허용하도록 정리한다.

즉, 이후에는 이 실습용 private key를 사용하는 접속만 허용된다.

확인하려면 Host에서 key 없이 접속을 다시 시도한다.

```bash
ssh ubuntu@192.168.56.3
```

예상 결과:

```text
Permission denied (publickey).
```

password 입력 프롬프트가 나오면 `install-ssh-key.sh`가 최신 버전인지 확인하고 VPC VM에서 다시 실행한다.

#### 5. Host에서 AppServer Ubuntu로 SSH 접속

Host에서 접속한다.

```bash
ssh -i local-keys/app-server-key ubuntu@192.168.56.3
```

접속 후 확인한다.

```bash
ls -la /app
```

주의:

```text
ssh-keygen -R, ssh -i 명령은 Host macOS에서 실행한다.
install-ssh-key.sh는 VPC VM에서 실행한다.
```

### 8. Ubuntu AppServer 안에서 웹앱 실행

이 단계부터 웹앱 프로세스를 실행한다.

이전 단계까지는 AppServer Ubuntu 컨테이너와 네트워크만 준비된 상태다.

VPC VM에서 [./step/step7/vpc/start-app.sh](./vpc/start-app.sh)를 실행하면 AppServer 컨테이너 내부에서 Flask 앱이 시작된다.

```bash
cd ~/aws-vpc-local-lab/step/step7
chmod +x start-app.sh
./start-app.sh
```

직접 실행하고 싶으면 다음처럼 해도 된다.

```bash
docker exec -d app-server python3 /app/app.py
```

실행 여부를 확인한다.

```bash
docker exec app-server pgrep -af app.py
docker logs app-server --tail 30
```

### 9. AppServer 내부 DB 연결 확인

VPC VM에서 AppServer namespace 안의 웹앱을 직접 확인한다.

```bash
sudo ip netns exec app-server curl -s http://10.10.1.10 | head
```

예상 결과:

```text
AWS VPC Local Lab
DB 연결 성공
```

### 10. Host에서 최종 도메인 접근

Host에서 확인한다.

```bash
curl -s http://api.local.test | grep -E 'AWS VPC Local Lab|DB 연결 성공'
```

또는 브라우저에서 접근한다.

```text
http://api.local.test
```

예상 결과:

```text
DB에 저장된 내용이 HTML 화면에 표시됨
```

## 실패 조건 확인

### 1. Host에서 Database 직접 접근 실패

Host에서 확인한다.

```bash
nc -vz 192.168.56.2 3306
```

예상 결과:

```text
실패가 정상
```

### 2. 허용되지 않은 source에서 Database 접근 실패

VPC VM에서 확인한다.

```bash
sudo ip netns exec router bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3306" && echo "router source allowed" || echo "router source blocked"'
```

예상 결과:

```text
router source blocked
```

### 3. 허용되지 않은 port 접근 실패

VPC VM에서 확인한다.

```bash
sudo ip netns exec app-server bash -lc 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/10.10.2.10/3307" && echo "database 3307 reachable" || echo "database 3307 blocked"'
```

예상 결과:

```text
database 3307 blocked
```

### 4. VPC 관리용 Address로 AppServer HTTP 접근

Step 7부터는 AppServer Public Address를 `192.168.56.3`으로 분리했으므로, `192.168.56.2`는 VPC VM 관리용으로만 본다.

```bash
curl -I http://192.168.56.2
```

예상 결과:

```text
실패가 정상
```

이유:

```text
Step 7에서 192.168.56.2:80 DNAT를 제거했다.
AppServer HTTP 접근은 192.168.56.3:80 또는 api.local.test를 사용한다.
```

## 언어 선택 기준

이번 Step 7의 목적은 웹 프레임워크 학습이 아니라 VPC 전체 흐름 검증이다.

그래서 예제 앱은 Python Flask로 둔다.

| 선택지 | 판단 |
| --- | --- |
| Java 단일 파일 | HTTP 서버와 MySQL 연동을 직접 작성해야 해서 예제가 길어짐 |
| Spring Boot | 실제 서비스 구조에는 좋지만 Gradle/Maven 프로젝트가 필요해서 네트워크 학습 초점이 흐려짐 |
| Node.js | 가능하지만 npm 프로젝트와 의존성 설치가 필요함 |
| Python Flask | 파일 수가 적고 DB 조회 후 HTML 렌더링을 가장 짧게 보여줄 수 있음 |

나중에 Spring Boot로 바꾸려면 같은 Ubuntu AppServer 안에 Java와 jar를 배치하고, `python3 /app/app.py` 대신 `java -jar app.jar`를 실행하면 된다.

이 경우에도 컨테이너를 재생성하지 않고 Ubuntu 내부 앱 프로세스만 교체하면 Step 2~5 네트워크 설정은 유지된다.

## 전체 흐름 정리

최종 요청 흐름:

```text
Host Browser
  -> api.local.test DNS 조회
  -> DNS VM 192.168.56.6
  -> 192.168.56.3 응답
  -> AppServer EC2 Public Address 192.168.56.3:80
  -> VPC VM이 192.168.56.3을 수신
  -> DNAT
  -> AppServer 10.10.1.10:80
  -> Database 10.10.2.10:3306
  -> DB content 조회
  -> HTML 응답
```

AppServer와 Database 사이 흐름:

```text
app-server 10.10.1.10
  -> route 10.10.2.0/24 via 10.10.1.1
  -> router namespace
  -> database 10.10.2.10:3306
  -> Database Security Group 허용
  -> MySQL query 성공
```

## 정리 명령

Step 7 구성을 정리하려면 VPC VM에서 실행한다.

```bash
cd ~/aws-vpc-local-lab/step/step7
./clean.sh
```

`clean.sh`는 Step 7에서 만든 네트워크 설정과 SSH key 등록 상태를 정리한다.

정리되는 항목:

```text
192.168.56.3 public IP alias
192.168.56.3:80 HTTP DNAT
192.168.56.3:22 SSH DNAT
10.10.1.254 IGW 역할 IP
br-public, br-private-db bridge
router namespace
app-server, database netns 연결
Step 7 FORWARD rule
VPC VM의 app-server-key.pub
AppServer Ubuntu의 /home/ubuntu/.ssh/authorized_keys
```

Docker 컨테이너 자체는 삭제하지 않는다.

컨테이너까지 다시 만들고 싶으면 별도로 실행한다.

```bash
docker-compose down
docker rm -f app-server database 2>/dev/null || true
docker-compose up -d --build
```

## 완료 기준

```text
Step 7 AppServer 컨테이너가 Ubuntu 기반 웹앱으로 실행됨
Ubuntu AppServer 컨테이너가 계속 실행 중임
VPC 관리용 Address 192.168.56.2 유지
AppServer EC2 Public Address 192.168.56.3 추가
DNS가 api.local.test를 192.168.56.3으로 응답
Ubuntu AppServer 내부에서 Flask 앱 프로세스 실행됨
Database에 page_contents 데이터가 생성됨
AppServer가 Database에 query 성공
Host -> api.local.test -> AppServer -> Database -> HTML 렌더링 성공
Host -> Database 직접 접근 실패
허용되지 않은 source -> Database 접근 실패
허용되지 않은 port 접근 실패
```

## 학습 기록

진행하면서 아래 항목을 기록한다.

```text
Step 7 AppServer 교체 결과:
VPC 관리용 Address 확인 결과:
AppServer EC2 Public Address 설정 결과:
DNS 레코드 변경 결과:
AppServer 내부 웹앱 실행 결과:
Database 초기화 결과:
Step 2~5 네트워크 재적용 결과:
AppServer -> Database query 결과:
Host -> api.local.test 접근 결과:
Host -> Database 직접 접근 결과:
허용되지 않은 source 접근 결과:
허용되지 않은 port 접근 결과:
막힌 부분:
정리한 개념:
```
