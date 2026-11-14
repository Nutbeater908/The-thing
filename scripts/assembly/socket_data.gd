## 一个接口（或挂点）。部件用 sockets 接子件，用 anchor 挂到父件上。
class_name SocketData
extends Resource

enum Kind { STRUCT, TOOL }
## 接口轴向：决定严格侧视下看到的是"完整圆"还是"侧边轮廓"
enum Axis { DEPTH, RIGHT, UP, LEFT, DOWN }

## 部件内部的名字，存档与连接都靠它
@export var uid: StringName
## 相对部件左上角的偏移（世界像素）
@export var offset := Vector2.ZERO
@export var kind := Kind.STRUCT
## 接口朝向（朝外）：插头方向必须与之相反
@export var dir := Vector2i.RIGHT
## 轴线方向；DEPTH = 面朝观察者，画成完整圆
@export var axis := Axis.DEPTH

static func opposite(d: Vector2i) -> Vector2i:
	return Vector2i(-d.x, -d.y)

static func rotate_vec(v: Vector2, rotation: int) -> Vector2:
	var out := v
	for i in rotation % 4:
		out = Vector2(-out.y, out.x)
	return out

static func rotate_dir(d: Vector2i, rotation: int) -> Vector2i:
	var out := d
	for i in rotation % 4:
		out = Vector2i(-out.y, out.x)
	return out
