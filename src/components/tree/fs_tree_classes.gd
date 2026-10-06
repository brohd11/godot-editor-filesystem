

const FSTreeHelperBase = preload("res://addons/_lib/editor_filesystem/src/util/fs_tree_helper_base.gd")
const FileData = FileSystemSingleton.FileData

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
	
	var tree_helper:FSTreeHelper
	
	var allow_drag:=true
	
	#! keys selected:String selected_paths:Array
	func get_selection() -> Dictionary:
		var selected_paths = tree_helper.get_selected_paths().duplicate()
		if selected_paths.is_empty():
			return {}
		var selected = selected_paths.front()
		#print(selected, ":", selected_paths)
		return {
			&"selected": selected,
			&"selected_paths": selected_paths
		}
	
	
	func _make_custom_tooltip(_for_text: String) -> Object:
		var item = get_item_at_position(get_local_mouse_position())
		if item:
			var path = FSTreeHelper.get_path_from_item(item)
			if path == null:
				return null
			if not path in ["res://", FileData.FAVORITES_META]:
				return FileSystemSingleton.get_custom_tooltip(path)
		return null
	
	
	func _on_file_tree_get_drag_data(at_position: Vector2) -> Variant:
		if not allow_drag:
			return null
		var target_item = get_item_at_position(at_position)
		if not is_instance_valid(target_item):
			return
		var selection = get_selection()
		if selection.is_empty():
			return
		return FileSystemSingleton.GetDropData.files(selection.selected_paths, self)


	func _on_file_tree_can_drop_data(at_position, data):
		if not allow_drag:
			return false
		return FileSystemSingleton.CanDropData.files(at_position, data)

	func _on_file_tree_drop_data(at_position: Vector2, data: Variant) -> void:
		if not allow_drag:
			return
		var target_item = get_item_at_position(at_position)
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


class Utils:
	static func get_file_data(file_path:String, fs_sing:FileSystemSingleton):
		var icon_color:Color = fs_sing.get_icon_color(file_path)
		if not icon_color:
			icon_color = Color.WHITE
		return {
			ItemKeys.PATH: file_path,
			ItemKeys.ICON: fs_sing.get_type_icon(file_path),
			ItemKeys.ICON_COLOR: icon_color,
			ItemKeys.BG_COLOR: fs_sing.get_folder_color(file_path),
		}

	static func get_folder_data(file_path:String, fs_sing:FileSystemSingleton):
		return {
			ItemKeys.PATH: file_path,
			ItemKeys.ICON: fs_sing.cache.folder_icon,
			ItemKeys.ICON_COLOR: fs_sing.get_folder_color(file_path),
			ItemKeys.BG_COLOR: fs_sing.get_background_color(file_path)
		}

class ItemKeys:
	const PATH = &"path"
	const ICON = &"icon"
	const ICON_COLOR = &"icon_color"
	const BG_COLOR = &"bg_color"
	const PREVIEW = &"preview"
