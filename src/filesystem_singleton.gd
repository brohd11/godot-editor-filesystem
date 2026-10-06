#! namespace EditorFS class Singleton
@tool
class_name FileSystemSingleton
extends "res://addons/_lib/singleton/singleton_ref_count.gd" #! ext Singletons.RefCount

const CacheHelper = UtilR.Files.CacheHelper
const UTree = UtilR.Nodes.Trees.UTree
const UNode = UtilR.UNode
const UFile = UtilR.Files.UFile
const UVersion = UtilR.UVersion
const UClassDetail = UtilR.Objects.UClassDetail
const FileSystem = EditorNodeRef.Refs.FileSystem

const ScenePreview = preload("res://addons/_lib/brohd/preview_gen/scene_preview/scene_preview.gd")

const FileTypes = preload("res://addons/_lib/editor_filesystem/src/util/file_types.gd")
const FSTooltip = preload("res://addons/_lib/editor_filesystem/src/util/fs_tooltip.gd")
const FSRename = preload("res://addons/_lib/editor_filesystem/src/util/fs_rename.gd")
const FSGenericPopupHandler = preload("res://addons/_lib/editor_filesystem/src/util/fs_generic_popup_handler.gd")

const PE_STRIP_CAST_SCRIPT = preload("res://addons/_lib/editor_filesystem/src/filesystem_singleton.gd")

static func get_singleton_name() -> String:
	return "FileSystemSingleton"

static func get_instance() -> FileSystemSingleton:
	return _get_instance(PE_STRIP_CAST_SCRIPT)

static func instance_valid() -> bool:
	return _instance_valid(PE_STRIP_CAST_SCRIPT)

static func register_node(node:Node):
	return _register_node(PE_STRIP_CAST_SCRIPT, node)

static func unregister_node(node):
	_unregister_node(PE_STRIP_CAST_SCRIPT, node)

static func call_on_ready(callable, print_err:bool=true):
	_call_on_ready(PE_STRIP_CAST_SCRIPT, callable, print_err)

static func clear_caches():
	get_instance().clear_all_caches()

static var editor_fs:EditorFileSystem

var editor_node_ref:EditorNodeRef
var popup_handler:FSGenericPopupHandler

var cache:Cache

var file_system_dock_favorites_dict:Dictionary = {}
var file_system_dock_item_dict:Dictionary = {}

var file_paths:= PackedStringArray()
var file_and_dir_paths:= PackedStringArray()

var _file_paths_dict:= {}
var _file_and_dir_paths_dict:={}

var editor_base_control:Control
var editor_resource_preview:EditorResourcePreview

var _preview_gen_started:=false
var _previews_generated:=false #^ need a flag to retrigger when all are built after initial build
var _preview_balance:=0
var _init_complete:=false

var _scene_preview:ScenePreview

signal filesystem_changed
signal filesystem_paths_changed(changed:bool)

func _init(_node):
	cache = Cache.new()

func _ready() -> void:
	#editor_node_ref = EditorNodeRef.get_instance()
	#EditorNodeRef.call_on_ready(_register_dialogs)
	editor_fs = EditorInterface.get_resource_filesystem()
	while editor_fs.is_scanning():
		await get_tree().process_frame
	
	editor_node_ref = EditorNodeRef.get_instance()
	EditorNodeRef.call_on_ready(_on_editor_node_ref_ready)


func _on_editor_node_ref_ready():
	editor_fs.filesystem_changed.connect(_on_filesystem_changed, 1)
	EditorInterface.get_resource_previewer().preview_invalidated.connect(func(path):queue_preview(path))
	
	_register_dialogs()
	
	_scene_preview = ScenePreview.new()
	add_child(_scene_preview)
	_scene_preview.queue_processed.connect(_scene_preview_queue_processed)
	
	get_filesystem_favorites()
	#get_filesystem_folder_colors()
	
	_set_interface_refs()
	cache.set_editor_icons()
	rebuild_files()
	
	_generate_previews() # init set in here so all previews generated at start
	_init_complete = true



func _get_ready_bool():
	return _init_complete

func _generate_previews():
	if _preview_gen_started:
		return
	_preview_gen_started = true
	for path:String in file_paths:
		_preview_balance += 1
		queue_preview(path)
	
	while _preview_balance > 0:
		await get_tree().process_frame
	_previews_generated = true
	filesystem_paths_changed.emit(false)

func _set_interface_refs():
	cache.set_folder_icon()
	editor_fs = EditorInterface.get_resource_filesystem()
	editor_base_control = EditorInterface.get_base_control()
	editor_resource_preview = EditorInterface.get_resource_previewer()
	
	cache.folder_colors_raw = get_filesystem_folder_colors()



func rebuild_files():
	_on_filesystem_changed()

