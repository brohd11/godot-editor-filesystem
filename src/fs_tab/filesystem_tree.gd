@tool
extends Tree

const _MIN_SIZE = Vector2(100,0)

#! import_p FileData,

const FSClasses = preload("res://addons/_lib/editor_filesystem/src/util/fs_classes.gd")
const FileSystemTab = FSClasses.FileSystemTab
const FileSystemTree = FSClasses.FileSystemTree
const FSTreeHelper = FSClasses.FSTreeHelper
const FSPopupHelper = FSClasses.FSPopupHelper

const FSUtil = FSClasses.FSUtil
const UFile = FSUtil.UFile
const UTree = FSUtil.UTree
const TreeAltColor = FSUtil.TreeAltColor
const UEditorTheme = FSUtil.UEditorTheme
const UVersion = FSUtil.UVersion

const FileData = FileSystemSingleton.FileData

var current_browser_state:FileSystemTab.BrowserState = FileSystemTab.BrowserState.BROWSE
var active:=true

var root_item:TreeItem

var global_buses = []

var root_dir = "res://"
var file_array = []

var tree_first_build:bool = false
var multi_selected_flag:bool = false
var only_send_to_filter:bool

var show_files:bool = false
var show_item_preview:bool = false

var sel_item_path:= ""

var filesystem_singleton:FileSystemSingleton
var filesystem_dirty:bool=false
var _force_refresh_queued:=false

var draw_alternate_line_colors:=false

var tree_helper:FSTreeHelper

signal left_clicked(selected_path:String, path_array:Array)
signal right_clicked(self_node, selected_path:String, path_array:Array)
signal double_clicked(selected_path:String)


func _ready() -> void:
	if is_part_of_edited_scene():
		return
	
	if UEditorTheme.get_current_theme_style() == "Modern" and UEditorTheme.get_custom_theme_path() == "":
		var sb = EditorInterface.get_editor_theme().get_stylebox("panel", "ItemList").duplicate()
		sb.bg_color = UEditorTheme.ThemeColor.get_theme_color(UEditorTheme.ThemeColor.Type.BASE).darkened(0.2)
		add_theme_stylebox_override("panel", sb)
	
	if UVersion.get_minor_version() > 5:
		scroll_hint_mode = Tree.SCROLL_HINT_MODE_BOTH
	
	custom_minimum_size = _MIN_SIZE
	
	allow_rmb_select = true
	allow_reselect = true
	select_mode = Tree.SELECT_MULTI
	hide_root = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	filesystem_singleton = FileSystemSingleton.get_instance()
	
	_new_tree_helper()
	
	item_edited.connect(_on_item_edited)

func _draw() -> void:
	if draw_alternate_line_colors:
		TreeAltColor.draw_lines(self)


func set_dir(target_dir:String, build:=false):
	root_dir = target_dir
	#_get_file_array(target_dir)
	if build:
		full_build()

func _new_tree_helper():
	tree_helper = FSTreeHelper.new(self)
	tree_helper.filesystem_singleton = filesystem_singleton
	
	tree_helper.mouse_double_clicked.connect(_on_tree_helper_mouse_double_clicked)
	tree_helper.multi_item_selected.connect(_on_tree_helper_multi_item_selected)
	tree_helper.mouse_left_clicked.connect(_on_tree_helper_mouse_left_clicked)
	tree_helper.mouse_right_clicked.connect(_on_tree_helper_mouse_right_clicked)

func _make_custom_tooltip(_for_text: String) -> Object:
	var item = get_item_at_position(get_local_mouse_position())
	if not is_instance_valid(item):
		return
	var path = tree_helper.get_path_from_item(item)
	if path == FileSystemTab.FAVORITES_META:
		return
	return FileSystemSingleton.get_custom_tooltip(path)


func set_active(active_state:bool):
	active = active_state
	#print("TREE ACTIVE: ", active_state)
	if active_state:
		refresh()
	else:
		clear_items()

func clear_items():
	tree_helper.clear_items_keep_paths()

func queue_force_refresh():
	_force_refresh_queued = true

func refresh():
	if filesystem_dirty or _force_refresh_queued:
		_force_refresh_queued = false
		full_build()
	else:
		quick_build()


func full_build():
	_get_file_array(root_dir)
	filesystem_dirty = false
	_build_tree()

func quick_build():
	if tree_helper.item_dict.is_empty():
		_build_tree()
	#_scroll_to_selected_and_emit()

func _get_file_array(dir):
	if dir == "res://":
		file_array = filesystem_singleton.file_and_dir_paths
	else:
		file_array = filesystem_singleton.get_files_in_dir(dir, true)

