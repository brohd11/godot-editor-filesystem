@tool
extends ItemList

const FSClasses = preload("res://addons/addon_lib/editor_filesystem/src/util/fs_classes.gd")
const FSUtil = FSClasses.FSUtil

const UWindow = FSUtil.UWindow
const LineSubmit = FSUtil.LineSubmit
const UEditorTheme = FSUtil.UEditorTheme
const UVersion = FSUtil.UVersion
const NUItemList = FSUtil.NUItemList
const UFile = FSUtil.UFile

const FileSystemTab = FSClasses.FileSystemTab
const FileSystemTree = FSClasses.FileSystemTree
const FSFilter = FSClasses.FSFilter

var filesystem_singleton:FileSystemSingleton

var draw_folder_tris:=false
var file_type_icon_size:Vector2 = Vector2(16, 16)
var file_type_icon_margin:Vector2 = Vector2(4, 4)

var current_browser_state:FileSystemTab.BrowserState = FileSystemTab.BrowserState.BROWSE
var current_view_mode:FileSystemTab.ViewMode = FileSystemTab.ViewMode.TREE
var active:=true

var tree_root:=""
var folder_view_root:="" #^ this is typically going to be the same as _current_dir, can it be replaced?
var disable_folder_root:=false
var display_file_type_icon:=true

var path_in_res:=true
var _filtered_paths:= PackedStringArray()
var display_as_list:=false
var draw_alternate_line_colors:=false

var _current_dir:= "res://"
var _current_paths:= []
var _current_path_hash:int = 0
var filesystem_dirty:=true
var _force_refresh_queued:=false
var _file_icons:= {}

var _selected_paths:=[]
var last_selected_path:String

signal selection_changed()

signal left_clicked(selected_path, selected_path_array)
signal right_clicked(self_node, selected_path, selected_path_array)
signal right_clicked_empty(self_node, selected_path)
signal double_clicked(selected_path)
signal navigate_up

func _ready() -> void:
	filesystem_singleton = FileSystemSingleton.get_instance()
	
	file_type_icon_size = Vector2(16, 16) * EditorInterface.get_editor_scale()
	file_type_icon_margin = Vector2(4, 4) * EditorInterface.get_editor_scale()
	
	NUItemList.replace_panel_stylebox_margin(self)
	
	
	#allow_rmb_select = true
	allow_reselect = true
	
	if UEditorTheme.get_current_theme_style() == "Modern" and UEditorTheme.get_custom_theme_path() == "":
		var sb = EditorInterface.get_editor_theme().get_stylebox("panel", "ItemList").duplicate()
		sb.bg_color = UEditorTheme.ThemeColor.get_theme_color(UEditorTheme.ThemeColor.Type.BASE).darkened(0.2)
		add_theme_stylebox_override("panel", sb)
	
	if UVersion.get_minor_version() > 5:
		scroll_hint_mode = ItemList.SCROLL_HINT_MODE_BOTH
	
	multi_selected.connect(_on_item_selected)
	item_clicked.connect(_on_item_clicked)
	item_activated.connect(_on_double_clicked)
	empty_clicked.connect(_on_empty_clicked)
	_set_list_settings()

func set_active(active_state:bool):
	active = active_state
	if active_state:
		refresh()
	else:
		clear_items()

func queue_force_refresh():
	_force_refresh_queued = true

func refresh():
	if not active:
		return
	#if current_browser_state == FileSystemTab.BrowserState.BROWSE:
	check_current_dir_contents()
	if filesystem_dirty or _force_refresh_queued:
		_force_refresh_queued = false
		_rebuild()

func _rebuild():
	clear_items()
	create_items()
	set_selected_paths(_selected_paths)

func clear_items():
	_selected_paths = get_selected_paths()
	clear()
	_file_icons.clear()



func set_display_as_list(toggled:bool, rebuild:=true):
	display_as_list = toggled
	_set_list_settings()
	if rebuild:
		_rebuild()


