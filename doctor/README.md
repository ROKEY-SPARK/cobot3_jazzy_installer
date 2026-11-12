# 부록: 강의 PC 진단기 (`doctor/`)

- 협동1, 협동2, 협동3, 지능1 강의 PC를 점검하는 bash 스크립트
- 점검 범위 3가지: **설치 누락**, **패키지 깨짐**, **강의와 무관한 공통 시스템 오류**
- 설치기 저장소 4개 (협동1, 협동2, 협동3, 지능1)의 `doctor/`는 같은 파일이다. 한 PC에 여러 강의가 깔려도 한 번에 점검한다
- 읽기 전용이다. 시스템을 바꾸지 않고 sudo 도 부르지 않는다. 고칠 방법은 결과 줄 아래 `→`로 알려 준다

## 실행

```bash
bash doctor/doctor.sh              # 저장소 루트에서. 설치 흔적으로 강의 자동 감지
bash doctor/doctor.sh cobot1       # 강의 지정 (여러 개 가능: cobot1 cobot2)
bash doctor/doctor.sh --help
```

- 자동 감지 근거: 설치기 진행 기록, `~/.bashrc` 강의 블록, 강의 워크스페이스 중 하나. 설치기 `--reset` 뒤에도 감지된다
- 아무 흔적이 없으면 공통 점검만 한다

| 결과 | 뜻 |
|------|----|
| `[PASS]` | 정상 |
| `[WARN]` | 확인 권장. 종료 코드에 반영하지 않음 |
| `[FAIL]` | 고쳐야 함. 아래에 명령 출력 앞부분과 복구 방법 |
| `[SKIP]` | 판정 불가 (권한, 하드웨어, 그래픽 세션 없음). 이유를 함께 표시 |

종료 코드: `0` FAIL 없음, `1` 잘못된 인자, `2` FAIL 있음

| 옵션 | 뜻 |
|------|----|
| `--no-host` | 커널, 부팅, sysctl, 정적 IP, 시간 점검 생략 (컨테이너 안) |
| `--no-gpu` | NVIDIA 드라이버, GPU 점검 생략 |
| `--no-docker` | docker 그룹, 데몬, 이미지, 런타임 점검 생략 |
| `--no-isaac` | Isaac Sim 본체 점검 생략 (협동3) |

## 점검 항목

| 계층 | 파일 | 항목 |
|------|------|------|
| 공통, 시스템 | `doctor/checks/system.sh` | Ubuntu 24.04, 디스크 여유, `dpkg --audit`, apt 의존성, apt 저장소 오류 (Signed-By 충돌 등), DNS, 다른 apt 작업 실행 중, modules-extra, 최신 커널 부팅, NVMe SSD timeout (APST), 재부팅 대기, 시간 동기화, nvidia-smi, 최신 커널의 nvidia 모듈, Secure Boot, docker 그룹, 데몬 |
| 공통, ROS 환경 | `doctor/checks/ros_env.sh` | ROS 2 Jazzy, ros2 CLI, rosdep, `~/.bashrc` 문법, 다른 distro source, `ROS_DOMAIN_ID`, `RMW_IMPLEMENTATION` 값 충돌, `CYCLONEDDS_URI` 파일, PDF 복사 특수문자, setuptools 80 이상, conda 자동 활성, numpy 2, 설치기 FAIL/RUNNING 기록, 재개 autostart 잔존 |
| 공통, DDS 통신 | `doctor/checks/dds.sh` | LOCALHOST 전용 탐색, `ROS_DOMAIN_ID` 미설정 또는 0, Discovery Server와 CycloneDDS 충돌, CycloneDDS XML에 적힌 없는 인터페이스 이름, ufw 켜짐 |
| 협동1, 2 노트북 | `doctor/checks/cobot_laptop.sh` | HWE 커널, sysctl 소켓 버퍼, 로봇 LAN `192.168.1.30/24`, 로봇 LAN 기본 경로 (인터넷 끊김), ros2_control, libpoco-dev, CycloneDDS, docker hold, DSR 에뮬레이터 이미지 |
| 협동1 | `doctor/checks/cobot1.sh` | cobot_rg2 clone, 워크스페이스 중복 패키지, 고정 커밋, 빌드 패키지, DSR_ROBOT2 경로, pymodbus, PyQt5, 강의 도구, udev, bashrc 블록 |
| 협동2 | `doctor/checks/cobot2.sh` | 드라이버 595 (closed), hold, nvidia 모듈 meta, docker nvidia 런타임, bashrc env 블록, cobot2 소스, 워크스페이스 중복 패키지, m0609 링크, DSR, onrobot 고정 커밋, 빌드, RealSense, 옛 저장소 파일, voice 모듈, pyserial, wakeword 모델 손상, yolo 이미지 |
| 협동3 | `doctor/checks/cobot3.sh` | 드라이버 580-open, hold, 커널 hold, Xorg, Prompt=never, Isaac Sim 5.1.0, 내장 ROS 2 라이브러리 (ros2 bridge), Nav2, Isaac ROS ws 태그, 빌드, 워크스페이스 중복 패키지, cobot3_ws, FastDDS 프로필, bashrc 블록 |
| 지능1 | `doctor/checks/intel1.sh` | 드라이버 580, torch GPU, turtlebot4 ws, 워크스페이스 중복 패키지, numpy 1.26.4, opencv 4.9.0, LabelImg, to_students, bashrc 블록 |

- 공통 DDS, 시스템 일부 항목의 근거 = 교육 운영팀 오류 대응 매뉴얼 DB (Notion)
- 버전, 경로 값은 `doctor/lib/pins.sh`에 있다. 출처는 각 설치기 `resources/config.sh`다 (다른 강의 저장소 없이도 돌도록 복사)
- `resources/config.sh` 핀을 바꾸면 `doctor/tests/test_pins.sh`가 실패한다. 같은 상위 폴더에 다른 강의 설치기가 있으면 그 config도 함께 대조

## 개발

```bash
bash doctor/tests/run.sh           # 단위 테스트 (가짜 HOME · 가짜 명령, 네트워크 · sudo 불필요)
bash doctor/tests/e2e.sh cobot1    # docker/build.sh 로 만든 rokey/jazzy-<강의> 이미지 안에서 성공 · 실패 경로
shellcheck -x doctor/doctor.sh doctor/lib/*.sh doctor/checks/*.sh doctor/tests/*.sh
```

- 새 점검 = 점검 함수 하나 (0 정상, 1 문제, `RC_SKIP` 판정 불가, stdout = 이유) + `check` 한 줄
- 점검 함수는 root 권한 명령, 쓰기 명령을 쓰지 않는다
- 고치면 네 저장소의 `doctor/`에 같은 변경을 넣는다 (파일이 같아야 한 PC의 결과가 저장소마다 같다)
- 협동2는 설치 완료 이미지가 없다 → 판정 함수는 단위 테스트, 전체 경로는 실제 협동2 PC에서 확인해야 한다
