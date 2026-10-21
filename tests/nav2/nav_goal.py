"""Nav2 lifecycle 전부 active 확인 → ComputePathToPose → NavigateToPose 결과."""
import sys, time, rclpy
from rclpy.node import Node
from rclpy.action import ActionClient
from lifecycle_msgs.srv import GetState
from nav2_msgs.action import ComputePathToPose, NavigateToPose
from geometry_msgs.msg import PoseStamped

rclpy.init(); n = Node("nav_goal_test")
def state(name):
    c = n.create_client(GetState, f"/{name}/get_state")
    if not c.wait_for_service(timeout_sec=2): return "no-service"
    f = c.call_async(GetState.Request()); rclpy.spin_until_future_complete(n, f, timeout_sec=3)
    return f.result().current_state.label if f.result() else "timeout"
names = ["map_server", "amcl", "planner_server", "controller_server", "bt_navigator", "behavior_server", "velocity_smoother"]
deadline = time.time() + 120
while time.time() < deadline:
    st = {k: state(k) for k in names}
    if all(v == "active" for v in st.values()): break
    time.sleep(3)
print("LIFECYCLE", st)
goal = PoseStamped(); goal.header.frame_id = "map"
goal.pose.position.x, goal.pose.position.y = float(sys.argv[1]), float(sys.argv[2])
goal.pose.orientation.z, goal.pose.orientation.w = 1.0, 0.0
pc = ActionClient(n, ComputePathToPose, "/compute_path_to_pose"); pc.wait_for_server(timeout_sec=10)
g = ComputePathToPose.Goal(goal=goal, use_start=False)
f = pc.send_goal_async(g); rclpy.spin_until_future_complete(n, f, timeout_sec=10)
rf = f.result().get_result_async(); rclpy.spin_until_future_complete(n, rf, timeout_sec=20)
print("PATH_POSES", len(rf.result().result.path.poses) if rf.result() else "none")
nc = ActionClient(n, NavigateToPose, "/navigate_to_pose"); nc.wait_for_server(timeout_sec=10)
f = nc.send_goal_async(NavigateToPose.Goal(pose=goal)); rclpy.spin_until_future_complete(n, f, timeout_sec=10)
gh = f.result(); print("NAV_ACCEPTED", gh.accepted)
rf = gh.get_result_async(); rclpy.spin_until_future_complete(n, rf, timeout_sec=150)
print("NAV_STATUS", rf.result().status if rf.result() else "timeout", "(4=SUCCEEDED)")
