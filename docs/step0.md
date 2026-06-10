# STEP0. VM 준비

## 현재 실습 환경

| 항목 | 값 | 역할 |
| --- | --- | --- |
| VPC VM IP | `192.168.56.2` | AWS VPC 역할 VM. Subnet, ENI, Route Table, IGW, SG, EC2, RDS 재현 |
| DNS VM IP | `192.168.56.6` | Route53 역할 VM. `api.local.test`를 VPC VM IP로 응답 |
| 실습 도메인 | `api.local.test` | 최종적으로 Host Browser에서 접근할 도메인 |
| SSH 사용자 | `if` | 두 VM 공통 사용자 |
| SSH 비밀번호 | `0000` | 두 VM 공통 비밀번호 |

## 기준 문서

* 실습 단계는 [CURRICULUM.md](../CURRICULUM.md)를 기준으로 진행한다.
* Codex 작업 시 IP와 실습 기준값은 [CODEX_GUIDE.md](../CODEX_GUIDE.md)를 먼저 확인한다.
* UTM VM 생성 및 Ubuntu Server 설치 과정은 [UTM_SETTING.md](../UTM_SETTING.md)를 참고한다.

## 확인할 것

```text
VPC VM IP 확인: 192.168.56.2
DNS VM IP 확인: 192.168.56.6
Host에서 VPC VM ping 가능
Host에서 DNS VM ping 가능
DNS VM에서 VPC VM ping 가능
Host에서 VPC VM SSH 접속 가능: ssh if@192.168.56.2
Host에서 DNS VM SSH 접속 가능: ssh if@192.168.56.6
```

## 학습 메모

* 이번 실습은 VM 두 대를 사용한다.
* VPC VM은 AWS VPC 자체를 재현하는 환경이다.
* DNS VM은 Route53처럼 도메인 이름을 VPC VM IP로 변환하는 역할이다.
* `api.local.test`는 문서용 Public IP가 아니라 Host에서 실제 라우팅 가능한 `192.168.56.2`로 응답해야 한다.