func clear_all_caches():
	file_paths.clear()
	_file_paths_dict.clear()
	file_and_dir_paths.clear()
	_file_and_dir_paths_dict.clear()
	file_system_dock_favorites_dict.clear()
	file_system_dock_item_dict.clear()
	
	cache.clear()
	cache.set_editor_icons()
	
	_preview_gen_started = false # trigger a build if needed
	_previews_generated = false
	_preview_balance = 0

func _on_filesystem_changed():
	if not is_instance_valid(editor_fs):
		editor_fs = EditorInterface.get_resource_filesystem()
	while editor_fs.is_scanning():
		await get_tree().process_frame
	
	_set_interface_refs()
	
	_file_paths_dict.clear()
	_file_and_dir_paths_dict.clear()
	
	_file_scan()
	#ALibRuntime.Utils.UProfile.TimeFunction.time_func(_file_scan, "FS SCAN")
	
	var new_paths = PackedStringArray(_file_and_dir_paths_dict.keys())
	var paths_changed = new_paths != file_and_dir_paths
	file_and_dir_paths = new_paths
	file_paths = PackedStringArray(_file_paths_dict.keys())
	
	
	if not _previews_generated:
		_generate_previews()
	
	filesystem_changed.emit() # own signal
	filesystem_paths_changed.emit(paths_changed)



func _file_scan():
	if get_fs_dock_split_mode() != 0:
		_singleton_build_fs_item_dict()
		_singleton_scan_for_files()
	else:
		_singleton_scan_tree_for_paths()



func _singleton_scan_for_files():
	_singleton_recursive_scan_for_files("res://")

func _singleton_recursive_scan_for_files(dir:String) -> void:
	_file_and_dir_paths_dict[dir] = true
	
	var fs_dir:EditorFileSystemDirectory = editor_fs.get_filesystem_path(dir)
	for i in fs_dir.get_subdir_count():
		var sub_dir = fs_dir.get_subdir(i)
		var path = sub_dir.get_path()
		_singleton_recursive_scan_for_files(path)
	
	for i in fs_dir.get_file_count():
		var path = fs_dir.get_file_path(i)
		#get_file_data(path)
		_file_paths_dict[path] = true
		_file_and_dir_paths_dict[path] = true


func _singleton_scan_tree_for_paths():
	var fs_tree: Tree = EditorNodeRef.get_registered(EditorNodeRef.Nodes.FILESYSTEM_TREE)
	if not fs_tree:
		printerr("FileSystemDock Tree not found.")
		return
	var root: TreeItem = fs_tree.get_root()
	if not root:
		printerr("FileSystemDock Tree has no root item.")
		return
	
	for child:TreeItem in root.get_children():
		if child.get_text(0) == get_favorites_text():
			for item in child.get_children():
				var path = item.get_metadata(0)
				file_system_dock_favorites_dict[path] = item
		elif child.get_text(0) == "res://":
			_singleton_recursive_scan_tree_for_paths(child)

func _singleton_recursive_scan_tree_for_paths(item: TreeItem):
	if item == null:
		return
	var file_path = item.get_metadata(0)
	if file_path == null:
		printerr("NO TREE META", item.get_text(0))
		return
	file_system_dock_item_dict[file_path] = item
	if not file_path.ends_with("/"):
		_file_paths_dict[file_path] = true
	_file_and_dir_paths_dict[file_path] = true
	
	var child: TreeItem = item.get_first_child()
	while child != null:
		_singleton_recursive_scan_tree_for_paths(child)
		child = child.get_next() # Move to the next sibling

func _singleton_build_fs_item_dict():
	var fs_tree: Tree = EditorNodeRef.get_registered(EditorNodeRef.Nodes.FILESYSTEM_TREE)
	if not fs_tree:
		printerr("FileSystemDock Tree not found.")
		return
	var root: TreeItem = fs_tree.get_root()
	if not root:
		printerr("FileSystemDock Tree has no root item.")
		return
	
	for child:TreeItem in root.get_children():
		if child.get_text(0) == get_favorites_text():
			for item in child.get_children():
				var path = item.get_metadata(0)
				file_system_dock_favorites_dict[path] = item
		elif child.get_text(0) == "res://":
			_singleton_recursive_build_fs_item_dict(child)

func _singleton_recursive_build_fs_item_dict(item: TreeItem):
	if item == null:
		return
	var file_path = item.get_metadata(0)
	if file_path == null:
		printerr("NO TREE META", item.get_text(0))
		return
	file_system_dock_item_dict[file_path] = item
	var child: TreeItem = item.get_first_child()
	while child != null:
		_singleton_recursive_build_fs_item_dict(child)
		child = child.get_next() # Move to the next sibling

static func recursive_scan_tree_for_paths(item: TreeItem, include_dirs:bool=false) -> PackedStringArray:
	var path_array:= PackedStringArray()
	if item == null:
		return path_array
	var file_path = item.get_metadata(0)
	if file_path.ends_with("/"):
		if include_dirs:
			path_array.append(file_path)
	else:
		path_array.append(file_path)
	
	var child: TreeItem = item.get_first_child()
	while child != null:
		path_array.append_array(recursive_scan_tree_for_paths(child, include_dirs))
		child = child.get_next() # Move to the next sibling
	
	return path_array

