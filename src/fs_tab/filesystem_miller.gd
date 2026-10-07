@tool
extends VBoxContainer

const FSClasses = preload("res://addons/_lib/editor_filesystem/src/util/fs_classes.gd")
const FSUtil = FSClasses.FSUtil

const ClickState = FSUtil.ClickState
const UFile = FSUtil.UFile
const ThemeColor = FSUtil.ThemeColor
const ColumnDragger = FSUtil.ColumnDragger

const FileSystemTab = FSClasses.FileSystemTab
const FileSystemItemList = FSClasses.FileSystemItemList



const MIN_COL_SIZE = 300

var scroll_container:ScrollContainer
var column_hbox:HBoxContainer
var column_spacer:Control

var current_browser_state:FileSystemTab.BrowserState = FileSystemTab.BrowserState.BROWSE
var active:= true

var _filtered_item_paths = []
var _filtered_item_paths_hash:int=0
var _new_filtered_paths:=true

var _columns := {}
var _search_column:FileColumn
var _search_history_path:String = ""
var _last_selected_search_item_path:String = ""

var _current_scroll_amount:float=0

var draw_alt_color:=false

var path_in_res:=true
var current_path := ""
var _current_dir := "res://" # set default so it builds at least
var _history_path := ""

var multi_select_dir:=""

signal left_clicked(path, selected_paths)
signal right_clicked(self_node, path, array)
signal double_clicked(path)

func _ready() -> void:
	if is_part_of_edited_scene():
		return
	var ed_scale = EditorInterface.get_editor_scale()
	var min_col_size = MIN_COL_SIZE * ed_scale
	
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container = ScrollContainer.new()
	add_child(scroll_container)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var _scroll_hbox = HBoxContainer.new()
	scroll_container.add_child(_scroll_hbox)
	_scroll_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	column_hbox = HBoxContainer.new() #^ TODO RENAME TO COLUMN HBOX
	column_hbox.add_theme_constant_override("separation", 0)
	_scroll_hbox.add_child(column_hbox)
	column_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	column_spacer = Control.new()
	_scroll_hbox.add_child(column_spacer)
	_scroll_hbox.add_theme_constant_override("separation", 0)
	column_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column_spacer.custom_minimum_size = Vector2(min_col_size, 0) * 2
	
	scroll_container.resized.connect(func(): column_spacer.custom_minimum_size.x = min(scroll_container.size.x / 2, min_col_size))

func set_active(active_state:bool):
	active = active_state
	if active_state:
		refresh()
		scroll_container.scroll_horizontal = int(_current_scroll_amount)
	else:
		_current_scroll_amount = scroll_container.scroll_horizontal
		_clear_columns("", true)

func on_filesystem_changed():
	for col:FileColumn in get_columns():
		if is_instance_valid(col.item_list):
			col.item_list.filesystem_dirty = true

func set_alt_list_colors(state:bool):
	draw_alt_color = state
	for col:FileColumn in get_columns():
		if is_instance_valid(col.item_list):
			col.item_list.draw_alternate_line_colors = state
			col.item_list.queue_redraw()

func queue_force_refresh():
	for col:FileColumn in get_columns():
		if is_instance_valid(col.item_list):
			col.item_list.queue_force_refresh()

func refresh():
	_build_columns()

func set_current_dir(path:String):
	if path == "FAVORITES":
		return
	_current_dir = path


func _build_columns(force_show_current:=false):
	if current_browser_state == FileSystemTab.BrowserState.BROWSE:
		await _build_normal_columns()
	elif current_browser_state == FileSystemTab.BrowserState.SEARCH:
		await _build_search_column()
	
	if force_show_current:
		#await get_tree().process_frame
		show_current_column()


