## 开发者开关集合。
##
## 全部是静态变量：游戏内用按键切换，不持久化（重启回到默认）。
## 以后新增调试功能：往这里加一个静态变量，再在对应的地方读取和按键切换。
## 未来可以包一层"开发者模式"总开关，控制这些开关是否可用。
class_name DevFlags
extends RefCounted

## 显示碰撞体轮廓（关卡：玩家移动碰撞；拼装：部件物理矩形）
static var show_collision := false

## 预留：显示 IK 调试点（髋/膝/踝三色圆点）
static var show_ik_points := false