static func recursive_scan_for_file_paths(dir:String, include_dirs:bool=false) -> PackedStringArray:
	var files = PackedStringArray()
	if include_dirs:
		files.append(dir)
	
	var fs_dir:EditorFileSystemDirectory = editor_fs.get_filesystem_path(dir)
	if not fs_dir:
		return files
	for i in fs_dir.get_subdir_count():
		var sub_dir = fs_dir.get_subdir(i)
		files.append_array(recursive_scan_for_file_paths(sub_dir.get_path(), include_dirs))
	
	for i in fs_dir.get_file_count():
		files.append(fs_dir.get_file_path(i))
	return files

static func is_path_valid(path:String):
	if instance_valid():
		return get_instance()._file_and_dir_paths_dict.has(path)
	return false

func get_file_data(path:String):
	var cached = CacheHelper.get_cached_data(path, cache.file_data)
	if cached:
		return cached
	
	var file_type = get_file_type(path)
	var icon = _get_type_icon(path)
	
	if file_type == "PackedScene":
		_scene_preview.get_path_hash(path)
	
	if file_type == "":
		file_type = FileData.FOLDER
	
	var _file_data = {
		FileData.PATH: path,
		FileData.TYPE_ICON: icon,
		FileData.TYPE: file_type,
		FileData.CUSTOM_ICON: false,
	}
	
	CacheHelper.store_data(path, _file_data, cache.file_data, [path])
		
	return _file_data

static func get_file_type_static(path:String):
	if instance_valid():
		return get_instance().get_file_type(path)
	return {}


func get_file_type(path:String):
	var cached = CacheHelper.get_cached_data(path, cache.file_types)
	if cached != null:
		return cached
	#if _file_types.has(path):
		#return _file_types[path]
	var file_type = editor_fs.get_file_type(path)
	#_file_types[path] = file_type
	CacheHelper.store_data(path, file_type, cache.file_types, [path])
	return file_type



func get_type_icon(file_path:String):
	var data = get_file_data(file_path)
	if data == null:
		return _get_type_icon(file_path)
	return data.get(FileData.TYPE_ICON)

func _get_type_icon(file_path):
	#if file_system_dock_item_dict.has(file_path):
		#var item = file_system_dock_item_dict.get(file_path)
		#if item:
			#return item.get_icon(0)
	if file_path.ends_with("/"):
		return get_folder_icon()
	var file_type = get_file_type(file_path)
	if cache.editor_icons.has(file_type):
		return cache.editor_icons[file_type]
	if Keys.VALID_FILE_TYPES.has(file_type):
		return cache.editor_icons[Keys.VALID_FILE_TYPES.get(file_type)]
	var fs_dir = EditorInterface.get_resource_filesystem().get_filesystem_path(file_path.get_base_dir())
	if fs_dir == null:
		return EditorInterface.get_editor_theme().get_icon(&"FileBroken", &"EditorIcons")
	var idx = fs_dir.find_file_index(file_path.get_file())
	if idx > -1:
		if fs_dir.get_file_import_is_valid(idx):
			return cache.file_icon
	return EditorInterface.get_editor_theme().get_icon(&"FileBroken", &"EditorIcons")

static func get_preview(path:String):
	if instance_valid():
		return get_instance()._get_preview(path)

func _get_preview(path:String):
	var cached_preview = CacheHelper.get_cached_data(path, cache.resource_previews)
	if cached_preview != null:
		return cached_preview
	if _scene_preview.hash_cache.has(path):
		var _hash = _scene_preview.hash_cache[path]
		var preview_data = _scene_preview.cache.get(_hash)
		if preview_data != null:
			var preview = preview_data.get(ScenePreview.PREVIEW)
			var preview_path = preview_data.get(ScenePreview.PREVIEW_PATH)
			CacheHelper.store_data(path, preview_data, cache.resource_previews, [preview_path])
			return preview
		return
	queue_preview(path)

func queue_preview(path:String):
	editor_resource_preview.queue_resource_preview(path, self, &"_get_resource_preview", null)

func _get_resource_preview(path, preview, thumbnail, _user_data):
	if not _previews_generated:
		_preview_balance -= 1
	if preview == null:
		return
	
	var data = {
		FileData.Preview.PREVIEW: preview,
		FileData.Preview.THUMBNAIL: thumbnail
	}
	CacheHelper.store_data(path, data, cache.resource_previews, [path])

static func clear_scene_preview_cache():
	get_instance()._scene_preview.clear_texture_cache()

static func generate_all_scene_previews():
	get_instance()._generate_all_scene_previews()

func _generate_all_scene_previews():
	var scn_files = get_paths_of_type(["PackedScene"])
	_generate_scene_previews(scn_files)

static func generate_scene_previews(paths:PackedStringArray):
	get_instance()._generate_scene_previews(paths)

