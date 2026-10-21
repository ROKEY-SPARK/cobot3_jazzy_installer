# cobot3_jazzy_installer

- ROKEY 협동3 강의용 PC 를 **Ubuntu 24.04 + ROS 2 Jazzy + Isaac Sim 5.1.0** 으로 자동 설치하는 bash 스크립트
- 설치하는 것: 커널 · 드라이버 버전 고정 · Xorg · ROS 2 Jazzy · Isaac Sim 5.1.0 · Nav2 · Foxglove · IsaacSim-ros_workspaces · `~/cobot3_ws` · alias (`isaac` · `isaac_python` · `isaac_ros` · `jazzy`)
- 다른 강의: [협동1](https://github.com/ROKEY-SPARK/cobot1_jazzy_installer) · [협동2](https://github.com/ROKEY-SPARK/cobot2_jazzy_installer) · [지능1](https://github.com/ROKEY-SPARK/int1_jazzy_installer)

Docker 이미지 (`docker/`) 도 같은 설치 함수로 만든다 → [Docker 로 쓰기](#docker-로-쓰기)

## 설치

```bash
git clone https://github.com/ROKEY-SPARK/cobot3_jazzy_installer.git ~/cobot3_jazzy_installer
cd ~/cobot3_jazzy_installer

bash install.sh                    # ROS_DOMAIN_ID 기본 50 = 강의 값
bash install.sh --domain-id 12     # 조별 ROS_DOMAIN_ID
```

- `sudo` 없이 일반 사용자로 실행한다. 필요한 곳에서 스크립트가 sudo 를 부른다 (비밀번호 1회)
- Isaac Sim zip (`isaac-sim-standalone-5.1.0-linux-x86_64.zip`) 은 설치 USB (`/media/$USER/*`) → `~/Downloads` 순서로 찾는다. 없으면 시작 전에 다운로드 여부를 묻는다
- NVIDIA 드라이버를 새로 깔면 재부팅을 묻는다 → 재부팅 후 **같은 명령을 다시 실행** → 끝난 단계는 건너뜀
- 콘솔에는 진행 단계만 나온다. 상세 출력 = 저장소 루트 `install_log` (append-only)
- 마지막 단계 = `--verify` 점검. 언제든 다시 확인: `bash install.sh --verify`

### 옵션

| 옵션 | 뜻 |
|------|----|
| `--domain-id N` | `~/.bashrc` 블록의 `ROS_DOMAIN_ID` (조·팀 번호). 없으면 이전 값, 처음이면 50 |
| `--no-nvidia` | 드라이버 단계 건너뜀 (이미 설치했거나 NVIDIA GPU 없음). GPU 가 없으면 자동으로 아무것도 안 함 |
| `--isaac-zip PATH` | Isaac Sim zip 위치를 직접 지정 |
| `--isaac-download` | zip 이 없으면 NVIDIA 에서 받음 (~8.7GB, 이어받기 가능) |
| `--no-kernel-hold` | 현재 커널 hold + `apt upgrade` 단계 생략 |
| `--yes` · `--verbose` · `--dry-run` | 확인 자동 동의 · 상세 출력 콘솔 표시 · 실행 없이 단계 목록만 |
| `--status` · `--verify` · `--reset` | 진행 상태 · 설치 결과 점검 · 진행 기록 삭제 (설치 파일은 유지) |

- `--yes` 는 8.7GB 다운로드까지 동의한 것으로 보지 않는다. 다운로드는 `--isaac-download` 를 줄 때만 한다
- 예전 형식 `bash install.sh cobot3 ...` 도 그대로 동작한다

종료 코드: `0` 성공 · `1` 사용자 오류 (잘못된 옵션 · 입력 파일 없음) · `2` 시스템 오류 (단계 실패)

## 단계

| # | 단계 | 내용 · 근거 (협동3 강의자료) |
|---|------|------|
| 1 | `kernel_hold` | HWE 메타 + **현재 커널** hold → `apt upgrade` ("Kernel 최신버전으로 업데이트") |
| 2 | `no_release_upgrade` | `/etc/update-manager/release-upgrades` → `Prompt=never` |
| 3 | `nvidia_driver` | `nvidia-driver-580-open` 고정 버전 시도 → 없으면 같은 브랜치 최신 + nvidia 패키지 전부 hold |
| 4 | `xorg` | `/etc/gdm3/custom.conf` `WaylandEnable=false` |
| 5 | `ros2_jazzy` | ros2-apt-source 방식 ROS 2 Jazzy desktop + ros-dev-tools |
| 6 | `vscode` | VS Code ("GPU-개인PC—VSCode 설치") |
| 7 | `isaacsim` | zip → `~/isaacsim` 압축 해제 → `post_install.sh` → `VERSION` = 5.1.0 확인 |
| 8 | `nav2` | navigation2 · nav2-bringup · pointcloud-to-laserscan · nav2-simple-commander · foxglove-bridge |
| 9 | `isaac_ros_ws` | `~/IsaacSim-ros_workspaces` (태그 `IsaacSim-5.1.0`) + submodule + `jazzy_ws` colcon build |
| 10 | `cobot3_workspace` | `~/cobot3_ws/src` + `~/cobot3_ws/isaacpjt` + colcon build |
| 11 | `fastdds_profile` | `~/.ros/fastdds_whitelist.xml` (UDPv4 전용) |
| 12 | `cobot3_bashrc` | `isaac` · `isaac_python` · `isaac_ros` · `jazzy` |
| 13 | `verify` | 점검 |

설치 후 (강의 순서):

```bash
isaac_ros; isaac                                   # 터미널 1: Isaac Sim GUI
isaac_ros; isaac_python 1_load_usd_standalone.py   # 또는 Standalone 스크립트
jazzy; ros2 launch carter_navigation carter_navigation.launch.py   # 터미널 2: ROS 쪽
```

## 강의자료와 다른 점

설치기는 강의자료 절차를 따른다. 아래는 그대로 두면 깨지는 부분이다.

| 항목 | 강의자료 | 설치기 | 이유 |
|------|---------|--------|------|
| NVIDIA 드라이버 | `nvidia-driver-580-open=580.173.02-0ubuntu0.24.04.1` | 그 버전 시도 → 없으면 `580-open` 최신 | 2026-10-20 기준 저장소에 `580.178.04` 만 남음 → 고정 명령 그대로면 실패 |
| 커널 hold | `6.14.0-27` 고정 | **현재 부팅된 커널** hold | 노트북마다 설치 시점 커널이 다름 |
| IsaacSim-ros_workspaces | `git clone` (main) | 태그 `IsaacSim-5.1.0` 고정 | main 은 이미 Isaac Sim 6.x 용 |
| `isaac_ros` | env 4줄 export | 같은 4줄 + 내장 ROS 라이브러리 경로 | 5.1.0 `isaac-sim.sh` 는 `ROS_DISTRO` 가 비어 있을 때만 내장 라이브러리를 붙이고 `python.sh` 는 아예 안 붙임 (zip 안 `setup_ros_env.sh` 확인) |
| `fastdds_whitelist.xml` | 내용 미기재 | UDPv4 전용 프로파일, 주소 제한은 `FASTDDS_WHITELIST=ip1,ip2` 로 선택 | 원본 파일 내용 unknown → Isaac Sim 공식 문서의 fastdds.xml 구성 사용 |
| 시스템 ROS | — | `~/.bashrc` 에서 source 안 함, ROS 터미널은 `jazzy` 로 | Isaac Sim 터미널에 시스템 Jazzy 를 섞지 말라는 강의 주의사항 |
| ROS apt 저장소 | ros2-apt-source (GitHub API 로 최신 조회) | ros2-apt-source `1.3.0` 고정. 이미 ROS 저장소가 있으면 추가 안 함 | 강의실 한 IP 에서 GitHub API 60회/시간 제한. 협동2 설치기의 `ros2.list` 와 겹치면 apt 가 `Conflicting values set for option Signed-By` 로 실패 |

## Docker 로 쓰기

호스트에 ROS 를 깔지 않고 협동3 ROS 쪽 환경을 컨테이너로 쓴다. 이미지 빌드가 위 설치 함수를 그대로 실행하고, 마지막에 `verify.sh` 를 통과해야 이미지가 생긴다.

- 파일: `docker/images/base.Dockerfile` (ROS 2 desktop + 사용자 `rokey` uid 1000) → `docker/images/cobot3.Dockerfile`
- `build.sh` 가 base → cobot3 순서로 빌드하고, 호스트 apt 미러 (예: `kr.archive.ubuntu.com`) 를 이미지에도 쓴다

```bash
bash docker/setup-host.sh          # Docker Engine + NVIDIA Container Toolkit (호스트 1회)
bash docker/build.sh               # rokey/jazzy-base → rokey/jazzy-cobot3
bash docker/run.sh cobot3          # ROS 쪽: X11 GUI · GPU · 호스트 네트워크 · ~/rokey_docker/cobot3 ↔ ~/work
bash docker/run.sh isaac-sim       # 공식 Isaac Sim 5.1.0 이미지 (헤드리스 스트리밍), --gui = 로컬 창
```

| 이미지 | 내용 |
|--------|------|
| `rokey/jazzy-cobot3` | Nav2 · foxglove · Isaac ROS `jazzy_ws` · `cobot3_ws` · FastDDS 프로파일 |
| `nvcr.io/nvidia/isaac-sim:5.1.0` | Isaac Sim 본체 (공식 이미지, `docker/run.sh isaac-sim` 이 실행) |

- `ROS_DOMAIN_ID=50 bash docker/run.sh cobot3` 처럼 도메인을 넘긴다
- 컨테이너는 `--rm` → 남길 코드는 `~/work` (호스트 `~/rokey_docker/cobot3`) 에 둔다. Isaac Sim 스크립트 폴더 = 호스트 `~/rokey_docker/isaac-sim/isaacpjt`
- `isaac-sim` 캐시 = docker volume `isaac-sim-*` (첫 실행 때 소유권을 uid 1234 로 맞춤). 셰이더 캐시가 남아 두 번째 실행부터 빠름

## 주의

- `docker/run.sh isaac-sim --gui` 는 `xhost +local:` 을 건다 (컨테이너 uid 1234 ≠ 호스트 사용자). 같은 PC 의 모든 로컬 사용자가 X 화면에 접근할 수 있다
- `~/.bashrc` 를 처음 고치기 전에 `~/.bashrc.rokey.bak` 으로 원본을 한 번 백업한다. 관리 블록 마커가 한쪽만 남아 있으면 지우지 않고 멈춘다
- 같은 PC 에 협동1 설치기 블록이 있으면 그 블록이 `/opt/ros/jazzy/setup.bash` 를 source 한다 → Isaac 터미널에 시스템 ROS 가 섞인다. Isaac 터미널에서는 `bash --norc` 후 협동3 블록만 쓰거나, 강의별 PC 를 나눈다
- `kernel_hold` 는 커널을 고정한다. 같은 PC 에서 나중에 다른 설치기가 새 커널을 깔려고 해도 올라가지 않는다

## 문제 해결

| 증상 | 조치 |
|------|------|
| 단계가 `[FAIL]` 로 멈춤 | 저장소 루트 `install_log` 끝부분 확인 → 원인 해결 → 같은 명령 다시 실행 (끝난 단계는 skip) |
| 처음부터 다시 | `bash install.sh --reset` 후 재실행 (설치된 패키지 · 폴더는 지우지 않음) |
| zip 이 없다고 실패 | `--isaac-zip /media/$USER/ISAACSIM/isaac-sim-standalone-5.1.0-linux-x86_64.zip` 또는 `--isaac-download` |
| 여유 공간 부족으로 실패 | `~/isaacsim` 옆에 30GB (다운로드하면 40GB) 이상 필요 |
| Isaac Sim 첫 실행이 느림 | 셰이더 컴파일 (5~10분). 두 번째 실행부터 빠름 |

## 개발

```bash
bash tests/run.sh                  # 단위 테스트 (sudo · 네트워크 불필요, 격리된 HOME)
bash tests/e2e.sh                  # install.sh 전체를 깨끗한 컨테이너에서 실행 (성공 · 실패 경로)
bash tests/nav2_smoke.sh           # Nav2: Isaac Sim 대역 노드로 navigate_to_pose 성공 확인 (GPU 불필요)
shellcheck -x install.sh resources/*.sh docker/*.sh tests/*.sh
bash install.sh --dry-run          # 실행할 단계 목록
```

- `tests/e2e.sh` 성공 경로는 작은 stub zip 으로 `isaacsim` 단계의 압축 해제 · 버전 확인 흐름만 본다. 실제 Isaac Sim 실행은 검증하지 않는다
- 버전 핀 · 경로 = `resources/config.sh` 한 곳. 환경변수로 덮어쓸 수 있다 (예: `COBOT3_WS=~/my_ws`)
- 단계 순서 = `resources/courses.sh` · 단계 구현 = `resources/<base|cobot3>.sh`
- 단계 이름은 state 키다 (`~/.rokey_jazzy_installer/cobot3.state`) → 이름을 바꾸면 기존 설치의 재개 기록이 끊긴다
