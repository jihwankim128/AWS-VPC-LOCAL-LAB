### Ubuntu Download
Ubuntu Server 22.04 Release
* 다운로드 링크: https://cdimage.ubuntu.com/releases/22.04/release/

---

### UTM Download

* https://mac.getutm.app/

---

### Create UTM VM

> DNS를 생성한다. VPC도 동일하게 생성한다.

|                          |                          |
|:------------------------:|:------------------------:|
|  ![1](images/utm/img.png)  | ![2](images/utm/img_1.png) |
| ![3](images/utm/img_2.png) | ![4](images/utm/img_3.png) |
| ![5](images/utm/img_4.png) | ![6](images/utm/img_5.png) |
| ![7](images/utm/img_6.png) |                          |

* 가상화, Linux 선택
* CPU, Memory는 사양에 맞게 적절히 선택
  * DNS는 매우 적은 사양으로 충분하니 CPU 1, RAM 1
  * VPC는 내부 도커 떄문에 CPU 2, RAM 2 정도로 선택했다.
* Apple 가상화 미사용
* 디스크도 10GB로만 설정했다. VPC는 조금 더 크게 30GB면 매우 충분

---

### Ubuntu Server Setting

|                                                    |                                                    |
|:--------------------------------------------------:|:--------------------------------------------------:|
|  <img src="./images/ubuntu/img.png" width="450">   | <img src="./images/ubuntu/img_1.png" width="450">  |
| <img src="./images/ubuntu/img_2.png" width="450">  | <img src="./images/ubuntu/img_3.png" width="450">  |
| <img src="./images/ubuntu/img_4.png" width="450">  | <img src="./images/ubuntu/img_5.png" width="450">  |
| <img src="./images/ubuntu/img_6.png" width="450">  | <img src="./images/ubuntu/img_7.png" width="450">  |
| <img src="./images/ubuntu/img_8.png" width="450">  | <img src="./images/ubuntu/img_9.png" width="450">  |
| <img src="./images/ubuntu/img_10.png" width="450"> | <img src="./images/ubuntu/img_11.png" width="450"> |

* Try or Install Ubuntu Server
* 언어 알아서 선택
* Continue without Updating -> Done
* Ubuntu Server 선택 -> Done
* Network Interface 미작성(그대로) -> Done
* Proxy Address 미작성 -> Done
* Mirror Address 그대로 -> Done
* Set up this disk as an LVM Group 체크 해제 -> Done
  * 요약 페이지 나오면 그냥 Done -> Continue
* 서버 설정 대충 작성
  * name: if
  * server name: custom-dns
  * pick a username: if
  * password: 0000
* Update Skip
* Bash 접속을 위해 Install Open SSH 선택 후 Done
* 추가 설정 무시하고 Done - 실습에 미필요
* 기다렸다가 설치 완료되면 Reboot Now

---

### VM 환경 최종 확인

|                                                  |                                                  |
|:------------------------------------------------:|:------------------------------------------------:|
|  <img src="./images/final/img.png" width="450">  | <img src="./images/final/img_1.png" width="450"> |
| <img src="./images/final/img_2.png" width="450"> | <img src="./images/final/img_3.png" width="450"> |
| <img src="./images/final/img_4.png" width="450"> | <img src="./images/final/img_5.png" width="450"> |

* UTM 환경 이슈 때문에 VM 종료 후 -> CD/DVD 찾아보기 초기화
* 재접속
* ID - PASSWORD로 로그인
  * if, 0000
  * 로그인 시 보이는 IP 확인
  * 확인 불가 시 `ip -4 addr`로 확인
  * 현재 세팅 환경은 192.168.56.6
* Host(Mac) Shell에서 접속 확인
  * `ssh if@192.168.56.6` -> ubuntuUser@ip
  * 비밀번호 입력
* 호스트 접속 확인 후 UTM 백그라운드 세팅
  * VM 종료 후 UTM에서 VM 우클릭 -> 편집 혹은 우측 상단 세팅 선택
  * 디스플레이 우클릭 -> 제거
  * 재실행 후 서버 부팅까지 기다렸다가 `ssh if@192.168.56.6`로 접속 확인
* 동일한 방식으로 VPC VM도 생성