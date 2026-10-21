# 협동3 ROS 쪽 이미지 = Nav2 · foxglove · IsaacSim-ros_workspaces jazzy_ws · cobot3_ws
#   Isaac Sim 자체 = 공식 이미지 nvcr.io/nvidia/isaac-sim:5.1.0 (bash docker/run.sh isaac-sim)
ARG BASE_IMAGE=rokey/jazzy-base:latest
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

COPY --chown=rokey:rokey resources /opt/rokey_installer/resources
RUN R=/opt/rokey_installer/resources \
 && bash $R/cobot3.sh nav2 \
 && bash $R/cobot3.sh isaac-ros-ws \
 && bash $R/cobot3.sh workspace \
 && bash $R/cobot3.sh dds \
 && bash $R/cobot3.sh bashrc \
 && sudo rm -rf /var/lib/apt/lists/*
RUN bash /opt/rokey_installer/resources/verify.sh --no-gpu --no-isaac
CMD ["bash"]