func _build_normal_columns():
	var path_to_display = _current_dir
	if _current_dir == "":
		return
	
	var force_rebuild = not FSUtil.paths_have_same_root(_history_path, _current_dir)
	var path_is_ancestor = UFile.is_dir_in_or_equal_to_dir(_history_path, _current_dir)
	var use_history_path = false
	if path_is_ancestor and not force_rebuild:
		use_history_path = true
		path_to_display = _history_path
	else:
		_history_path = _current_dir
	
	var current_dir = _current_dir
	if not current_dir.ends_with("/"):
		current_dir = UFile.get_dir(current_dir)
	
	if multi_select_dir != "":
		current_dir = multi_select_dir
	
	_free_search_column()
	_clear_columns(path_to_display, force_rebuild)
	
	var path_parts = _get_path_parts(path_to_display)
	var root = path_parts.root
	var parts = path_parts.parts
	
	var working_path = root
	var current_col = _get_or_build_column(working_path)
	
	var col = _build_path_parts(current_dir, working_path, parts)
	if is_instance_valid(col):
		current_col = col
	
	if current_path.ends_with("/"): #^ ensures dir clicking in doesn't have items cleared
		current_dir = UFile.get_dir(current_dir)
	select_path_items(current_dir)
	
	if multi_select_dir != "": #^ dir with multi selected to current
		set_current_column_with_path(current_dir)
	else: #^ sets either file's dir or selected dir's contents to current
		if is_instance_valid(current_col):
			_set_current_column(current_col)
	
	await get_tree().process_frame
	
	if is_instance_valid(current_col):
		if not use_history_path:
			scroll_container.ensure_control_visible(current_col.item_list)


func set_filtered_paths(path_array:Array):
	var _hash = path_array.hash()
	_new_filtered_paths = _filtered_item_paths_hash != _hash
	_filtered_item_paths_hash = _hash
	_filtered_item_paths = path_array
	var sort = func(a:String, b:String):
		var a_dir = a.ends_with("/")
		var b_dir = b.ends_with("/")
		if a_dir and b_dir:
			return a < b
		elif a_dir:
			return true
		elif b_dir:
			return false
		return a < b
	
	_filtered_item_paths.sort_custom(sort)


func update_filter():
	start_search()
	scroll_container.scroll_horizontal = 0

func start_search():
	_clear_columns("", true)
	_search_history_path = _current_dir
	_search(_search_history_path)

func set_current_dir_search(path:String):
	_search(path)

func _search(current_search_path:String):
	_build_search_column()
	_build_columns_search(current_search_path)

func _build_columns_search(search_path:String):
	var selected_search_item_path = _get_search_column_selected_path()
	var force_column_rebuild = selected_search_item_path != _last_selected_search_item_path
	
	if selected_search_item_path == "" or not selected_search_item_path.ends_with("/"):
		_clear_columns("%SEARCH", true)
		_set_current_column(_search_column)
		_search_history_path = selected_search_item_path
		return
	
	_last_selected_search_item_path = selected_search_item_path
	
	var path_to_display = search_path
	var use_history_path = false
	var path_is_ancestor = UFile.is_dir_in_or_equal_to_dir(_search_history_path, search_path)
	if path_is_ancestor and not force_column_rebuild: #^ if force, will start a new column stack
		use_history_path = true
		path_to_display = _search_history_path
	else:
		_search_history_path = search_path
	
	var path_tail = path_to_display.trim_prefix(selected_search_item_path)
	var current_dir = search_path
	if not current_dir.ends_with("/"):
		current_dir = UFile.get_dir(current_dir)
	
	if multi_select_dir != "":
		current_dir = multi_select_dir
	
	_clear_columns(path_to_display, force_column_rebuild)
	
	var working_path = selected_search_item_path
	var current_col = _get_or_build_column(working_path)
	
	var parts = path_tail.split("/", false)
	var col = _build_path_parts(current_dir, working_path, parts)
	if is_instance_valid(col):
		current_col = col
	
	_set_current_column(current_col)
	
	#select_path_items(search_path)
	
	await get_tree().process_frame
	
	if not use_history_path:
		scroll_container.ensure_control_visible(current_col.item_list)
	


func _build_search_column():
	if not is_instance_valid(_search_column):
		_new_column("%SEARCH") #^ this will make it not set path
		_search_column.set_path_in_res(path_in_res)
		_search_column.set_filtering(true)
	
	if _new_filtered_paths:
		_new_filtered_paths = false
		_search_column.set_filtered_paths(_filtered_item_paths, true)
	

func _get_search_column_selected_path():
	var paths = _search_column.item_list.get_selected_paths()
	if not paths.is_empty():
		return paths[0]
	return ""