func _build_tree():
	if not is_instance_valid(tree_helper):
		_new_tree_helper()
	if not is_instance_valid(tree_helper.filesystem_singleton):
		tree_helper.filesystem_singleton = filesystem_singleton
	
	tree_helper.show_files = show_files
	
	var selected_paths = tree_helper.get_selected_paths().duplicate()
	
	#var folder_icon = filesystem_singleton.get_folder_icon()
	#var folder_color = filesystem_singleton.get_folder_color()
	
	var target_dir = root_dir
	
	tree_helper.clear_items()
	tree_helper.set_thumbnail_size()
	tree_helper.show_item_preview = show_item_preview
	tree_helper.updating = true
	
	var tree_root = create_item()
	if target_dir == "res://": # handle favorites
		var favorites_item = create_item(tree_root)
		favorites_item.set_text(0, FileSystemSingleton.get_favorites_text())
		favorites_item.set_icon(0, FileSystemSingleton.get_favorites_icon())
		favorites_item.set_metadata(0, {FileData.PATH: FileSystemTab.FAVORITES_META})
		var favorites = FileSystemSingleton.get_filesystem_favorites()
		for path in favorites:
			var item = create_item(favorites_item)
			var text = path.get_file()
			if path.ends_with("/"):
				text = path.trim_suffix("/").get_file()
			item.set_text(0, text)
			tree_helper.set_tree_item_params(path, item)
			tree_helper.item_dict[text] = item
	
	
	root_item = create_item(tree_root) as TreeItem
	tree_helper.parent_item = root_item
	tree_helper.item_dict[target_dir] = root_item
	
	if not DirAccess.dir_exists_absolute(target_dir):
		root_item.set_text(0, "Doesn't Exist: " + target_dir)
		return
	
	if target_dir == "res://": # handle favorites
		root_item.set_text(0, "res://")
	else:
		var target_dir_folder_name = target_dir.trim_suffix("/").get_file()
		root_item.set_text(0, target_dir_folder_name)
		var bg_color = filesystem_singleton.get_background_color(target_dir)
		if bg_color:
			root_item.set_custom_bg_color(0, bg_color)
	
	tree_helper.set_tree_item_params(target_dir, root_item)
	
	for file_path:String in file_array:
		var file_data = filesystem_singleton.get_file_data(file_path)
		if not file_data:
			continue
		
		var last_item:TreeItem = tree_helper.new_file_path(file_path, target_dir, file_data)
		last_item.set_metadata(0, file_data)
		var file_type = file_data.get(FileData.TYPE)
		if file_type != FileData.FOLDER:
			if not show_files:
				#last_item.visible = false
				last_item.free()
				tree_helper.item_dict.erase(file_path)
				continue
	
	if not tree_first_build:
		tree_first_build = true
	
	tree_helper.updating = false
	_select_selected_paths(selected_paths)
	
	if _is_filtering():
		_update_tree_items()

func scroll_to_path(path:String):
	var item = tree_helper.item_dict.get(path) as TreeItem
	if item:
		scroll_to_item(item, true)
	
	pass

func select_paths(paths:Array, emit_selected:bool=true, navigate:=false):
	deselect_all()
	tree_helper.clear_selection()
	_select_selected_paths(paths)
	tree_helper.uncollapse_items()
	if navigate:
		var item = tree_helper.get_tree_item(paths[0])
		tree_helper.show_tree_item(item)
	if emit_selected:
		_emit_item_selected()


func _select_selected_paths(selected_paths):
	for path in selected_paths:
		var item = tree_helper.item_dict.get(path) as TreeItem
		if item:
			item.select(0)

func get_selected_paths():
	return tree_helper.get_selected_paths()

func get_selected_items():
	var items = [] # tree_helper.get_selected_items not working..
	for p in tree_helper.get_selected_paths():
		items.append(tree_helper.get_tree_item(p))
	return items

func _scroll_to_selected_and_emit():
	var selected_paths = get_selected_paths()
	if not selected_paths.is_empty():
		var sel_item = tree_helper.item_dict.get(selected_paths[0])
		if sel_item:
			set_selected(sel_item,0)
			scroll_to_item(sel_item)

func set_filtered_paths(path_array:Array):
	tree_helper.filtered_item_paths = path_array

func update_filter():
	_update_tree_items()
	var selected_paths = tree_helper.get_selected_paths()
	if selected_paths.size() > 0:
		sel_item_path = selected_paths[0]

