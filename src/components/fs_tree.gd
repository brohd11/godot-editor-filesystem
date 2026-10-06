#! namespace EditorFS.Components class FSTree

extends VBoxContainer

const PopupHelper = UtilR.Nodes.Popups.PathHelper
const FSTreeHelperBase = preload("res://addons/_lib/editor_filesystem/src/util/fs_tree_helper_base.gd")
const FileData = preload("uid://fhnuvnmqrurq").FileData #! resolve FileSystemSingleton.FileData
const PopupID = preload("uid://co1fsmkihc4cg") #! resolve FileSystemSingleton.FSGenericPopupHandler.PopupID
const FSRenameContext = preload("res://addons/_lib/editor_filesystem/src/util/fs_rename_ctx.gd")
const TreeAltColor = preload("uid://bgfj0lf3e1btg") #! resolve UtilR.Nodes.Trees.AltLineColor

const SET_ROOT = "Set Root"
const RESET_ROOT = "Reset Root"

## Setting this object allows FSPopup methods to be called elsewhere.
var custom_popup_handler:Object

var filesystem_singleton:FileSystemSingleton
var fs_rename_ctx:FSRenameContext

var file_tree:Tree
var tree_helper:FSTreeHelper

var filter_hbox:HBoxContainer
var filter_line_edit:LineEdit
var last_filter_state:bool = false

var current_files:PackedStringArray = []

var root_dir:= "res://"
var _persistent_data:= {}

var file_extensions:= []

var multi_select:=true
var allow_root_pinning:=true
var show_favorites:=true
var show_empty_dirs:=true
var filter_full_path:=false
var draw_alternate_line_colors:=false

var _flat_view:=false


func _ready() -> void:
	
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	filter_hbox = HBoxContainer.new()
	add_child(filter_hbox)
	
	filter_line_edit = LineEdit.new()
	filter_hbox.add_child(filter_line_edit)
	filter_line_edit.text_changed.connect(_on_filter_line_text_changed)
	filter_line_edit.right_icon = EditorInterface.get_editor_theme().get_icon(&"Search", &"EditorIcons")
	filter_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_line_edit.clear_button_enabled = true
	filter_line_edit.placeholder_text = "Filter Files"
	
	file_tree = MinTree.new()
	file_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_tree.select_mode = Tree.SELECT_SINGLE
	file_tree.draw.connect(_on_file_tree_draw)
	
	file_tree.hide_root = true
	#file_tree.item_activated.connect(_on_item_activated)
	file_tree.set_drag_forwarding(
		_on_file_tree_get_drag_data,
		_on_file_tree_can_drop_data,
		_on_file_tree_drop_data,
		)
	add_child(file_tree)
	
	file_tree.allow_rmb_select = true
	file_tree.allow_reselect = true
	
	if multi_select:
		file_tree.select_mode = Tree.SELECT_MULTI
	else:
		file_tree.select_mode = Tree.SELECT_SINGLE
	
	filesystem_singleton = FileSystemSingleton.get_instance()
	
	tree_helper = FSTreeHelper.new(file_tree, null, null, null, false)
	tree_helper.filesystem_singleton = filesystem_singleton
	
	tree_helper.mouse_double_clicked.connect(_on_item_activated)
	tree_helper.mouse_left_clicked.connect(_on_item_left_clicked)
	tree_helper.mouse_right_clicked.connect(_on_item_right_clicked)
	
	fs_rename_ctx = FSRenameContext.new()
	fs_rename_ctx.set_file_tree(file_tree)
	
	EditorInterface.get_file_system_dock().folder_moved.connect(_on_fs_folder_moved)
	_set_persistent_on_ready()
	FileSystemSingleton.call_on_ready(_on_fs_ready)

func _on_fs_ready():
	filesystem_singleton.filesystem_paths_changed.connect(_on_file_system_changed, 1)
	_refresh_files_and_tree()
	
	_build_tree() # shouldn't be needed...



func set_persistent_data(data:Dictionary):
	_persistent_data = data
	
	root_dir = data.get(PersistentData.ROOT_DIR, "res://")
	_flat_view = data.get(PersistentData.FLAT_VIEW, _flat_view)
	file_extensions = data.get(PersistentData.EXTENSIONS, file_extensions)
	show_favorites = data.get(PersistentData.SHOW_FAVORITES, show_favorites)
	show_empty_dirs = data.get(PersistentData.SHOW_EMPTY_DIRS, show_empty_dirs)

