"""Isaac Sim 대역 = /clock + odom->base_link TF + /chassis/odom + 2D/3D 라이다 (빈 공간).
cmd_vel(Twist 또는 TwistStamped)을 적분해 로봇을 실제로 움직인다. 검증 전용."""
import math, rclpy
from rclpy.node import Node
from rclpy.parameter import Parameter
from rosgraph_msgs.msg import Clock
from builtin_interfaces.msg import Time
from geometry_msgs.msg import TransformStamped, Twist, TwistStamped
from nav_msgs.msg import Odometry
from sensor_msgs.msg import LaserScan, PointCloud2, PointField
from tf2_ros import TransformBroadcaster

DT = 0.02
class FakeCarter(Node):
    def __init__(self):
        super().__init__("fake_carter", parameter_overrides=[Parameter("use_sim_time", value=False)])
        self.t = 1.0
        self.x = self.y = self.yaw = 0.0
        self.v = self.w = 0.0
        self.clock = self.create_publisher(Clock, "/clock", 10)
        self.odom = self.create_publisher(Odometry, "/chassis/odom", 10)
        self.scans = [self.create_publisher(LaserScan, t, 10) for t in ("/scan", "/front_2d_lidar/scan", "/back_2d_lidar/scan")]
        self.cloud = self.create_publisher(PointCloud2, "/front_3d_lidar/lidar_points", 10)
        self.tf = TransformBroadcaster(self)
        self.sub = None
        self.create_timer(DT, self.step)
        self.create_timer(1.0, self.attach_cmd_vel)
    def attach_cmd_vel(self):
        if self.sub: return
        types = dict(self.get_topic_names_and_types()).get("/cmd_vel", [])
        if "geometry_msgs/msg/TwistStamped" in types:
            self.sub = self.create_subscription(TwistStamped, "/cmd_vel", lambda m: self.set_vel(m.twist), 10)
        elif "geometry_msgs/msg/Twist" in types:
            self.sub = self.create_subscription(Twist, "/cmd_vel", self.set_vel, 10)
        if self.sub: self.get_logger().info(f"cmd_vel type {types}")
    def set_vel(self, tw):
        self.v, self.w = tw.linear.x, tw.angular.z
    def stamp(self):
        s = int(self.t); return Time(sec=s, nanosec=int((self.t - s) * 1e9))
    def step(self):
        self.t += DT
        self.yaw += self.w * DT
        self.x += self.v * math.cos(self.yaw) * DT
        self.y += self.v * math.sin(self.yaw) * DT
        st = self.stamp()
        self.clock.publish(Clock(clock=st))
        tf = TransformStamped()
        tf.header.stamp, tf.header.frame_id, tf.child_frame_id = st, "odom", "base_link"
        tf.transform.translation.x, tf.transform.translation.y = self.x, self.y
        tf.transform.rotation.z, tf.transform.rotation.w = math.sin(self.yaw / 2), math.cos(self.yaw / 2)
        self.tf.sendTransform(tf)
        od = Odometry(); od.header.stamp, od.header.frame_id, od.child_frame_id = st, "odom", "base_link"
        od.pose.pose.position.x, od.pose.pose.position.y = self.x, self.y
        od.pose.pose.orientation = tf.transform.rotation
        od.twist.twist.linear.x, od.twist.twist.angular.z = self.v, self.w
        self.odom.publish(od)
        sc = LaserScan(); sc.header.stamp, sc.header.frame_id = st, "base_link"
        sc.angle_min, sc.angle_max, sc.angle_increment = -math.pi, math.pi, math.pi / 180
        sc.range_min, sc.range_max = 0.1, 20.0
        sc.ranges = [float("inf")] * 360
        for p in self.scans: p.publish(sc)
        pc = PointCloud2(); pc.header.stamp, pc.header.frame_id = st, "base_link"
        pc.fields = [PointField(name=c, offset=4 * i, datatype=PointField.FLOAT32, count=1) for i, c in enumerate("xyz")]
        pc.point_step, pc.height, pc.width, pc.is_dense = 12, 1, 0, True
        self.cloud.publish(pc)

rclpy.init(); n = FakeCarter()
try: rclpy.spin(n)
except (KeyboardInterrupt, rclpy.executors.ExternalShutdownException): pass