func _build_path_parts(current_dir:String, working_path:String, parts:PackedStringArray, select:=true): #^ select was causing issues probably remove
	var current_col
	for i in range(parts.size()):
		var part = parts[i]
		#var dir_path = working_path #^ for select
		
		working_path = working_path.path_join(part)
		var is_dir = DirAccess.dir_exists_absolute(working_path)
		if is_dir:
			working_path += "/"
		
		#_select_item_path(dir_path, working_path) #^ select is for this
		
		if not is_dir:
			break
		var col = _get_or_build_column(working_path)
		if working_path == current_dir:
			current_col = col
	
	return current_col

func _get_path_parts(path:String):
	var parts
	var root
	if path.find("://") > -1:
		root = path.get_slice("://", 0) + "://"
		parts = path.get_slice("://", 1).split("/", false)
	else:
		root = "/"
		parts = path.split("/", false)
	
	return {"root": root, "parts": parts}


func _get_or_build_column(working_path:String):
	var col:FileColumn = _columns.get(working_path)
	if not is_instance_valid(col):
		col = _new_column(working_path)
	else:
		col.set_path_in_res(path_in_res)
		col.set_current_path(working_path)
	return col

func _new_column(path:String="%SEARCH") -> FileColumn:
	var column = FileColumn.new()
	column_hbox.add_child(column)
	
	column.left_clicked.connect(_on_column_left_clicked)
	column.right_clicked.connect(_on_column_right_clicked)
	column.double_clicked.connect(_on_column_double_clicked)
	column.forward_gui.connect(_on_column_list_input_event)
	
	column.item_list.draw_alternate_line_colors = draw_alt_color
	
	if path == "%SEARCH":
		_search_column = column
		column_hbox.move_child(_search_column, 0)
	else:
		_columns[path] = column
		column.set_path_in_res(path_in_res)
		column.set_current_path(path)
	
	return column


func select_path_items(path:String):
	var data = _get_path_parts(path)
	var root = data.root
	var parts = data.parts
	var working_path = root
	for i in range(parts.size()):
		var part = parts[i]
		var dir_path = working_path
		working_path = working_path.path_join(part)
		if DirAccess.dir_exists_absolute(working_path):
			working_path += "/"
		_select_item_path(dir_path, working_path)

func _select_item_path(dir_path:String, item_path:String):
	var col:FileColumn = _columns.get(dir_path)
	if is_instance_valid(col):
		col.select_item(item_path)
	

func set_current_column_with_path(path:String):
	var column:FileColumn = _columns.get(path)
	if column:
		_set_current_column(column)
	else:
		set_current_dir(path)

func _set_current_column(current:FileColumn):
	for col:FileColumn in get_columns():
		if col == current:
			col.is_current = true
		else:
			col.is_current = false
		col.redraw()

func get_columns():
	return column_hbox.get_children()

func show_current_column():
	for col in column_hbox.get_children():
		if col.is_current:
			scroll_container.ensure_control_visible(col.item_list)

func clear_columns():
	_clear_columns("", true)

func _clear_columns(path_to_display:String, clear_all:=false):
	for column:FileColumn in column_hbox.get_children():
		if column == _search_column:
			continue
		
		var path = column.current_path
		if not UFile.is_dir_in_or_equal_to_dir(path_to_display, path) or clear_all:
			var par = column.get_parent()
			par.remove_child(column)
			column.queue_free()
			_columns.erase(path)

func _free_search_column():
	if is_instance_valid(_search_column):
		column_hbox.remove_child(_search_column)
		_search_column.queue_free()


func _on_column_left_clicked(path:String, paths:Array):
	get_window().gui_release_focus()
	left_clicked.emit(path, paths)

func _on_column_right_clicked(file_column:FileColumn, path:String, array:Array):
	get_window().gui_release_focus()
	_set_current_column(file_column)
	right_clicked.emit(file_column.item_list, path, array)

func _on_column_double_clicked(path:String):
	double_clicked.emit(path)

func _on_column_list_input_event(event:InputEvent):
	var click_state = ClickState.get_click_state(event) as ClickState.State
	if click_state == ClickState.State.WHEEL_LEFT or click_state == ClickState.State.WHEEL_UP:
		scroll_container.scroll_horizontal -= scroll_container.size.x / 8
	elif click_state == ClickState.State.WHEEL_RIGHT or click_state == ClickState.State.WHEEL_DOWN:
		scroll_container.scroll_horizontal += scroll_container.size.x / 8



