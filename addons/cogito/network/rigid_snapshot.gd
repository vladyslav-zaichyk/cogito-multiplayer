extends RefCounted
## RigidSnapshot: Stores a single state snapshot of a RigidBody3D at a specific time
## Used for time-based interpolation in Smooth Sync

var timestamp: float = 0.0
var position: Vector3 = Vector3.ZERO
var rotation: Quaternion = Quaternion.IDENTITY
var linear_velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
var flags: int = 0

const FLAG_KEYFRAME = 1
const FLAG_TELEPORT = 2
const FLAG_OWNERSHIP_CHANGE = 4
const FLAG_IS_CARRIED = 8

