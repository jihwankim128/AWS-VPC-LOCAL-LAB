# STEP1. VPC VM에 AppServer와 Database 실행

## 목표

VPC VM 안에서 EC2 역할의 AppServer와 RDS 역할의 Database를 실행한다.

이번 단계에서는 Docker Compose를 컨테이너 실행 목록으로 사용한다.

아직 AWS VPC의 Subnet, ENI, Route Table, Security Group, Internet Gateway는 구성하지 않는다.

Compose 파일은 [docker-compose.yml](./docker-compose.yml)에 둔다.

## 현재 실습 기준

| 항목 | 값 |
| --- | --- |
| VPC VM IP | `192.168.56.2` |
| SSH 사용자 | `if` |
| SSH 비밀번호 | `0000` |

## 이번 단계에서 이해할 것

| AWS 개념 | 로컬 실습에서의 대응 |
| --- | --- |
| EC2 | nginx를 실행하는 `app-server` 컨테이너 |
| RDS | MySQL을 실행하는 `database` 컨테이너 |
| 인스턴스 프로세스 | 컨테이너 안에서 실행되는 nginx, mysqld |
| Docker Compose | 어떤 컨테이너 이미지를 실행했는지 저장소에 남기는 실행 명세 |
| 네트워크 | Compose 네트워크를 쓰지 않고 다음 단계에서 직접 구성 |

## 진행 순서

### 1. VPC VM 접속

Host 터미널에서 VPC VM에 접속한다.

```bash
ssh if@192.168.56.2
```

### 2. 기본 패키지 상태 확인

VPC VM 안에서 Docker와 네트워크 도구가 있는지 확인한다.

```bash
docker --version
docker-compose version
ip -V
iptables --version
```

없다면 다음 패키지를 설치해야 한다.

```bash
sudo apt update
# 1. 도커와 네트워크 툴, 구버전 컴포즈 명칭으로 한방에 설치
sudo apt install -y docker.io docker-compose iproute2 iptables curl
# 2. 설치가 완료되면 이제 docker 그룹이 생겼으니 유저 추가
sudo usermod -aG docker if
```

`usermod` 이후에는 SSH를 끊고 다시 접속한다.

### 3. AppServer 컨테이너 실행 준비

이번 단계의 AppServer는 nginx 프로세스가 살아 있는지 확인하는 수준으로 진행한다.

중요한 점은 아직 Host에 포트를 공개하는 것이 목적이 아니라는 것이다.

VPC VM 안에서 실습 디렉터리를 만든다.

```bash
mkdir -p ~/aws-vpc-local-lab/step/step1
cd ~/aws-vpc-local-lab/step/step1
```

Host의 [docker-compose.yml](./docker-compose.yml) 내용을 VPC VM의 `~/aws-vpc-local-lab/step/step1/docker-compose.yml`에 동일하게 작성한다.

Compose 파일의 핵심은 다음과 같다.

```yaml
services:
  app-server:
    image: nginx:stable
    container_name: app-server
    network_mode: "none"
```

### 4. Database 컨테이너 실행 준비

Database는 MySQL 프로세스가 살아 있는지 확인하는 수준으로 진행한다.

Compose 파일에는 다음 서비스가 함께 있어야 한다.

```yaml
services:
  database:
    image: mysql:8.0
    container_name: database
    network_mode: "none"
    environment:
      MYSQL_ROOT_PASSWORD: localpass
      MYSQL_DATABASE: appdb
```

### 5. Compose로 컨테이너 실행

VPC VM에서 Compose 파일이 있는 디렉터리로 이동한 뒤 실행한다.

```bash
cd ~/aws-vpc-local-lab/step/step1
docker-compose up -d
```

상태를 확인한다.

```bash
docker ps
docker logs database --tail 30
```

확인 포인트:

```text
app-server 컨테이너가 Up 상태인지 확인
database 컨테이너가 Up 상태인지 확인
app-server 이미지가 nginx인지 확인
database 이미지가 mysql인지 확인
```

AppServer 컨테이너 내부 프로세스를 확인한다.

```bash
# nginx 확인
docker exec app-server nginx -v
docker exec app-server nginx -t
docker logs app-server --tail 20
```

MySQL 프로세스가 떠 있는지 확인한다.

```bash
docker exec database mysqladmin ping -uroot -plocalpass
```

성공하면 다음과 비슷한 응답이 나온다.

```text
mysqld is alive
```

## 접근 확인

현재 단계에서는 컨테이너 프로세스 실행만 확인한다.

`docker-compose.yml`에서 두 컨테이너 모두 `network_mode: "none"`으로 실행했기 때문에 컨테이너에는 일반적인 네트워크 인터페이스가 없다.

### 1. Host Browser에서 AppServer 접근