func _generate_scene_previews(paths:PackedStringArray):
	_scene_preview.preview_size = 128
	_scene_preview.queue_paths(paths)

func _scene_preview_queue_processed():
	_scene_preview.threaded_load_cache()
	await _scene_preview.cache_loaded
	rebuild_files()

func get_paths_of_ext(ext_array:=[]):
	var valid = []
	for path in _file_paths_dict.keys():
		if path.get_extension() in ext_array:
			valid.append(path)
	return valid

func get_paths_of_type(type_array:=[]):
	var valid = []
	for path in _file_paths_dict.keys():
		if get_file_type(path) in type_array:
			valid.append(path)
	return valid
	

func get_folder_icon():
	return cache.folder_icon

static func get_favorites_icon():
	return EditorInterface.get_base_control().get_theme_icon("Favorites", "EditorIcons")

static func get_favorites_text():
	return "Favorites:"

func get_icon_color(file_path:String):
	if file_system_dock_item_dict.has(file_path):
		var item = file_system_dock_item_dict.get(file_path)
		if is_instance_valid(item):
			return item.get_icon_modulate(0)
	if file_path.ends_with("/"):
		return get_folder_color(file_path)
	#var file_type = _get_file_type(file_path)
	#return editor_base_control.get_theme_icon(file_type, &"EditorIcons")
	return Color.WHITE


func get_background_color(file_path:String):
	if cache.folder_color_path_cache.has(file_path):
		return cache.folder_color_path_cache[file_path]
	if file_system_dock_item_dict.has(file_path):
		var item = file_system_dock_item_dict.get(file_path)
		if is_instance_valid(item):
			var item_color = item.get_custom_bg_color(0)
			cache.folder_color_path_cache[file_path] = item_color
			return item_color
	
	if cache.folder_colors_raw.has(file_path):
		var cached_color = Keys.FOLDER_COLORS_DICT.get(cache.folder_colors_raw.get(file_path))
		cached_color.a = 0.1
		cache.folder_color_path_cache[file_path] = cached_color
		return cached_color
	var color = get_folder_color(file_path)
	if color != cache.folder_color:
		color *= 0.7
		color.a = 0.1
		cache.folder_color_path_cache[file_path] = color
		return color


func get_folder_color(file_path:String=""):
	if file_path == "":
		return cache.folder_color
	var color = ""
	var working_path = file_path
	while true:
		var check_path = working_path
		if not check_path.ends_with("/"):
			check_path = check_path + "/"
		
		if cache.folder_colors_raw.has(check_path):
			color = cache.folder_colors_raw.get(check_path)
			break
		
		if working_path == "res://":
			break
		var old_path = working_path
		working_path = working_path.get_base_dir()
		if working_path == old_path:
			break # fail-safe: if get_base_dir() returns the same path, break
	  
	return Keys.FOLDER_COLORS_DICT.get(color, cache.folder_color)

## Recursive get files in directory.
func get_files_in_dir(dir:String, include_dirs:bool=false):
	#^ alternate method, quicker on large array, slower on small
	#if not dir.ends_with("/"):
		#dir += "/"
	#var p_arr = file_and_dir_paths if include_dirs else file_paths
	#var valid = []
	#for p in p_arr:
		#if p.begins_with(dir):
			#valid.append(p)
	
	var first_item = file_system_dock_item_dict.get(dir)
	if get_fs_dock_split_mode() != 0 or first_item == null:
		return recursive_scan_for_file_paths(dir, include_dirs)
	else:
		return recursive_scan_tree_for_paths(first_item, include_dirs)

static func get_dir_contents(dir:String):
	var files = PackedStringArray()
	var fs_dir:EditorFileSystemDirectory = editor_fs.get_filesystem_path(dir)
	if not fs_dir:
		return files
	for i in fs_dir.get_subdir_count():
		var sub_dir = fs_dir.get_subdir(i)
		files.append(sub_dir.get_path())
	
	for i in fs_dir.get_file_count():
		files.append(fs_dir.get_file_path(i))
	return files
	

static func get_filesystem_folder_colors():
	var data_cache:Dictionary
	if FileSystemSingleton.instance_valid():
		data_cache = FileSystemSingleton.get_instance().cache.data_cache
		var cached = CacheHelper.get_cached_data(Keys.FOLDER_COLORS, data_cache)
		if cached != null:
			return cached
	
	var config = ConfigFile.new()
	var err = config.load(FilePaths.PROJECT)
	if err != OK:
		printerr("Could not get project file: Error %s" % err)
		return
	var folder_colors = config.get_value("file_customization", "folder_colors", {})
	if FileSystemSingleton.instance_valid():
		FileSystemSingleton.get_instance().cache.folder_color_path_cache.clear()
		CacheHelper.store_data(Keys.FOLDER_COLORS, folder_colors, data_cache, [FilePaths.PROJECT])
	return folder_colors