func _set_persistent_on_ready():
	tree_helper.data_dict = _persistent_data.get(PersistentData.TREE_ITEM_META, {})
	_persistent_data.clear()

## Get persistent data for the tree
func get_persistent_data() -> Dictionary:
	var data = {
		PersistentData.ROOT_DIR: root_dir,
		PersistentData.FLAT_VIEW: _flat_view,
		PersistentData.EXTENSIONS: file_extensions,
		PersistentData.SHOW_FAVORITES: show_favorites,
		PersistentData.SHOW_EMPTY_DIRS: show_empty_dirs
	}
	var item_meta = {}
	for path in tree_helper.data_dict.keys():
		var path_data = tree_helper.data_dict.get(path)
		var collapsed = path_data.get(tree_helper.Keys.METADATA_COLLAPSED)
		if collapsed:
			continue
		item_meta[path] = {tree_helper.Keys.METADATA_COLLAPSED:false}
	
	#data[DataKeys.TREE_SCROLL_OFFSET] = tree.get_scroll()
	data[PersistentData.TREE_ITEM_META] = item_meta
	return data

func _set_flat_view(state:bool):
	_flat_view = state
	_build_tree()

func _set_show_favorites(state:bool):
	show_favorites = state
	_build_tree()

func _set_show_empty_dirs(state:bool):
	show_empty_dirs = state
	_refresh_files_and_tree()

func _set_filter_full_paths(state:bool):
	filter_full_path = state
	if _is_filtering():
		_update_tree_items()

func _set_alt_line_color(state:bool):
	draw_alternate_line_colors = state
	file_tree.queue_redraw()

func _on_file_tree_draw() -> void:
	if draw_alternate_line_colors:
		TreeAltColor.draw_lines(file_tree)

func _on_fs_folder_moved(old_path:String, new_path:String):
	var rename = FSTreeHelperBase.update_root(root_dir, old_path, new_path)
	if rename != "":
		root_dir = rename


func _on_file_system_changed(paths_changed:bool):
	if not paths_changed:
		_stagger_call(_refresh_tree)
	else:
		_stagger_call(_refresh_files_and_tree)

func _stagger_call(callable:Callable):
	if visible:
		callable.call()
		return
	for i in range(get_index() * 2):
		await get_tree().process_frame
	callable.call()

func refresh():
	_refresh_files_and_tree()

func _refresh_files_and_tree():
	_set_current_files()
	_build_tree()

func set_root_dir(root:String):
	_set_root(root)

func _set_current_files():
	var files := []
	if root_dir == "res://":
		if show_empty_dirs:
			files = filesystem_singleton.file_and_dir_paths.duplicate()
		else:
			files = filesystem_singleton.file_paths.duplicate()
	else:
		files = filesystem_singleton.get_files_in_dir(root_dir, show_empty_dirs)
	
	var no_exts = file_extensions.is_empty()
	current_files.clear()
	for path in files:
		if no_exts or (show_empty_dirs and path.ends_with("/")) or path.get_extension() in file_extensions:
			current_files.append(path)