Host 브라우저에서 아래 주소로 접근해 본다.

```text
http://192.168.56.2
```

또는 Host 터미널에서 확인한다.

```bash
curl http://192.168.56.2
```

예상 결과:

```text
접속 실패가 정상
```

이유:

```text
아직 VPC VM의 80번 포트를 AppServer로 연결하지 않았다.
Compose에서도 ports를 사용하지 않았다.
Internet Gateway 역할의 DNAT도 아직 구성하지 않았다.
```

### 2. VPC VM에서 AppServer 접근

VPC VM 안에서 확인한다.

```bash
curl http://localhost
curl http://127.0.0.1
```

예상 결과:

```text
접속 실패가 정상
```

이유:

```text
app-server 컨테이너의 nginx는 떠 있지만 VPC VM host network에 포트를 공개하지 않았다.
```

### 3. app-server에서 database 접근

app-server 컨테이너 안에서 database 이름 해석을 시도한다.

```bash
docker exec app-server sh -c 'getent hosts database || echo "database name lookup failed"'
```

예상 결과:

```text
database name lookup failed
```

이유:

```text
Docker Compose 네트워크를 사용하지 않으므로 database라는 서비스 이름을 DNS로 찾을 수 없다.
```

nginx 기본 이미지에는 `curl`, `ping`, `nc` 같은 네트워크 확인 도구가 없을 수 있다.

이번 단계에서는 `database` 이름 해석 실패까지만 확인해도 충분하다.

### 4. database에서 app-server 접근

database 컨테이너 안에서 app-server 이름 해석을 시도한다.

```bash
docker exec database sh -c 'getent hosts app-server || echo "app-server name lookup failed"'
```

예상 결과:

```text
app-server name lookup failed
```

이유:

```text
database 컨테이너도 Docker Compose 네트워크에 연결되어 있지 않다.
```

### 5. 컨테이너 네트워크 상태 확인

각 컨테이너의 네트워크 모드를 확인한다.

```bash
docker inspect app-server --format '{{.HostConfig.NetworkMode}}'
docker inspect database --format '{{.HostConfig.NetworkMode}}'
```

예상 결과:

```text
none
none
```

컨테이너에 통신 가능한 IP가 없는지도 확인한다.

```bash
docker inspect app-server --format 'mode={{.HostConfig.NetworkMode}} ip={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} gateway={{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
docker inspect database --format 'mode={{.HostConfig.NetworkMode}} ip={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} gateway={{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
```

예상 결과:

```text
mode=none ip=invalid IP gateway=invalid IP
mode=none ip=invalid IP gateway=invalid IP
```

Docker 버전에 따라 `.NetworkSettings.Networks`에는 `none` 엔트리가 보일 수 있다.

```bash
docker inspect app-server --format '{{json .NetworkSettings.Networks}}'
docker inspect database --format '{{json .NetworkSettings.Networks}}'
```

이 경우에도 아래 값들이 비어 있으면 현재 단계에서는 정상이다.

```text
IPAddress: 빈 값
Gateway: 빈 값
MacAddress: 빈 값
IPPrefixLen: 0
DNSNames: null
```

### 6. 현재 단계에서 실패해도 정상인 것

아직 네트워크를 직접 구성하지 않았기 때문에 다음은 성공하지 않아도 된다.

```text
Host Browser -> app-server 직접 접근
app-server -> database 접근
database -> app-server 접근
```

특히 `--network none`으로 실행했기 때문에 컨테이너는 외부 네트워크와 분리되어 있다.

## 정리 명령

실습을 다시 시작하고 싶으면 VPC VM 안에서 컨테이너를 삭제한다.

```bash
cd ~/aws-vpc-local-lab/step/step1
docker-compose down
```

## 완료 기준

```text
VPC VM에서 docker 명령 사용 가능
VPC VM에서 docker-compose 명령 사용 가능
app-server 컨테이너가 Up 상태
database 컨테이너가 Up 상태
app-server 컨테이너 안에서 nginx 프로세스 확인
database 컨테이너에서 mysqld is alive 확인
Host Browser에서 AppServer 직접 접근 실패 확인
VPC VM에서 localhost:80 접근 실패 확인
app-server에서 database 이름 해석 실패 확인
database에서 app-server 이름 해석 실패 확인
두 컨테이너의 NetworkMode가 none인지 확인
```

## 학습 기록

진행하면서 아래 항목을 기록한다.

```text
Docker 설치 여부:
docker-compose 설치 여부:
app-server 컨테이너 실행 결과:
database 컨테이너 실행 결과:
Host Browser -> AppServer 접근 결과:
VPC VM -> localhost:80 접근 결과:
app-server -> database 접근 결과:
database -> app-server 접근 결과:
막힌 부분:
정리한 개념:
```
