## 器官上的一个接点。
##
## 独立成 Resource 是为了能随器官一起存进 .tres；
## GDScript 内部类无法被资源系统稳定序列化。
class_name OrganPort
extends Resource

## 这个接点允许的连接方式
## NONE  = 普通接点，不能用来连肢体
## RIGID = 接上后角度锁死（躯干节之间）
## HINGE = 可转动，形成关节
enum JointRole { NONE, RIGID, HINGE }

@export var cell: Vector2i = Vector2i.ZERO   ## 相对器官原点的格坐标
@export var type: int = 0                    ## OrganData.NERVE / BLOOD / BONE
@export var uid: StringName = &""            ## 器官内唯一标识，用于建立链
@export var joint_role: int = JointRole.NONE ## 骨骼接点的关节类型


func _init(p_cell := Vector2i.ZERO, p_type := 0, p_uid: StringName = &"") -> void:
	cell = p_cell
	type = p_type
	uid = p_uid


func rotated(rotation: int) -> OrganPort:
	var p := cell
	for i in rotation:
		p = Vector2i(-p.y, p.x)
	var out := OrganPort.new(p, type, uid)
	out.joint_role = joint_role
	return out