func _update_tree_items():
	var filter_callable = null #^ not used in this version, set the paths above
	var is_filtering = _is_filtering()
	tree_helper.update_tree_items(is_filtering, filter_callable, root_dir)
	tree_helper.uncollapse_items()
	#_scroll_to_selected_and_emit() #^ this was used to set the filter panel items, I think can be removed

func _is_filtering():
	return current_browser_state == FileSystemTab.BrowserState.SEARCH

func _emit_item_selected():
	var selected_paths = get_selected_paths()
	if selected_paths.is_empty():
		return
	var selected = get_selected()
	var path = tree_helper.get_path_from_item(selected)
	
	if tree_helper.is_item_in_favorites(selected) and not path.ends_with("/"):
		left_clicked.emit(FileSystemTab.FAVORITES_META, selected_paths)
	else:
		left_clicked.emit(path, selected_paths)


func _on_tree_helper_multi_item_selected():
	_emit_item_selected()

func _on_tree_helper_mouse_left_clicked():
	pass

func _on_tree_helper_mouse_double_clicked():
	var selected = get_selected()
	var meta = selected.get_metadata(0)
	var path = meta.get(FSTreeHelper.Keys.METADATA_PATH)
	
	if path.ends_with("/"):
		tree_helper.uncollapse_items()
		var item = tree_helper.get_tree_item(path)
		if item:
			item.collapsed = false
			tree_helper.show_tree_item(item)
	else:
		double_clicked.emit(path)
		#var selected_in_fs = select_selected_in_fs()
		#if not selected_in_fs:
			#return
		#filesystem_singleton.activate_in_fs()


func _on_tree_helper_mouse_right_clicked():
	var selected_item = get_selected()
	var data = selected_item.get_metadata(0)
	if not data:
		return
	var path = tree_helper.get_path_from_item(selected_item)
	if path == FileSystemTab.FAVORITES_META:
		return
	right_clicked.emit(self, path, tree_helper.get_selected_paths())



func rc_expand_folder():
	var items = get_selected_items()
	print(items)
	for item in items:
		item.collapsed = false

func rc_hierarchy(expand:bool):
	var selected = get_selected()
	selected.set_collapsed_recursive(not expand)



#region works but too jank

var original_file_name = ""
func start_edit():
	var item = get_selected()
	if not FileSystemTab.ATTEMPT_RENAME:
		var path = tree_helper.get_path_from_item(item)
		FileSystemSingleton.fs_navigate_to_path(path, true)
		return
	
	original_file_name = item.get_text(0)
	edit_selected(true)
	var line_edit = UTree.get_line_edit(self) as LineEdit
	var ext_idx = line_edit.text.find(".")
	if ext_idx > -1:
		line_edit.select(0, ext_idx)

func _on_item_edited():
	if not FileSystemTab.ATTEMPT_RENAME:
		return
	var item = get_edited()
	var new_name = item.get_text(0)
	
	if not FileSystemSingleton.is_new_name_valid(original_file_name, new_name):
		item.set_text(0, original_file_name)
		original_file_name = ""
		return
	var old_path = tree_helper.get_path_from_item(item)
	
	await FileSystemSingleton.rename_path(old_path, new_name)
	
	#var popup = _rename_popup()
	#while EditorInterface.get_resource_filesystem().is_scanning():
		#await get_tree().process_frame
	
	#popup.queue_free()
	#filesystem_singleton.rebuild_files()


func _rename_popup():
	var popup = Popup.new()
	var label = Label.new()
	label.text = "Scanning"
	popup.add_child(label)
	popup.transient = true
	popup.exclusive = true
	popup.unfocusable = true
	add_child(popup)
	popup.popup_centered()
	return popup

#endregion


func _get_drag_data(_at_position):
	var files = tree_helper.get_selected_paths().duplicate()
	files.erase(FileSystemTab.FAVORITES_META)
	files.erase("res://")
	if files.is_empty():
		return null
	set_drag_preview(FileSystemSingleton.get_drag_preview(files))
	return FileSystemSingleton.GetDropData.files(files, self)


func _can_drop_data(at_position, data):
	if current_browser_state == FileSystemTab.BrowserState.SEARCH:
		return false
	return FileSystemSingleton.CanDropData.files(at_position, data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var target_item = get_item_at_position(at_position)
	var meta = target_item.get_metadata(0)
	var target_dir = ""
	if meta is String:
		target_dir = meta
	if meta is Dictionary:
		target_dir = tree_helper.get_path_from_item(target_item)
	if not target_dir.ends_with("/"):
		target_dir = UFile.get_dir(target_dir)
	
	FileSystemSingleton.DropData.move_dialog(data, target_dir, self)