static func get_filesystem_favorites():
	var data_cache:Dictionary
	if FileSystemSingleton.instance_valid():
		data_cache = FileSystemSingleton.get_instance().cache.data_cache
		var cached = CacheHelper.get_cached_data(Keys.FAVORITES, data_cache)
		if cached != null:
			return cached
	
	if FileAccess.file_exists(FilePaths.FAVORITES):
		var file_as_string = FileAccess.get_file_as_string(FilePaths.FAVORITES)
		var favorites_array = file_as_string.split("\n", false)
		if FileSystemSingleton.instance_valid():
			CacheHelper.store_data(Keys.FAVORITES, favorites_array, data_cache, [FilePaths.FAVORITES])
		return favorites_array
	else:
		#printerr("Could not get favorites file.")
		return []


static func activate_path(path:String):
	var sel = ensure_items_selected([path])
	if sel:
		activate_in_fs()

static func activate_in_fs():
	var fs_tree = get_filesystem_tree() as Tree
	fs_tree.item_activated.emit()

static func ensure_items_selected(path_array:Array):
	var instance = get_instance()
	var selected_in_fs = instance.select_items_in_fs(path_array)
	if not selected_in_fs:
		instance.rebuild_files()
		selected_in_fs = instance.select_items_in_fs(path_array)
		if not selected_in_fs:
			print("Could not select the items in FileSystem")
		return selected_in_fs
	else:
		return true

func select_items_in_fs(selected_item_paths:Array, navigate=false) -> bool:
	var sel_paths_reversed = selected_item_paths.duplicate()
	var fs_tree = get_filesystem_tree()
	sel_paths_reversed.reverse()
	if sel_paths_reversed.size() > 0:
		var fs_item = fs_tree.get_selected()
		fs_tree.multi_selected.emit(fs_item, 0, true)
	
	if navigate and sel_paths_reversed.size() > 0:
		EditorInterface.get_file_system_dock().navigate_to_path(sel_paths_reversed[0])
	
	fs_tree.deselect_all()
	var items = []
	
	for path:String in sel_paths_reversed:
		var fs_item = file_system_dock_item_dict.get(path)
		if is_instance_valid(fs_item):
			items.append(fs_item)
			fs_item.select(0)
		else:
			return false
	
	if fs_tree.visible:
		fs_tree.queue_redraw()
	return true

static func show_right_click_menu(clicked:Node, selected:String, selected_paths:Array, to_hide:=FSGenericPopupHandler.HIDE_HANDLED_ID):
	var ins = get_instance()
	if not is_instance_valid(ins):
		printerr("right_click_menu - Could not get FileSystem instance.")
		return
	ins.right_click_menu(clicked, selected, selected_paths, to_hide)


func right_click_menu(clicked:Node, selected:String, selected_paths:Array, to_hide:=FSGenericPopupHandler.HIDE_HANDLED_ID):
	var did_select = ensure_items_selected(selected_paths)
	if not did_select:
		printerr("right_click_menu -  Could not select paths: ", selected_paths)
		return
	if not is_instance_valid(popup_handler):
		popup_handler = FSGenericPopupHandler.new()
	popup_handler.right_clicked(clicked, selected, selected_paths, to_hide)

func _register_dialogs():
	var fs_dock = EditorInterface.get_file_system_dock()
	var dialog_nodes = []
	var move_dialog
	for n in fs_dock.get_children():
		var _class = n.get_class()
		if _class in Keys.DIALOGS_TO_MOVE:
			dialog_nodes.append(n)
		if _class == Keys.EDITOR_DIR_DIALOG:
			move_dialog = n
	
	EditorNodeRef.register(Keys.FS_DIALOGS, dialog_nodes)
	move_dialog.about_to_popup.connect(_move_dialog_create_file_list)

static func get_dialogs():
	return EditorNodeRef.get_registered(Keys.FS_DIALOGS)

static func move_dialogs(new_parent, connect_vis_signal:=true):
	var window_checked = false
	var dialog_nodes = EditorNodeRef.get_registered(Keys.FS_DIALOGS)
	for dialog in dialog_nodes:
		if not window_checked:
			window_checked = true
			if dialog.get_parent().get_window() == new_parent.get_window():
				return
		new_parent = new_parent.get_window().get_child(0) # TEST
		if dialog.get_parent() != new_parent:
			dialog.reparent(new_parent)
		
		if connect_vis_signal:
			if not dialog.visibility_changed.is_connected(_on_dialog_visibility_changed):
				dialog.visibility_changed.connect(_on_dialog_visibility_changed.bind(dialog))

static func _on_dialog_visibility_changed(dialog_changed:Window):
	if dialog_changed.visible == false:
		var dialog_nodes = EditorNodeRef.get_registered(Keys.FS_DIALOGS)
		for dialog:Window in dialog_nodes:
			if dialog.visibility_changed.is_connected(_on_dialog_visibility_changed):
				dialog.visibility_changed.disconnect(_on_dialog_visibility_changed)
		reset_dialogs()