func _set_list_settings():
	same_column_width = true
	select_mode = ItemList.SELECT_MULTI
	if display_as_list:
		wraparound_items = false
		max_text_lines = 1
		max_columns = 1
		fixed_column_width = 0
		icon_mode = ItemList.ICON_MODE_LEFT
		fixed_icon_size = Vector2i(16,16) * EditorInterface.get_editor_scale()
	else:
		wraparound_items = true
		max_text_lines = 2
		max_columns = 0
		fixed_column_width = 96 * EditorInterface.get_editor_scale()
		icon_mode = ItemList.ICON_MODE_TOP
		fixed_icon_size = Vector2i(64,64) * EditorInterface.get_editor_scale()


func set_filtered_paths(paths:Array):
	_filtered_paths = paths

func _is_filtering() -> bool:
	return current_browser_state == FileSystemTab.BrowserState.SEARCH

func update_filter():
	_rebuild()


func set_current_path(path:String, set_folder_view:=false):
	set_current_dir(path, set_folder_view)
	
func set_current_dir(path:String, _refresh:=true):
	_current_dir = path
	folder_view_root = path
	if _refresh:
		refresh()

func check_current_dir_contents():
	_current_paths = get_paths_at_dir(_current_dir, path_in_res)
	var _hash = _current_paths.hash()
	#if not filesystem_dirty:
	filesystem_dirty = _hash != _current_path_hash
	_current_path_hash = _hash



func create_items():
	if path_in_res:
		_create_items_res()
	else:
		_create_items_not_res()

func _create_items_res():
	var folder_thumb = EditorInterface.get_editor_theme().get_icon("FolderBigThumb", "EditorIcons")
	var file_thumb = EditorInterface.get_editor_theme().get_icon("FileBigThumb", "EditorIcons")
	if display_as_list:
		folder_thumb = filesystem_singleton.get_folder_icon()
	
	var view_root = _get_folder_view_root(true)
	var paths = _get_paths_to_show()
	
	if view_root != "":# and view_root != tree_root:
		add_icon_item(folder_thumb)
		set_item_text(0, "..")
		set_item_selectable(0, false)
		var icon_color = filesystem_singleton.get_icon_color(view_root)
		if icon_color:
			set_item_icon_modulate(0, icon_color)
		set_item_metadata(0, view_root)
	
	for path:String in paths:
		var file_data = filesystem_singleton.get_file_data(path)
		var file_type_icon = file_data.get(FileSystemSingleton.FileData.TYPE_ICON)
		var item_icon:Texture2D
		if path.ends_with("/"):
			item_icon = folder_thumb
		else:
			var preview_data = FileSystemSingleton.get_preview(path)
			if display_as_list:
				if preview_data != null:
					item_icon = preview_data.get(FileSystemSingleton.FileData.Preview.THUMBNAIL)
				if item_icon == null:
					item_icon = file_type_icon
			else:
				#var preview_data = filesystem_singleton.get_preview(path)
				if preview_data != null:
					item_icon = preview_data.get(FileSystemSingleton.FileData.Preview.PREVIEW)
				else:
					var file_icon = file_data.get(FileSystemSingleton.FileData.TYPE_ICON)
					var custom_icon = file_data.get(FileSystemSingleton.FileData.CUSTOM_ICON)
					if not custom_icon:
						item_icon = file_thumb
					else:
						item_icon = file_icon
		
		var idx = add_icon_item(item_icon)
		_file_icons[idx] = file_type_icon
		set_item_metadata(idx, path)
		set_item_text(idx, path.trim_suffix("/").get_file())
		var icon_color = filesystem_singleton.get_icon_color(path)
		if icon_color:
			set_item_icon_modulate(idx, icon_color)