func _build_tree():
	#var selected_paths = tree_helper.get_selected_paths().duplicate()
	var selected_paths = []
	var selected_items = tree_helper.get_selected_tree_items()
	for item:TreeItem in selected_items:
		var path = FSTreeHelper.get_path_from_item(item)
		if tree_helper.is_item_in_favorites(item):
			path = FSTreeHelper.get_favorite_key(path)
		selected_paths.append(path)
	
	# settings to impl
	var show_files = true
	var show_item_preview = true
	
	#tree_helper.show_files = show_files # default to true, for a simple tree
	
	var target_dir = root_dir
	
	tree_helper.clear_items()
	tree_helper.set_thumbnail_size()
	tree_helper.show_item_preview = show_item_preview
	tree_helper.updating = true
	
	var root_item
	var tree_root = file_tree.create_item()
	if target_dir == "res://" and show_favorites: # handle favorites
		var favorites_item = file_tree.create_item(tree_root)
		favorites_item.set_text(0, FileSystemSingleton.get_favorites_text())
		favorites_item.set_icon(0, FileSystemSingleton.get_favorites_icon())
		favorites_item.set_metadata(0, FSTreeHelper.create_item_meta(FileData.FAVORITES_META))
		var favorites = FileSystemSingleton.get_filesystem_favorites()
		for path in favorites:
			var item = file_tree.create_item(favorites_item)
			var file_data = _get_file_data(path).duplicate()
			file_data.erase(ItemKeys.BG_COLOR)
			var text = path.get_file()
			if path.ends_with("/"):
				file_data[ItemKeys.ICON_COLOR] = filesystem_singleton.get_folder_color(path)
				text = path.trim_suffix("/").get_file()
			item.set_metadata(0, FSTreeHelper.create_item_meta(path))
			item.set_text(0, text)
			tree_helper.set_item_icon(item, file_data)
			tree_helper.item_dict[FSTreeHelper.get_favorite_key(path)] = item
	
	
	root_item = file_tree.create_item(tree_root) as TreeItem
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
	
	for file_path:String in current_files:
		var file_data = _get_file_data(file_path)
		#var file_data = filesystem_singleton.get_file_data(file_path)
		if not file_data:
			continue
		
		if _flat_view:
			if file_path.ends_with("/"):
				continue
			var item = file_tree.create_item(root_item)
			item.set_metadata(0, FSTreeHelper.create_item_meta(file_path))
			tree_helper.set_item_icon(item, file_data)
			item.set_text(0, file_path.get_file())
			_process_custom_item(file_path, item)
		else:
			var last_item:TreeItem = tree_helper.new_file_path(file_path, target_dir, file_data)
			last_item.set_metadata(0, FSTreeHelper.create_item_meta(file_path))
			if not show_files and not file_path.ends_with("/"):
				last_item.free()
				tree_helper.item_dict.erase(file_path)
				continue
			_process_custom_item(file_path, last_item)
	
	
	tree_helper.updating = false
	tree_helper.select_paths(selected_paths)
	
	#if _is_filtering():
	_update_tree_items()

## Receive the leaf item of the tree. Custom processing on build.
func _process_custom_item(file_path:String, tree_item:TreeItem):
	pass
	

func _refresh_tree():
	#var t = ALibRuntime.Utils.UProfile.TimeFunction.new("refresh tree--" + root_dir)
	var item:TreeItem = file_tree.get_root()
	if not is_instance_valid(item):
		return
	while is_instance_valid(item):
		var meta = item.get_metadata(0)
		if meta != null:
			var path = meta.get(FSTreeHelperBase.Keys.METADATA_PATH)
			if path != FileData.FAVORITES_META:
				var file_data = _get_folder_data(path) if path.ends_with("/") else _get_file_data(path)
				tree_helper.set_item_icon(item, file_data)
				_process_custom_item_refresh(path, item)
		
		item = item.get_next_in_tree()
	
	
	#t.stop()

## Receive the leaf item of the tree. Custom processing on a refresh
func _process_custom_item_refresh(file_path:String, tree_item:TreeItem):
	pass

func _get_file_data(file_path:String):
	var icon_color:Color = filesystem_singleton.get_icon_color(file_path)
	if not icon_color:
		icon_color = Color.WHITE
	return {
		ItemKeys.PATH: file_path,
		ItemKeys.ICON: filesystem_singleton.get_type_icon(file_path),
		ItemKeys.ICON_COLOR: icon_color,
		ItemKeys.BG_COLOR: filesystem_singleton.get_folder_color(file_path),
	}

func _get_folder_data(file_path:String):
	return {
		ItemKeys.PATH: file_path,
		ItemKeys.ICON: tree_helper.folder_icon,
		ItemKeys.ICON_COLOR: filesystem_singleton.get_folder_color(file_path),
		ItemKeys.BG_COLOR: filesystem_singleton.get_background_color(file_path)
	}

func _on_item_activated():
	var selection = _get_selection()
	if selection.is_empty():
		return
	if selection.selected.ends_with("/"):
		var item = tree_helper.get_tree_item(selection.selected) as TreeItem
		if is_instance_valid(item):
			var clicked_item = tree_helper.get_selected_tree_items().front()
			if clicked_item and tree_helper.is_item_in_favorites(clicked_item):
				tree_helper.uncollapse_items([item])
				file_tree.scroll_to_item(item)
				file_tree.set_selected(item, 0)
			else:
				item.collapsed = not item.collapsed
	else:
		FileSystemSingleton.activate_path(selection.selected)

func _on_item_left_clicked():
	var selection = _get_selection()
	if selection.is_empty():
		return
	#if selection.selected == FileData.FAVORITES_META:
		#return
	FileSystemSingleton.ensure_items_selected(selection.selected_paths)
	return

