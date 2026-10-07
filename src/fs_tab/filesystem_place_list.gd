@tool
extends SplitContainer

const FSClasses = preload("res://addons/_lib/editor_filesystem/src/util/fs_classes.gd")
const FSUtil = FSClasses.FSUtil

const ClickState = FSUtil.ClickState
const UWindow = FSUtil.UWindow
const LineSubmit = FSUtil.LineSubmit
const ThemeColor = FSUtil.ThemeColor
const NUItemList = FSUtil.NUItemList

const FileSystemPlaces = FSClasses.FileSystemPlaces
const PlaceList = FSClasses.FileSystemPlaceList

var places_instance:FileSystemPlaces

var content_panel:PanelContainer
var content_vbox:VBoxContainer
var title_button:Button
var item_list:ItemList

var _title:String = "Places"
var _hovered_title:=false
#var _preview_state:=0
var _list_toggled:=true

var _list_hovered:=false

signal path_selected(path:String, _self)
signal right_clicked(index, _self)
signal title_right_clicked(_self)
signal move_lists(from, to)

signal list_changed


func _init(title:String) -> void:
	_title = title
	
func _ready() -> void:
	vertical = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	#content_panel = PanelContainer.new()
	#add_child(content_panel)
	#var sb = EditorInterface.get_editor_theme().get_stylebox("panel", "Panel")
	#content_panel.add_theme_stylebox_override("panel", sb)
	
	content_vbox = VBoxContainer.new()
	add_child(content_vbox)
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#content_vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	
	var sep = HSeparator.new()
	content_vbox.add_child(sep)
	
	title_button = Button.new()
	title_button.text = _title
	title_button.icon = _fold_icon_down()
	title_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	#title_button.flat = true
	title_button.theme_type_variation = &"BottomPanelButton"
	title_button.focus_mode = Control.FOCUS_NONE
	content_vbox.add_child(title_button)
	title_button.pressed.connect(toggle_list)
	title_button.mouse_filter = Control.MOUSE_FILTER_STOP
	title_button.gui_input.connect(_on_title_gui_input)
	title_button.draw.connect(_title_draw)
	title_button.mouse_exited.connect(func():_hovered_title = false;title_button.queue_redraw())
	title_button.set_drag_forwarding(_title_get_drag_data, _title_can_drop_data, _title_drop_data)
	
	item_list = ItemList.new()
	content_vbox.add_child(item_list)
	NUItemList.replace_panel_stylebox_margin(item_list, 0, false)
	item_list.draw.connect(_item_list_draw)
	item_list.allow_reselect = true
	#item_list.allow_rmb_select = true
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.item_clicked.connect(_on_item_clicked)
	item_list.item_selected.connect(_on_item_selected)
	item_list.set_drag_forwarding(_item_list_get_drag_data, _item_list_can_drop_data, _item_list_drop_data)
	item_list.mouse_exited.connect(func():_list_hovered = false; item_list.queue_redraw())
	

func _emit_list_changed():
	list_changed.emit.call_deferred()

func build_items(data:Dictionary):
	var indexes = data.keys()
	indexes.sort()
	for index in indexes:
		var item_data = data[index]
		new_item(item_data["name"], item_data["path"], false)

func get_item_count():
	return item_list.item_count

func _on_item_selected(index:int):
	var item_path = item_list.get_item_metadata(index)
	path_selected.emit(item_path, self)
	item_list.deselect_all()

func _on_item_clicked(index:int, _at_pos:Vector2, button_idx:int):
	if button_idx == 2:
		right_clicked.emit(index, self)

func has_path(path:String):
	for i in range(item_list.item_count):
		if item_list.get_item_metadata(i) == path:
			return true
	return false

func new_item(text:String, path:String, emit_sig:=true):
	item_list.add_item(text)
	var i = item_list.item_count - 1
	item_list.set_item_metadata(i, path)
	item_list.set_item_tooltip(i, path)
	if emit_sig:
		_emit_list_changed()

func get_item_path(index:int):
	return item_list.get_item_metadata(index)

func get_item_title(index:int):
	return item_list.get_item_text(index)

func set_item_title(index:int, new_name:String):
	item_list.set_item_text(index, new_name)

func rename_item(index:int):
	var item_rect = item_list.get_item_rect(index)
	item_rect.position += UWindow.get_control_absolute_position(item_list)
	var line_edit = LineSubmit.new(self, item_rect, false)
	var current_name = get_item_title(index)
	line_edit.set_text(current_name, LineSubmit.SelectMode.ALL)
	var resp:Dialogs.Response = await line_edit.handled
	var text = resp.payload
	if resp.cancelled or text == current_name or text == "":
		return
	set_item_title(index, text)
	_emit_list_changed()

func remove_item(index:int):
	item_list.remove_item(index)
	_emit_list_changed()

func move_item(from:int, to:int):
	item_list.move_item(from, to)
	_emit_list_changed()

func get_title():
	return _title

func set_title(new_name:String):
	title_button.text = new_name
	_title = new_name