func _create_items_not_res():
	var folder_icon = EditorInterface.get_editor_theme().get_icon("FolderBigThumb", "EditorIcons")
	var folder_color = filesystem_singleton.get_folder_color()
	var file_icon = EditorInterface.get_editor_theme().get_icon("FileBigThumb", "EditorIcons")
	if display_as_list:
		folder_icon = filesystem_singleton.get_folder_icon()
		file_icon = EditorInterface.get_editor_theme().get_icon("File", "EditorIcons")
	
	var view_root = _get_folder_view_root(false)
	var paths = _get_paths_to_show()
	
	if view_root != "":# and not FSUtil.is_root_folder(_current_dir):
		add_icon_item(folder_icon)
		set_item_text(0, "..")
		set_item_selectable(0, false)
		set_item_icon_modulate(0, folder_color)
		set_item_metadata(0, view_root)
	
	for path:String in paths:
		var item_icon:Texture2D
		var icon_color = Color.WHITE
		if path.ends_with("/"):
			item_icon = folder_icon
			icon_color = folder_color
		else:
			item_icon = file_icon
		
		var idx = add_icon_item(item_icon)
		set_item_metadata(idx, path)
		set_item_text(idx, path.trim_suffix("/").get_file())
		set_item_icon_modulate(idx, icon_color)

func _get_folder_view_root(in_res:bool):
	if disable_folder_root:
		return ""
	var view_root = folder_view_root
	if _current_dir == FileSystemTab.FAVORITES_META:
		view_root = ""
	if _is_filtering() or FSUtil.is_root_folder(_current_dir):
		view_root = ""
	if in_res and current_view_mode == FileSystemTab.ViewMode.TREE and view_root == tree_root:
		view_root = ""
	return view_root

func _get_paths_to_show():
	var paths = _current_paths
	if _is_filtering():
		paths = _filtered_paths
	return paths

func get_paths_at_dir(path:String, _path_in_res:= true) -> Array:
	var paths
	if _path_in_res:
		if path == FileSystemTab.FAVORITES_META:
			paths = FileSystemSingleton.get_filesystem_favorites()
			paths.sort()
		else:
			paths = FileSystemSingleton.get_dir_contents(path)
	else:
		paths = []
		var dir_contents = UFile.get_dir_contents(path)
		var raw_dirs = dir_contents.get("dirs")
		for _name in raw_dirs:
			var full_path = path.path_join(_name) + "/"
			paths.append(full_path)
		
		var raw_files = dir_contents.get("files")
		for _name in raw_files:
			var full_path = path.path_join(_name)
			paths.append(full_path)
	
	return paths


func _draw() -> void:
	var ed_scale = EditorInterface.get_editor_scale()
	var scroll_bar_offset = Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)
	if display_as_list:
		if draw_alternate_line_colors:
			NUItemList.AltColor.draw_lines(self)
		if not draw_folder_tris:
			return
		var folder_texture = EditorInterface.get_editor_theme().get_icon("TransitionImmediate", "EditorIcons")
		var scroll_bar_vis = get_v_scroll_bar().visible
		for i in item_count:
			var path = get_item_metadata(i)
			if not path.ends_with("/"):
				continue
			var rect = get_item_rect(i, true)
			if rect.size.x < 150:
				break
			rect.position.y -= scroll_bar_offset.y
			if scroll_bar_vis:
				rect.position.x -= 10
			var og_x_size = rect.size.x
			var og_y_size = rect.size.y
			rect.size = Vector2(og_y_size * 0.75, og_y_size * 0.75)
			rect.position.x = rect.position.x + (og_x_size - (rect.size.y * 1.25))
			rect.position.y = rect.position.y + (og_y_size / 2) - (rect.size.y / 2)
			draw_texture_rect(folder_texture, rect, false, Color(0.7, 0.7, 0.7, 0.5))
		return
	
	#^ grid items
	if display_file_type_icon and path_in_res:
		var broken_file = EditorInterface.get_editor_theme().get_icon("FileBroken", "EditorIcons")
		for i in item_count:
			var path = get_item_metadata(i)
			if path.ends_with("/"):
				continue
			var rect = get_item_rect(i, false)
			var icon = _file_icons.get(i, broken_file)
			var display_rect = Rect2((rect.position - scroll_bar_offset) + file_type_icon_margin, file_type_icon_size)
			draw_texture_rect(icon, display_rect, false)
	
	var font = ThemeDB.get_default_theme().default_font
	var count = item_count
	if folder_view_root != "" and current_browser_state == FileSystemTab.BrowserState.BROWSE:
		count -= 1
		count = max(count, 0)
	var text = "Items: %s" % count
	var rect = get_rect()
	var pos = rect.size
	var string_size = font.get_string_size(text) * ed_scale
	pos.x -= string_size.x
	pos -= (Vector2(6,6) * ed_scale)
	
	draw_string(font, pos, text,0,-1, 14 * ed_scale, Color(1,1,1,0.7))