func _on_item_right_clicked():
	var selection = _get_selection()
	if selection.is_empty():
		return
	if selection.selected == FileData.FAVORITES_META:
		return
	FileSystemSingleton.show_right_click_menu(self, selection.selected, selection.selected_paths, [])


#region FSPopup Handlers

## Adds Set/Reset Root, overide _custom_right_click_menu to add custom items.
func custom_right_click_menu(items:Dictionary, selected_path:String, selected_paths:Array):
	if _custom_popup_handler_call(&"custom_right_click_menu", [items, selected_path, selected_paths]):
		return
	
	_add_popup_root_items(items, selected_path)
	_custom_right_click_menu(items, selected_path, selected_paths)

func _custom_right_click_menu(_items:Dictionary, _selected_path:String, _selected_paths:Array):
	return

## Handles Set/Reset Root items, overide _handle_custom_popup_id for others.
func handle_custom_popup_id(id:int, popup:PopupMenu):
	if _custom_popup_handler_call(&"handle_custom_popup_id", [id, popup]):
		return
	var path = PopupHelper.parse_menu_path(id, popup)
	var meta = PopupHelper.parse_metadata(id, popup)
	var selected = meta.get("selected")
	match path:
		SET_ROOT: _set_root(selected)
		RESET_ROOT: _set_root("res://")
		_: _handle_custom_popup_id(id, popup)

func _handle_custom_popup_id(_id:int, _popup:PopupMenu):
	pass

## Handle file system items that are not just popup pass throughs.
## Overide _handle_fs_popup_id to handle any other cases (all are covered currently)
func handle_fs_popup_id(id, fs_popup):
	if id == PopupID.expand_folder():
		rc_expand_folder()
	elif id == PopupID.expand_hierarchy():
		rc_hierarchy(true)
	elif id == PopupID.collapse_hierarchy():
		rc_hierarchy(false)
	elif id == PopupID.rename():
		fs_rename_ctx.start_edit()
	elif _custom_popup_handler_call(&"handle_fs_popup_id", [id, fs_popup]):
		return

func _handle_fs_popup_id(_id:int, _fs_popup:PopupMenu):
	return

#endregion

func _set_root(new_root):
	root_dir = new_root
	_refresh_files_and_tree()
	var root_item = tree_helper.get_tree_item(root_dir)
	root_item.collapsed = false

func _add_popup_root_items(items:Dictionary, selected_path:String):
	if allow_root_pinning and selected_path.ends_with("/"):
		if selected_path != "res://":
			if selected_path == root_dir:
				items["pre"][RESET_ROOT] = create_popup_item_dict(selected_path, "Clear")
			else:
				items["pre"][SET_ROOT] = create_popup_item_dict(selected_path, "NewRoot")


func create_popup_item_dict(path:String, icon=null):
	var data = {PopupHelper.ParamKeys.METADATA: {"selected": path}}
	if icon:
		if not icon is Array:
			icon = [icon]
		data[PopupHelper.ParamKeys.ICON] = icon
	return data

func _on_filter_line_text_changed(_new_text:String):
	_update_tree_items()

func _update_tree_items():
	
	var filtering = _is_filtering()
	var changed_state = last_filter_state != filtering
	
	var item_paths = tree_helper.get_selected_paths()
	
	if not _flat_view:
		tree_helper.update_tree_items(filtering, _filter_text, root_dir)
	else:
		var root = tree_helper.get_tree_item(root_dir)
		if filtering:
			for c in root.get_children():
				c.visible =  _filter_text(c.get_text(0))
		else:
			for c in root.get_children():
				c.visible =  true
	
	if changed_state and last_filter_state:
		if item_paths.size() > 0:
			var item = tree_helper.get_tree_item(item_paths[0])
			if is_instance_valid(item):
				tree_helper.uncollapse_items([item])
				file_tree.set_selected(item, 0)
				file_tree.scroll_to_item(item, true)
	
	last_filter_state = filtering

func _filter_text(to_filter:String):
	if not filter_full_path:
		to_filter = to_filter.trim_suffix("/").get_file()
	return filter_line_edit.text.is_subsequence_of(to_filter)

func _is_filtering():
	return filter_line_edit.text != ""