func rename_title():
	var line = LineSubmit.on_control(title_button, false)
	line.set_text(title_button.text, LineSubmit.SelectMode.ALL)
	var resp:Dialogs.Response = await line.handled
	var submit = resp.payload
	if resp.cancelled or submit == "" or submit == get_title():
		return
	set_title(submit)
	_emit_list_changed()

func get_place_data():
	var data = {}
	for i in range(item_list.item_count):
		var _name = item_list.get_item_text(i)
		var _path = item_list.get_item_metadata(i)
		data[i] = FileSystemPlaces.Data.get_place_dict(_name, _path)
	return data

func get_place_paths():
	var paths = []
	for i in range(item_list.item_count):
		var _path = item_list.get_item_metadata(i)
		paths.append(_path)
	return paths

func _item_list_get_drag_data(at_position: Vector2) -> Variant:
	var from_item = item_list.get_item_at_position(at_position)
	var data = {
		"from": self,
		"from_item": from_item,
	}
	_set_drag_preview(get_item_title(from_item))
	return data

func _item_list_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var can_drop_item = _check_can_drop(data, "from_item")
	
	if can_drop_item:
		var from = data.get("from") as PlaceList
		var from_item = data["from_item"]
		var from_path = from.get_item_path(from_item)
		var _name = from.get_item_title(from_item)
		if not has_path(from_path):
			_highlight_list()
			return true
		elif from == self:
			return true
		elif from != self:
			pass #^ maybe do this later TODO
			#_set_drag_preview("List already has path.")
	
	var type = data.get("type", "")
	if type == "files_and_dirs":
		var files = data.get("files")
		for f in files:
			if f.ends_with("/") and not has_path(f):
				_highlight_list()
				return true
	return false

func _item_list_drop_data(at_position: Vector2, data: Variant) -> void:
	var from = data.get("from")
	if from is PlaceList:
		var from_item = data.get("from_item")
		if from == self:
			var to_item = item_list.get_item_at_position(at_position)
			move_item(from_item, to_item)
		else:
			var _name = from.get_item_title(from_item)
			var _path = from.get_item_path(from_item)
			from.item_list.remove_item(from_item) #^ operate on item list so list_changed doesn't fire
			new_item(_name, _path)
			var to_item = item_list.get_item_at_position(at_position, true)
			if to_item == -1:
				return
			await get_tree().process_frame
			
			move_item(item_list.item_count - 1, to_item)
	
	var type = data.get("type", "")
	if type == "files_and_dirs":
		var files = data.get("files")
		for f in files:
			if f.ends_with("/") and not has_path(f):
				new_item(f.trim_suffix("/").get_file(), f)

func _item_list_draw():
	NUItemList.AltColor.draw_lines(item_list)
	
	if _list_hovered:
		var accent_color = ThemeColor.get_theme_color(ThemeColor.Type.ACCENT)
		var rect = Rect2(Vector2.ZERO, item_list.size)
		item_list.draw_rect(rect, accent_color, false, 2)
	
	pass

func _on_title_gui_input(event:InputEvent):
	var click_state = ClickState.get_click_state(event) as ClickState.State
	if event is InputEventMouseButton:
		if click_state == ClickState.State.RMB_PRESSED:
			title_right_clicked.emit(self)

func _title_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var can_drop = _check_can_drop(data, "title")
	var from = data.get("from")
	if can_drop and from != self:
		_highlight_title(true)
		return true
	return false

func _title_drop_data(_at_position: Vector2, data: Variant) -> void:
	_highlight_title(false)
	var from = data.get("from")
	move_lists.emit(from, self)

func _title_get_drag_data(_at_position: Vector2) -> Variant:
	var data = {
		"from": self,
		"title":true
	}
	_set_drag_preview(get_title())
	return data

func _highlight_list(_state:bool=true):
	_list_hovered = true
	item_list.queue_redraw()

func _highlight_title(state:bool=true):
	_hovered_title = state
	title_button.queue_redraw()

func _title_draw():
	var lab_rect = Rect2(Vector2.ZERO, title_button.size)
	if _hovered_title:
		var accent_color = ThemeColor.get_theme_color(ThemeColor.Type.ACCENT)
		title_button.draw_rect(lab_rect, accent_color, false)

func toggle_list():
	_list_toggled = not _list_toggled
	_toggle_list(_list_toggled)

func _toggle_list(state:bool):
	item_list.visible = state
	if state:
		title_button.icon = _fold_icon_down()
		content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		dragging_enabled = true
	else:
		title_button.icon = _fold_icon_right()
		content_vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		dragging_enabled = false
	title_button.queue_redraw()



func _set_drag_preview(text):
	var preview = Label.new()
	preview.text = text
	set_drag_preview(preview)

func _check_can_drop(data:Dictionary, key:String):
	var from = data.get("from")
	if from and from is PlaceList:
		if from.places_instance != places_instance:
			return false
		if data.has(key):
			return true
	return false

func _fold_icon_down():
	return EditorInterface.get_editor_theme().get_icon("CodeFoldDownArrow", "EditorIcons")

func _fold_icon_right():
	return EditorInterface.get_editor_theme().get_icon("CodeFoldedRightArrow", "EditorIcons")