static func reset_dialogs(parent=null, _mouse=null):
	var dialog_nodes = EditorNodeRef.get_registered(Keys.FS_DIALOGS)
	var first_dialog = dialog_nodes[0]
	if not is_instance_valid(first_dialog):
		printerr("FileSystem Dialogs have been freed likely by FileSystem Instances plugin. Save your work and restart the editor.")
		printerr("Apologies, this is a bug that should not happen.")
		return
	if first_dialog.get_parent() == EditorInterface.get_file_system_dock():
		return
	if is_instance_valid(parent) and parent is Node:
		if first_dialog.get_window() != parent.get_window():
			return
	for dialog:Window in dialog_nodes:
		dialog.reparent(EditorInterface.get_file_system_dock())
		dialog.cancel_free()

static func _get_move_dialog() -> Window:
	var dialogs = FileSystemSingleton.get_dialogs()
	var move_dialog:Window
	for dialog:Window in dialogs:
		if dialog.get_class() == Keys.EDITOR_DIR_DIALOG:
			move_dialog = dialog
			break
	return move_dialog

static func show_file_move_dialog(target_dir:=""):
	var file_system_popup = EditorNodeRef.get_registered(EditorNodeRef.Nodes.FILESYSTEM_POPUP)
	file_system_popup.id_pressed.emit(9)
	var move_dialog:Window = _get_move_dialog()
	
	var nodes = move_dialog.find_children("*", "Tree", true, false)
	var dialog_tree = nodes[0] as Tree
	var root = dialog_tree.get_root()
	if root == null:
		return
	var paths = EditorInterface.get_selected_paths()
	if paths.is_empty():
		return
	var first_sel = paths[0]
	if first_sel.get_extension() != "":
		first_sel = first_sel.get_base_dir()
	if target_dir != "":
		first_sel = target_dir
	if not first_sel.ends_with("/"):
		first_sel = first_sel + "/"
	
	var item = UTree.find_item_by_meta(root, first_sel)
	if item:
		root.set_collapsed_recursive(true)
		if first_sel == "res://":
			root.collapsed = false
		var par = item.get_parent()
		while par != null:
			par.collapsed = false
			par = par.get_parent()
	else:
		return
	
	dialog_tree.deselect_all()
	item.select(0)
	dialog_tree.scroll_to_item(item, true)
	dialog_tree.queue_redraw()

static func _move_dialog_create_file_list():
	var move_dialog:Window = _get_move_dialog()
	var nodes = move_dialog.find_children("*", "Tree", true, false)
	var dialog_tree = nodes[0] as Tree
	var paths = EditorInterface.get_selected_paths()
	
	var file_list_root = VBoxContainer.new()
	dialog_tree.get_parent().add_child(file_list_root)
	#file_list_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_list_root.custom_minimum_size = Vector2(0, 100) * EditorInterface.get_editor_scale()
	var title_bar = HBoxContainer.new()
	file_list_root.add_child(title_bar)
	title_bar.add_spacer(true)
	var title_button = Button.new()
	title_button.text = "Files to Move/Copy"
	title_button.flat = true
	title_button.focus_mode = Control.FOCUS_NONE
	
	var callable = func():
		if file_list_root.size_flags_vertical == Control.SIZE_EXPAND_FILL:
			file_list_root.size_flags_vertical = Control.SIZE_FILL
		else:
			file_list_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	title_button.pressed.connect(callable)
	title_bar.add_child(title_button)
	title_bar.add_spacer(false)
	
	var file_list = ItemList.new()
	file_list_root.add_child(file_list)
	file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for path in paths:
		file_list.add_item(path)
	
	move_dialog.visibility_changed.connect(_free_move_dialog_file_list.bind(move_dialog, file_list_root))


static func _free_move_dialog_file_list(move_dialog:Window, control:Control):
	if not move_dialog.visible:
		control.queue_free()
		if move_dialog.visibility_changed.is_connected(_free_move_dialog_file_list):
			move_dialog.visibility_changed.disconnect(_free_move_dialog_file_list)


static func populate_filesystem_popup(calling_node:Node):
	FileSystem.populate_popup(calling_node)

static func popuplate_filesystem_bottom_popup(calling_node:Node):
	FileSystem.populate_bottom_popup(calling_node)

static func get_filesystem_tree() -> Tree:
	return FileSystem.get_tree()

static func show_filesystem():
	_toggle_fs_bottom_panel_button_vis(true)

static func hide_filesystem():
	if not fs_dock_in_bottom_panel():
		print("Can only hide dock in bottom panel.")
		return
	
	var fs = EditorInterface.get_file_system_dock()
	var split_button = fs.get_child(0).get_child(0).get_child(3)
	var split_callable = UNode.get_signal_callable(split_button,
		"pressed", "FileSystemDock::_change_split_mode")
	if not split_callable:
		print("Could not get split mode button.")
		return
	
	for i in range(3):
		if get_fs_dock_split_mode() != 0:
			split_callable.call()
		else:
			break
	
	_toggle_fs_bottom_panel_button_vis(false)
	