class FileColumn extends HBoxContainer:
	var current_path:String
	var item_list:FileSystemItemList
	var is_current:=false
	
	var has_vertical_scroll:= false
	var has_horizontal_scroll:= false
	signal forward_gui(event)
	
	signal left_clicked(path, selected_paths)
	signal right_clicked(path)
	signal double_clicked(path)
	
	var sel_timer:Timer
	
	func _ready() -> void:
		add_theme_constant_override("separation", 0)
		#size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		var vbox = VBoxContainer.new()
		add_child(vbox)
		vbox.custom_minimum_size = Vector2(MIN_COL_SIZE * EditorInterface.get_editor_scale(), 0)
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var dragger = ColumnDragger.new()
		add_child(dragger)
		dragger.target_control = vbox
		dragger.drag_ended.connect(_check_mouse_filter)
		
		item_list = FileSystemItemList.new()
		vbox.add_child(item_list)
		item_list.disable_folder_root = true
		item_list.draw_folder_tris = true
		item_list.set_display_as_list(true, false)
		item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_list.focus_mode = Control.FOCUS_NONE
		
		sel_timer = Timer.new()
		add_child(sel_timer)
		sel_timer.one_shot = true
		sel_timer.timeout.connect(_on_selection_changed_debounced)
		item_list.selection_changed.connect(func(): sel_timer.start(0.1))
		
		#item_list.left_clicked.connect(func(path, paths):left_clicked.emit(path, paths))
		item_list.double_clicked.connect(func(path):double_clicked.emit(path))
		#^ right click pass FileColumn as arg to redraw columns
		item_list.right_clicked.connect(func(_s, p, arr):right_clicked.emit(self, p, arr))
		
		item_list.draw.connect(_item_draw)
		item_list.gui_input.connect(_on_item_list_gui_input)
	
	func select_item(path:String):
		item_list.deselect_all()
		item_list.set_selected_paths([path])
		item_list.queue_redraw()
		
		#if not item_list._selected_paths.has(path):
			#item_list._selected_paths.append(path)
		#item_list.set_selected_paths(item_list._selected_paths)
	
	func set_path_in_res(state:bool):
		item_list.path_in_res = state
	
	func set_current_path(path:String):
		current_path = path
		item_list.set_current_dir(path)
		_check_mouse_filter()
	
	func refresh():
		item_list.refresh()
		_check_mouse_filter()
	
	func _on_selection_changed_debounced():
		var sel_paths = item_list.get_selected_paths()
		if sel_paths.size() > 0:
			var selected_path = item_list.last_selected_path
			if not selected_path in sel_paths:
				selected_path = sel_paths[0]
			left_clicked.emit(selected_path, sel_paths)
		
	
	func _on_left_clicked(path:String, paths:Array):
		return
		left_clicked.emit(path, paths)
	
	func set_filtered_paths(paths, update:=false):
		item_list.set_filtered_paths(paths)
		if update:
			item_list.update_filter()
		_check_mouse_filter()
	
	func _check_mouse_filter():
		await get_tree().process_frame
		has_vertical_scroll = item_list.get_v_scroll_bar().visible
		has_horizontal_scroll = item_list.get_h_scroll_bar().visible
	
	func set_filtering(state:bool):
		if state:
			item_list.current_browser_state = FileSystemTab.BrowserState.SEARCH
		else:
			item_list.current_browser_state = FileSystemTab.BrowserState.BROWSE
	
	func redraw():
		item_list.queue_redraw()
	
	func _item_draw() -> void:
		if is_current:
			var accent_color = ThemeColor.get_theme_color(ThemeColor.Type.ACCENT)
			var rect = item_list.get_rect()
			item_list.draw_rect(rect, accent_color, false, 4)
	
	func _on_item_list_gui_input(event:InputEvent):
		if has_vertical_scroll or has_horizontal_scroll:
			item_list.mouse_force_pass_scroll_events = false
		else:
			item_list.mouse_force_pass_scroll_events = true
		if has_vertical_scroll and has_horizontal_scroll:
			return
		
		var click_state = ClickState.get_click_state(event) as ClickState.State
		if click_state == ClickState.State.WHEEL_LEFT or click_state == ClickState.State.WHEEL_RIGHT:
			if has_vertical_scroll:
				forward_gui.emit(event)
				accept_event()
		elif click_state == ClickState.State.WHEEL_UP or click_state == ClickState.State.WHEEL_DOWN:
			if has_horizontal_scroll:
				forward_gui.emit(event)
				accept_event()
		