#! keys selected:String selected_paths:Array
func _get_selection():
	var selected_paths = tree_helper.get_selected_paths().duplicate()
	if selected_paths.is_empty():
		return {}
	var selected = selected_paths.front()
	#print(selected, ":", selected_paths)
	return {
		&"selected": selected,
		&"selected_paths": selected_paths
	}

func _custom_popup_handler_call(method:StringName, args:Array=[]):
	if is_instance_valid(custom_popup_handler) and custom_popup_handler.has_method(method):
		custom_popup_handler.callv(method, args)
		return true
	return false

func rc_expand_folder():
	var items = tree_helper.get_selected_tree_items()
	for item in items:
		item.collapsed = false

func rc_hierarchy(expand:bool):
	var selected = file_tree.get_selected()
	selected.set_collapsed_recursive(not expand)

func _on_file_tree_get_drag_data(at_position: Vector2) -> Variant:
	var target_item = file_tree.get_item_at_position(at_position)
	if not is_instance_valid(target_item):
		return
	var selection = _get_selection()
	if selection.is_empty():
		return
	return FileSystemSingleton.GetDropData.files(selection.selected_paths, self)


func _on_file_tree_can_drop_data(at_position, data):
	return FileSystemSingleton.CanDropData.files(at_position, data)

func _on_file_tree_drop_data(at_position: Vector2, data: Variant) -> void:
	var target_item = file_tree.get_item_at_position(at_position)
	if not is_instance_valid(target_item):
		return
	var meta = target_item.get_metadata(0)
	var target_dir = ""
	if meta is String:
		target_dir = meta
	if meta is Dictionary:
		target_dir = FSTreeHelper.get_path_from_item(target_item)
	if not target_dir.ends_with("/"):
		target_dir = target_dir.get_base_dir() # was using UFile.get_dir, does it matter?
	
	FileSystemSingleton.DropData.move_dialog(data, target_dir, self)

func set_tree_item_params(path:String, item:TreeItem, file_data:Dictionary):
	item.set_metadata(0, FSTreeHelper.create_item_meta(path))
	#item.set_icon(0, filesystem_singleton.get_type_icon(path))
	#var color = filesystem_singleton.get_icon_color(path)
	#if color:
		#item.set_icon_modulate(0, color)
	item.set_icon(0, file_data.get(ItemKeys.ICON))
	item.set_icon_modulate(0, file_data.get(ItemKeys.ICON_COLOR))
	item.set_icon_max_width(0, int(tree_helper.thumbnail_size))


class FSTreeHelper extends FSTreeHelperBase:
	
	# this should nullify above
	func _set_item_icon(last_item:TreeItem, file_data:Dictionary):
		set_item_icon(last_item, file_data)
	
	func set_item_icon(last_item:TreeItem, file_data:Dictionary):
		if show_item_preview and file_data.has(ItemKeys.PREVIEW):
			last_item.set_icon(0, file_data.get(ItemKeys.PREVIEW))
		else:
			last_item.set_icon(0, file_data.get(ItemKeys.ICON))
		#if file_data.get(ItemKeys.PATH).ends_with("/"):
	
		#else:
		last_item.set_icon_modulate(0, file_data.get(ItemKeys.ICON_COLOR, Color.WHITE))
		last_item.set_icon_max_width(0, int(thumbnail_size))

class MinTree extends Tree:
	func _make_custom_tooltip(_for_text: String) -> Object:
		var item = get_item_at_position(get_local_mouse_position())
		if item:
			var path = FSTreeHelper.get_path_from_item(item)
			if not path in ["res://", FileData.FAVORITES_META]:
				return FileSystemSingleton.get_custom_tooltip(path)
		return null


class ItemKeys:
	const PATH = &"path"
	const ICON = &"icon"
	const ICON_COLOR = &"icon_color"
	const BG_COLOR = &"bg_color"
	const PREVIEW = &"preview"

class PersistentData:
	const ROOT_DIR = &"fs_tree.root_dir"
	const TREE_ITEM_META = &"fs_tree.tree_item_meta"
	const FLAT_VIEW = &"fs_tree.flat_view"
	const EXTENSIONS = &"fs_tree.extensions"
	const MULTI_SELECT = &"fs_tree.multi_select"
	const ALLOW_ROOT_PINNING = &"fs_tree.allow_root_pinning"
	const SHOW_FAVORITES = &"fs_tree.show_favorites"
	const SHOW_EMPTY_DIRS = &"fs_tree.show_empty_dirs"