func get_selected_paths():
	var selected_items = get_selected_items()
	var paths = []
	for i:int in selected_items:
		paths.append(get_item_metadata(i))
	return paths

func set_selected_paths(paths:Array):
	for i in range(item_count):
		var path = get_item_path(i)
		if path in paths:
			select(i, false)

func get_item_path(idx:int):
	return get_item_metadata(idx)

func _on_empty_clicked(_at_pos:Vector2, mouse_button_idx:int):
	
	if mouse_button_idx == 1 or mouse_button_idx == 2:
		deselect_all()
	if mouse_button_idx == 2:
		if folder_view_root != "":
			right_clicked_empty.emit(self, folder_view_root)
			

func _on_item_selected(idx:int, selected:bool):
	if selected:
		var path = get_item_path(idx)
		_on_left_clicked(path)
		last_selected_path = path
	selection_changed.emit()

func _on_item_clicked(_index:int, at_pos:Vector2, mouse_button_idx:int):
	if mouse_button_idx == 2:
		var item_at_pos = get_item_at_position(at_pos)
		if not is_item_selectable(item_at_pos):
			return
		var path = get_item_path(item_at_pos)
		if not item_at_pos in get_selected_items():
			select(item_at_pos)
		
		_on_right_clicked(path)


func _on_left_clicked(path):
	left_clicked.emit(path, get_selected_paths())


func _on_right_clicked(path):
	var path_array = get_selected_paths()
	right_clicked.emit(self, path, path_array)

func _on_double_clicked(selected_item:int):
	var path = get_item_path(selected_item)
	if not path.ends_with("/"):
		double_clicked.emit(path)
	else:
		if path.ends_with("://"):
			return
		if path != folder_view_root:
			double_clicked.emit(path)
		else:
			navigate_up.emit()

func start_edit():
	if not FileSystemTab.ATTEMPT_RENAME:
		var path = get_selected_paths()[0]
		FileSystemSingleton.fs_navigate_to_path(path, true)
		return
	var selected = get_selected_items()[0]
	var old_name = get_item_text(selected)
	
	var item_rect = get_item_rect(selected, false)
	
	var window_pos = UWindow.get_window_global_position(get_window())
	item_rect.position += window_pos + get_global_rect().position
	item_rect.position.y -= get_v_scroll_bar().value
	if not display_as_list:
		item_rect.position.y +=  item_rect.size.y * 0.6
		item_rect.size.y *= 0.4
	
	var line = LineSubmit.new(self, item_rect)
	line.set_text(old_name, LineSubmit.SelectMode.BASENAME)
	var new_name = await line.line_submitted
	
	if not FileSystemSingleton.is_new_name_valid(old_name, new_name):
		return
	
	var old_path = get_selected_paths()[0]
	await FileSystemSingleton.rename_path(old_path, new_name)
	
	#while EditorInterface.get_resource_filesystem().is_scanning():
		#await get_tree().process_frame
		#
	#filesystem_singleton.rebuild_files()
	

func _make_custom_tooltip(_for_text: String) -> Object:
	var item = get_item_at_position(get_local_mouse_position(), true)
	if item > -1:
		var path = get_item_path(item)
		if path:
			return FileSystemSingleton.get_custom_tooltip(path)
	return null

func _get_drag_data(_at_position):
	var sel_paths = get_selected_paths()
	set_drag_preview(FileSystemSingleton.get_drag_preview(sel_paths))
	return FileSystemSingleton.GetDropData.files(sel_paths, self)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if current_browser_state == FileSystemTab.BrowserState.SEARCH:
		return false
	return FileSystemSingleton.CanDropData.files(at_position, data, [])

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var item = get_item_at_position(at_position, true)
	var path = folder_view_root
	if item > -1:
		path = get_item_path(item)
	if not path.ends_with("/"):
		path = UFile.get_dir(path)
	
	FileSystemSingleton.DropData.move_dialog(data, path, self)
