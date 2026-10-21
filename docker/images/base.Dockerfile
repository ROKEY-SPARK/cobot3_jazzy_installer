# 강의 이미지 공통 base = ROS 2 Jazzy desktop + rosdep + 사용자 rokey (uid 1000, sudo 비밀번호 없음)
#   설치 = 호스트 설치기와 같은 resources/base.sh ros2 → 이미지 빌드가 곧 설치기 검증
#   cobot3 이미지가 FROM 으로 이어받는다. 빌드: bash docker/build.sh
#   stage 하나짜리 파일로 나눈 이유 = 레거시 빌더는 --target 앞의 stage 를 전부 빌드한다

ARG ROS_BASE=ros:jazzy-ros-base-noble
FROM ${ROS_BASE}
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
# 비우면 이미지 기본 미러. build.sh 가 호스트 미러(예: kr.archive.ubuntu.com)를 넘겨 다운로드 단축
ARG UBUNTU_MIRROR=""

RUN if [[ -n "${UBUNTU_MIRROR}" ]]; then \
      sed -i "s#http://archive.ubuntu.com/ubuntu/\?#${UBUNTU_MIRROR}#g" /etc/apt/sources.list.d/ubuntu.sources; \
    fi \
 && usermod -l rokey -d /home/rokey -m ubuntu \
 && groupmod -n rokey ubuntu \
 && echo 'rokey ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/rokey \
 && chmod 0440 /etc/sudoers.d/rokey

USER rokey
WORKDIR /home/rokey
ENV HOME=/home/rokey \
    LOG_FILE=/tmp/install_log \
    LANG=en_US.UTF-8

# base.sh ros2 가 쓰는 파일만 먼저 복사 → 강의 스크립트를 고쳐도 이 무거운 레이어는 캐시 유지
COPY --chown=rokey:rokey resources/config.sh resources/lib.sh resources/sys.sh resources/base.sh /opt/rokey_installer/resources/
RUN bash /opt/rokey_installer/resources/base.sh ros2 \
 && sudo rm -rf /var/lib/apt/lists/*