static func _toggle_fs_bottom_panel_button_vis(toggled:bool):
	var minor = UVersion.get_minor_version()
	if minor < 6:
		var bottom_panel_buttons = EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.BOTTOM_PANEL_BUTTONS)
		for b in bottom_panel_buttons.get_children():
			if b.text == "FileSystem":
				b.toggled.emit(false)
				b.visible = toggled
				break

## 0=None, 1=Vertical, 2=Horizontal, -1=Err
static func get_fs_dock_split_mode():
	var tree = EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.FILESYSTEM_TREE)
	if not tree:
		return -1
	var search_node = tree
	var minor_version = UVersion.get_minor_version()
	if minor_version >= 6:
		search_node = search_node.get_parent()
	var item_list = search_node.get_parent().get_child(1)
	if not item_list.visible:
		return 0
	var split = search_node.get_parent() as SplitContainer
	if split.vertical:
		return 1
	return 2

static func fs_dock_in_bottom_panel() -> bool:
	var fs_dock = EditorInterface.get_file_system_dock()
	var minor_version = UVersion.get_minor_version()
	if minor_version <= 5: # versions will need testing
		var dock_par = fs_dock.get_parent()
		if dock_par is TabContainer:
			return false
		dock_par = dock_par.get_parent()
		return dock_par.get_class() == Keys.EDITOR_BOTTOM_PANEL
	else: #elif minor_version <= 7:
		var dock_par = fs_dock.get_parent()
		return dock_par.get_class() == Keys.EDITOR_BOTTOM_PANEL
	return false

## Takes a file path, and the new name of the file. New name is not entire path.
static func rename_path(old_path:String, new_path:String):
	await FSRename.rename_path(old_path, new_path)

static func is_new_name_valid(original_file_name:String, new_file_name:String) -> bool:
	return FSRename.is_new_name_valid(original_file_name, new_file_name)

static func fs_navigate_to_path(path:String, activate_rename:=false):
	FSRename.show_item_in_dock(path, activate_rename)


static func navigate_to_path(path:String, calling_node:Node):
	var sibling_filesystem = get_sibling_filesystem(calling_node)
	if not is_instance_valid(sibling_filesystem):
		EditorInterface.get_file_system_dock().navigate_to_path(path)
		return
	sibling_filesystem.navigate_to_path(path)

static func get_sibling_filesystem(calling_node:Node):
	var editor_panel_singleton = UClassDetail.get_global_class_script("EditorPanelSingleton")
	if not is_instance_valid(editor_panel_singleton):
		return
	var split_panel = editor_panel_singleton.get_split_panel_ancestor(calling_node)
	if not is_instance_valid(split_panel):
		return
	for panel in split_panel.get_panels():
		var content = panel.get_control()
		if content.has_method("get_all_tab_controls"):
			for tab in content.get_all_tab_controls():
				var script = tab.get_script()
				if script and script.resource_path.get_file() == "filesystem_tab.gd":
					return tab

static func get_custom_tooltip(path:String):
	return FSTooltip.get_custom_tooltip(path)

static func get_thumbnail_size():
	return Vector2(64, 64) * EditorInterface.get_editor_scale()

static func get_drag_preview(paths:Array):
	var ins = get_instance()
	var file_icon = ins.cache.file_icon
	var folder_icon = ins.cache.folder_icon
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 0)
	var path_size = paths.size()
	var to_list = 6 if path_size < 7 else 5
	for i in range(to_list):
		if i >= path_size:
			break
		var path = paths[i]
		var hbox = HBoxContainer.new()
		var icon = folder_icon if path.ends_with("/") else file_icon
		var _name = path.trim_suffix("/").get_file()
		var texture = TextureRect.new()
		texture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		texture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		texture.texture = icon
		var lab = Label.new()
		lab.text = _name
		hbox.add_child(texture)
		hbox.add_child(lab)
		container.add_child(hbox)
	if path_size > to_list:
		var leftover = path_size - to_list
		var lab = Label.new()
		lab.text = "%s more files" % leftover
		container.add_child(lab)
	
	return container


static func is_path_valid_res(path:String) -> bool:
	if not path.begins_with("res://"):
		return false
	return is_path_valid(path)

static func is_root_folder(path:String):
	if path.ends_with("://") or path == "/":
		return true
	return false

static func paths_have_same_root(path:String, path_2:String):
	if path.begins_with("res://"):
		if path_2.begins_with("res://"):
			return true
		return false
	elif path.begins_with("user://"):
		if path_2.begins_with("user://"):
			return true
		return false
	elif path.begins_with("/"):
		if path_2.begins_with("/"):
			return true
		return false


func _all_unregistered_callback():
	var move_dialog = _get_move_dialog()
	if move_dialog.about_to_popup.is_connected(_move_dialog_create_file_list):
		move_dialog.about_to_popup.disconnect(_move_dialog_create_file_list)

