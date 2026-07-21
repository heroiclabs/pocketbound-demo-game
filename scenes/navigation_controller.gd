class_name NavigationController
extends RefCounted

enum Screen { MENU, MY_LEVELS, COMMUNITY_LEVELS, CREATOR, PLAYER, LEVEL_COMPLETE }

var _stack: Array[int] = []


func current() -> int:
	if _stack.is_empty():
		return Screen.MENU
	return _stack[_stack.size() - 1]


func set_root(screen: int) -> void:
	_stack.clear()
	_stack.append(screen)


func push(screen: int) -> void:
	_stack.append(screen)


func pop() -> void:
	if _stack.size() <= 1:
		return
	_stack.pop_back()


func size() -> int:
	return _stack.size()


func replace_top(screen: int) -> void:
	if _stack.is_empty():
		_stack.append(screen)
	else:
		_stack[_stack.size() - 1] = screen


func peek_prev() -> int:
	if _stack.size() < 2:
		return -1
	return _stack[_stack.size() - 2]
