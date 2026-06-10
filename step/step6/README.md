# STEP6. DNS VM으로 Route53 재현

## 목표

DNS VM을 Route53처럼 사용해 `api.local.test` 도메인을 VPC VM의 외부 IP로 응답하게 한다.

이번 단계에서는 DNS VM에서 CoreDNS를 실행한다.

```text
api.local.test -> 192.168.56.2
```

Host는 `api.local.test` 질의를 DNS VM `192.168.56.6`으로 보낸다.

주의할 점은 Step 1의 VPC VM 컨테이너와 달리, DNS VM의 CoreDNS는 Host에서 직접 접근해야 하므로 `53/tcp`, `53/udp` 포트를 공개한다.

## 구성 매핑

| AWS 개념 | 로컬 실습에서의 대응 |
| --- | --- |
| Route53 Public Hosted Zone | DNS VM의 CoreDNS |
| DNS Record | `api.local.test -> 192.168.56.2` |
| Public Endpoint | VPC VM `192.168.56.2` |
| Host DNS Resolver | macOS `/etc/resolver/local.test` |

## 현재 실습 기준

| 항목 | 값 |
| --- | --- |
| DNS VM IP | `192.168.56.6` |
| VPC VM IP | `192.168.56.2` |
| Domain | `api.local.test` |
| SSH 사용자 | `if` |
| SSH 비밀번호 | `0000` |

## 진행 전 확인

Step 5가 정상이어야 한다.

Host에서 VPC VM Public Endpoint 접근이 성공해야 한다.

```bash
curl -I http://192.168.56.2
```

예상 결과:

```text
HTTP/1.1 200 OK
```

DNS VM에 접속한다.

```bash
ssh if@192.168.56.6
```

DNS VM에서 VPC VM에 접근 가능한지 확인한다.

```bash
ping -c 2 192.168.56.2
```

## 진행 순서

아래 명령은 DNS VM에서 진행한다.

### 1. Docker와 확인 도구 설치

DNS VM에 Docker와 DNS 확인 도구가 없다면 설치한다.

```bash
sudo apt update
sudo apt install -y docker.io docker-compose bind9-dnsutils curl
sudo usermod -aG docker if
```

`usermod` 이후에는 SSH를 끊고 다시 접속한다.

### 2. 실습 디렉터리 준비

DNS VM 안에서 Step 6 디렉터리를 준비한다.

```bash
mkdir -p ~/aws-vpc-local-lab/step/step6
cd ~/aws-vpc-local-lab/step/step6
```

Host의 [Corefile](./Corefile), [docker-compose.yml](./docker-compose.yml)을 DNS VM의 같은 경로에 작성한다.

### 3. CoreDNS 설정 확인

[Corefile](./Corefile)의 핵심은 다음과 같다.

```text
api.local.test -> 192.168.56.2
```

CoreDNS는 `hosts` 플러그인으로 이 레코드를 응답한다.

```text
hosts {
  192.168.56.2 api.local.test
  fallthrough
}
```

### 4. CoreDNS 실행

DNS VM에서 실행한다.

```bash
docker-compose up -d
```

상태를 확인한다.

```bash
docker ps
docker logs route53-dns --tail 30
```

만약 `bind: cannot assign requested address`가 나오면 `docker-compose.yml`의 `192.168.56.6:53:53` 부분이 현재 DNS VM IP와 같은지 확인한다.

만약 `port is already allocated`가 나오면 DNS VM에서 이미 53번 포트를 사용 중인 프로세스가 있는지 확인한다.

```bash
sudo ss -lntup | grep ':53'
```

### 5. DNS VM에서 직접 질의 확인

DNS VM에서 자신의 외부 IP로 질의한다.

```bash
dig @192.168.56.6 api.local.test
```

예상 결과:

```text
api.local.test. ... A 192.168.56.2
```

짧게 확인하려면:

```bash
dig @192.168.56.6 api.local.test +short
```

예상 결과:

```text
192.168.56.2
```

## Host DNS 설정

아래 명령은 Host macOS에서 진행한다.

`api.local.test`는 `local.test` 도메인 아래에 있으므로 resolver 파일 이름은 `local.test`로 만든다.

```bash
sudo mkdir -p /etc/resolver
sudo sh -c 'echo "nameserver 192.168.56.6" > /etc/resolver/local.test'
```

설정을 확인한다.

```bash
cat /etc/resolver/local.test
```

예상 결과:

```text
nameserver 192.168.56.6
```

macOS DNS 설정에 반영되었는지 확인한다.

```bash
scutil --dns | grep -A3 'local.test'
```

## 접근 확인

### 1. Host에서 DNS VM으로 직접 질의

Host에서 직접 DNS VM을 지정해 질의한다.

```bash
dig @192.168.56.6 api.local.test +short
```

또는:

```bash
nslookup api.local.test 192.168.56.6
```

예상 결과:

```text
192.168.56.2
```

### 2. Host Browser에서 도메인 접근

Host에서 브라우저로 접근한다.

```text
http://api.local.test
```

또는 터미널에서 확인한다.

```bash
curl -I http://api.local.test
```

예상 결과:

```text
HTTP/1.1 200 OK
```

## 흐름 정리

DNS 조회 흐름은 다음과 같다.

```text
Host
  -> api.local.test 질의
  -> /etc/resolver/local.test
  -> DNS VM 192.168.56.6:53
  -> CoreDNS
  -> 192.168.56.2 응답
```

HTTP 요청 흐름은 다음과 같다.

```text
Host Browser
  -> http://api.local.test
  -> DNS 응답 192.168.56.2
  -> VPC VM 192.168.56.2:80
  -> Step 5 DNAT
  -> app-server 10.10.1.10:80
```

## 정리 명령

DNS VM에서 CoreDNS를 중지하려면:

```bash
cd ~/aws-vpc-local-lab/step/step6
docker-compose down
```

또는 [clean.sh](./clean.sh)를 사용할 수 있다.

```bash
./clean.sh
```

Host macOS resolver 설정을 제거하려면 Host에서 실행한다.

```bash
sudo rm -f /etc/resolver/local.test
```

## 완료 기준

```text
DNS VM에서 CoreDNS 컨테이너 실행 확인
DNS VM에서 dig @192.168.56.6 api.local.test 결과가 192.168.56.2인지 확인
Host에서 dig @192.168.56.6 api.local.test 결과가 192.168.56.2인지 확인
Host 기본 resolver에서 api.local.test가 192.168.56.2로 해석되는지 확인
Host Browser 또는 curl로 http://api.local.test 접근 성공
```

## 학습 기록

진행하면서 아래 항목을 기록한다.

```text
CoreDNS 실행 결과:
DNS VM -> api.local.test 질의 결과:
Host -> DNS VM 직접 질의 결과:
Host resolver 설정 결과:
Host -> api.local.test 접근 결과:
막힌 부분:
정리한 개념:
```