class Cache:
	var data_cache:= {}
	var folder_colors_raw:= {}
	var folder_color_path_cache:= {}
	var file_types:= {}
	var file_data:={}
	var resource_previews:={}
	
	var file_icon:Texture2D
	var folder_icon:Texture2D
	var folder_color:Color
	
	var editor_icons:= {}
	
	func clear():
		data_cache.clear()
		folder_colors_raw.clear()
		folder_color_path_cache.clear()
		file_types.clear()
		file_data.clear()
		
		set_folder_icon()
	
	func set_folder_icon():
		file_icon = EditorInterface.get_base_control().get_theme_icon("File", &"EditorIcons")
		folder_icon = EditorInterface.get_base_control().get_theme_icon("Folder", &"EditorIcons")
		folder_color = EditorInterface.get_base_control().get_theme_color("folder_icon_color", "FileDialog")
	
	func set_editor_icons():
		editor_icons = {}
		var editor_theme = EditorInterface.get_editor_theme()
		for _name in editor_theme.get_icon_list(&"EditorIcons"):
			editor_icons[_name] = editor_theme.get_icon(_name, &"EditorIcons")

class FilePaths:
	const PROJECT = "res://project.godot"
	const FAVORITES = "res://.godot/editor/favorites"

class Keys:
	const EDITOR_BOTTOM_PANEL = "EditorBottomPanel"
	const EDITOR_DIR_DIALOG = "EditorDirDialog"
	
	const FOLDER_COLORS = &"FolderColors"
	const FAVORITES = &"FileSystemFavorites"
	
	const FOLDER_COLORS_DICT = {
		"red":Color(1.0, 0.271, 0.271),
		"orange":Color(1.0, 0.561, 0.271),
		"yellow":Color(1.0, 0.890, 0.271),
		"green":Color(0.502, 1.0, 0.271),
		"teal":Color(0.271, 1.0, 0.635),
		"blue":Color(0.271, 0.843, 1.0),
		"purple":Color(0.502, 0.271, 1.0),
		"pink":Color(1.0, 0.271, 0.588),
		"gray":Color(0.616, 0.616, 0.616),
	}
	
	const FS_DIALOGS = "FS_DIALOGS"
	const DIALOGS_TO_MOVE = [ "ScriptCreateDialog", "DependencyEditor", "DependencyRemoveDialog", "ConfirmationDialog", "EditorDirDialog",
	"SceneCreateDialog","ShaderCreateDialog","DependencyEditorOwners","DirectoryCreateDialog","CreateDialog"]
	
	const VALID_FILE_TYPES = {
		"Resource":"Object", # this is actually file in the normal tree
		"Texture": "CompressedTexture2D"
		#"JSON":true,
	}


class FileData:
	const FOLDER = &"Folder"
	const PATH = &"item_path"
	const TYPE_ICON = &"file_type_icon"
	const TYPE = &"file_type"
	const CUSTOM_ICON = &"file_custom_icon"
	
	const FAVORITES_META = "FAVORITES"
	
	class Preview:
		const PREVIEW = &"preview"
		const THUMBNAIL = &"thumbnail"

class GetDropData:
	static func files(selected_item_paths:Array, from_node:Control, remove_invalid:=true) -> Variant:
		if remove_invalid:
			selected_item_paths.erase("res://")
			selected_item_paths.erase(FileData.FAVORITES_META)
		if selected_item_paths.is_empty():
			return
		
		from_node.set_drag_preview(FileSystemSingleton.get_drag_preview(selected_item_paths))
		#return UTree.get_drop_data.files(selected_item_paths, from_node)
		var data_type:String = "files"
		var selected_paths:Array = []
		for path in selected_item_paths:
			if path.ends_with("/"):
				data_type = "files_and_dirs"
				selected_paths.append(path)
			else:
				selected_paths.append(path)
		var data:Dictionary = {"type": data_type, "files": selected_paths, "from": from_node}
		
		return data

class CanDropData:
	static func files(at_position: Vector2, data: Variant, extensions:Array=[]) -> bool:
		return UTree.CanDropData.files(at_position, data, extensions)

class DropData:
	static func move_dialog(data, target_dir, calling_node):
		var files = []
		if data.has("files"):
			files = data.get("files")
		elif data.has("file_and_dirs"):
			files = data.get("file_and_dirs")
		
		for file:String in files:
			if file == target_dir:
				return
			if UFile.is_file_in_directory(target_dir, file):
				return
			var file_dir = file
			file_dir = file_dir.trim_suffix("/")
			file_dir = file_dir.get_base_dir()
			if not file_dir.ends_with("/"):
				file_dir += "/"
			if file_dir == target_dir:
				return
		
		calling_node.get_window().gui_cancel_drag()
		
		var selected = FileSystemSingleton.ensure_items_selected(files)
		if not selected:
			return
		
		calling_node.get_window().grab_focus()
		FileSystemSingleton.move_dialogs(calling_node)
		FileSystemSingleton.show_file_move_dialog(target_dir)
