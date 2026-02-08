extends Area2D

# 对话节点结构
class DialogueNode:
	var id: String
	var text: String
	var options: Array  # 每个选项是字典：{text: "选项文本", next_id: "下一个节点ID", condition: 可选条件函数}
	
	func _init(node_id: String, node_text: String, node_options: Array = []):
		id = node_id
		text = node_text
		options = node_options

# 对话树配置 - 可导出以便在编辑器中编辑
@export var dialogue_tree: Dictionary = {
	"start": {
		"text": "废弃的文件夹 空的 上面有三个纸条",
		"options": [
			{"text": "第一张纸条", "next_id": "about_place"},
			{"text": "第二张纸条", "next_id": "how_to_start"},
			{"text": "第三张纸条", "next_id": "other_npcs"},
			{"text": "离开", "next_id": "goodbye"}
		]
	},
	"about_place": {
		"text": "第一张纸条的一部分被污损了，上面隐隐约约能看见几个字 ██他们 ████了██ ████████队██ R██3365",
		"options": [
			{"text": "翻到背面", "next_id": "more_info"},
			{"text": "第二张纸条", "next_id": "how_to_start"},
			{"text": "看来没什么可以看的了", "next_id": "start"}
		]
	},
	"how_to_start": {
		"text": "第二张纸条看来是一个任务纸的一部分 这是一个叫雪杉行动的任务 后面被人写了“骗子”两个字",
		"options": [
			{"text": "看来没什么可以看的了", "next_id": "start"},
			{"text": "第三张纸条", "next_id": "other_npcs"}
		]
	},
	"more_info": {
		"text": "翻到背面 可以发现上面写了雪杉行动四个字 看来和第二张纸条有关",
		"options": [
			{"text": "看来没什么可以看的了", "next_id": "start"}
		]
	},
	"other_npcs": {
		"text": "第三张纸条占满了血迹，隐隐约约的能看到名字“阿廖沙”",
		"options": [
			{"text": "看来没什么可以看的了", "next_id": "start"}
		]
	},
	"goodbye": {
		"text": "...",
		"options": []
	}
}

# 对话显示时间（秒） - 用于自动前进的对话
@export var dialogue_display_time: float = 5.0

# 信号
signal dialogue_started
signal dialogue_finished
signal option_selected(option_text, next_node_id)

var player_in_range: bool = false
var current_node_id: String = "start"
var is_dialogue_active: bool = false

# UI节点
var dialogue_canvas: CanvasLayer
var dialogue_panel: Panel
var dialogue_label: Label
var options_container: VBoxContainer
var dialogue_timer: Timer

func _ready():
	# 设置分组
	add_to_group("npc")
	
	# 创建对话UI
	_create_dialogue_ui()
	
	# 连接信号
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	
	print("[level:Beginner's Tutorial] [NPC] NPC已加载，对话树节点数：", dialogue_tree.size())

func _create_dialogue_ui():
	# 创建CanvasLayer
	dialogue_canvas = CanvasLayer.new()
	dialogue_canvas.name = "DialogueCanvas"
	dialogue_canvas.layer = 10
	add_child(dialogue_canvas)
	
	# 创建对话面板
	dialogue_panel = Panel.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_panel.offset_top = -200
	dialogue_panel.offset_bottom = -20
	dialogue_panel.offset_left = 20
	dialogue_panel.offset_right = -20
	
	# 样式
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0, 0, 0, 0.8)
	dialogue_panel.add_theme_stylebox_override("panel", stylebox)
	
	dialogue_canvas.add_child(dialogue_panel)
	
	# 创建垂直容器
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_top = 15
	main_vbox.offset_bottom = -15
	main_vbox.offset_left = 15
	main_vbox.offset_right = -15
	dialogue_panel.add_child(main_vbox)
	
	# 创建对话文本标签
	dialogue_label = Label.new()
	dialogue_label.name = "DialogueLabel"
	dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.add_theme_font_size_override("font_size", 18)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	main_vbox.add_child(dialogue_label)
	
	# 创建选项容器
	options_container = VBoxContainer.new()
	options_container.name = "OptionsContainer"
	options_container.add_theme_constant_override("separation", 10)
	main_vbox.add_child(options_container)
	
	# 创建计时器（用于无选项时的自动关闭）
	dialogue_timer = Timer.new()
	dialogue_timer.name = "DialogueTimer"
	dialogue_timer.one_shot = true
	dialogue_timer.connect("timeout", Callable(self, "_on_dialogue_timer_timeout"))
	add_child(dialogue_timer)
	
	# 初始隐藏
	dialogue_panel.hide()

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		print("[level:Beginner's Tutorial] [NPC] 玩家进入NPC范围")

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		print("[level:Beginner's Tutorial] [NPC] 玩家离开NPC范围")
		if is_dialogue_active:
			_end_dialogue()

func start_dialogue():
	if not player_in_range or is_dialogue_active:
		return
	
	is_dialogue_active = true
	current_node_id = "start"
	dialogue_started.emit()
	
	_show_current_node()

func _show_current_node():
	# 清理选项容器
	_clear_options()
	
	# 获取当前节点数据
	var node_data = dialogue_tree.get(current_node_id)
	if not node_data:
		print("[level:Beginner's Tutorial] [NPC] [ERROR] 找不到对话节点：", current_node_id)
		_end_dialogue()
		return
	
	# 显示对话文本
	dialogue_label.text = node_data["text"]
	
	# 获取选项
	var options = node_data.get("options", [])
	
	if options.is_empty():
		# 没有选项，自动关闭对话
		dialogue_timer.start(dialogue_display_time)
		options_container.hide()
	else:
		# 显示选项按钮
		dialogue_timer.stop()
		options_container.show()
		_create_option_buttons(options)
	
	# 显示面板
	dialogue_panel.show()

func _clear_options():
	for child in options_container.get_children():
		child.queue_free()

func _create_option_buttons(options):
	for option in options:
		var button = Button.new()
		button.text = option["text"]
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
		
		# 设置按钮样式
		var button_style = StyleBoxFlat.new()
		button_style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
		button.add_theme_stylebox_override("normal", button_style)
		
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.3, 0.3, 0.4, 0.9)
		button.add_theme_stylebox_override("hover", hover_style)
		
		# 连接点击事件
		button.connect("pressed", Callable(self, "_on_option_selected").bind(option))
		
		options_container.add_child(button)

func _on_option_selected(option):
	var next_id = option.get("next_id", "")
	option_selected.emit(option["text"], next_id)
	
	if next_id == "" or next_id == "end":
		_end_dialogue()
	else:
		current_node_id = next_id
		_show_current_node()

func _on_dialogue_timer_timeout():
	_end_dialogue()

func _end_dialogue():
	dialogue_panel.hide()
	is_dialogue_active = false
	dialogue_finished.emit()
	print("[level:Beginner's Tutorial] [NPC] 对话结束")

# 公开方法
func interact():
	if player_in_range:
		if not is_dialogue_active:
			start_dialogue()
		else:
			# 如果对话已激活，按E键可以快速跳过？
			pass

# 设置新的对话树
func set_dialogue_tree(new_tree: Dictionary):
	dialogue_tree = new_tree
	print("[level:Beginner's Tutorial] [NPC] 已更新NPC对话树")

# 获取当前对话节点
func get_current_node():
	return dialogue_tree.get(current_node_id, {})

# 跳转到指定节点
func jump_to_node(node_id: String):
	if dialogue_tree.has(node_id):
		current_node_id = node_id
		if is_dialogue_active:
			_show_current_node()
		return true
	return false
