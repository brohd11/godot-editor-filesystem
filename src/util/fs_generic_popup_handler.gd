
const PopupID = preload("uid://co1fsmkihc4cg") #! resolve ALibEditor.Nodes.FileSystem.PopupID
const FSPopupHelper = preload("res://addons/addon_lib/editor_filesystem/src/util/fs_popup_helper.gd")


const HANDLE_RIGHT_CLICK_METHOD = &"custom_right_click_menu"
const HANDLE_ID_METHOD = &"handle_fs_popup_id"
const HANDLE_CUSTOM_ID_METHOD = &"handle_custom_popup_id"

const HIDE_HANDLED_ID = [
	"Rename...",
	"Expand Folder",
	"Expand Hierarchy",
	"Collapse Hierarchy",
	]


var filesystem_singleton:FileSystemSingleton

var clicked_node:Node
var selected_path:String

func _init() -> void:
	filesystem_singleton = FileSystemSingleton.get_instance()


func right_clicked(clicked:Node, selected_item_path:String, selected_paths:Array, to_hide:=HIDE_HANDLED_ID):
	_right_click_menu(clicked, selected_item_path, selected_paths, to_hide)

func _right_click_menu(clicked:Node, selected_item_path:String, selected_paths:Array, names_to_hide:Array=[]):
	var items_selected = FileSystemSingleton.ensure_items_selected(selected_paths)
	if not items_selected:
		return
	
	clicked_node = clicked
	selected_path = selected_item_path
	FileSystemSingleton.populate_filesystem_popup(clicked_node)
	var items = {
		"pre":{},
		"post":{}
		}
	
	if clicked_node.has_method(HANDLE_RIGHT_CLICK_METHOD):
		clicked_node.call(HANDLE_RIGHT_CLICK_METHOD, items, selected_path, selected_paths)
	
	var window = clicked_node.get_window()
	var popup = PopupMenu.new()
	window.add_child(popup)
	popup.popup_hide.connect(_on_popup_hide.bind(popup), 1)
	FSPopupHelper.recreate_popup(popup, _on_wrapper_clicked, names_to_hide, items)
	popup.position = DisplayServer.mouse_get_position()
	popup.popup()


func _on_wrapper_clicked(id:int, popup:PopupMenu, fs_popup:PopupMenu=null):
	if fs_popup == null:
		_handle_non_fs(id, popup)
		return
	
	#print(id)
	var queue_rescan = false
	var is_folder_popup = fs_popup.get_item_text(0) == "Default (Reset)"
	var is_create_popup = fs_popup == EditorNodeRef.get_registered(EditorNodeRef.Nodes.FILESYSTEM_CREATE_POPUP)
	FileSystemSingleton.move_dialogs(clicked_node)
	if is_folder_popup:
		fs_popup.id_pressed.emit(id)
		filesystem_singleton.rebuild_files()
		return
	elif is_create_popup:
		pass
	else:
		if id in get_ids_need_rescan():
			queue_rescan = true
		
		if id in get_ids_need_handle_folder() or id in get_ids_need_handle_file():
			_handle_fs(id, fs_popup)
			return
	
	if id >= 5000:
		_handle_non_fs(id, popup)
	else:
		if fs_popup == EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.FILESYSTEM_BOTTOM_POPUP):
			fs_popup = EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.FILESYSTEM_POPUP)
		if id == PopupID.reimport():
			await _reimport_pressed(fs_popup, popup)
		else:
			fs_popup.id_pressed.emit(id)
		
	
	if queue_rescan:
		filesystem_singleton.rebuild_files()

func _reimport_pressed(fs_popup, popup_wrapper):
	fs_popup.position = popup_wrapper.position
	fs_popup.show()
	await filesystem_singleton.get_tree().process_frame
	fs_popup.id_pressed.emit(PopupID.reimport())
	fs_popup.hide()


func _handle_fs(id, fs_popup):
	if clicked_node.has_method(HANDLE_ID_METHOD):
		clicked_node.call(HANDLE_ID_METHOD, id, fs_popup)

func _handle_non_fs(id, popup):
	if clicked_node.has_method(HANDLE_CUSTOM_ID_METHOD):
		clicked_node.call(HANDLE_CUSTOM_ID_METHOD, id, popup)


func _on_popup_hide(popup:PopupMenu):
	popup.queue_free()
	_reset.call_deferred()

func _reset():
	clicked_node = null
	selected_path = ""


static func get_ids_need_rescan():
	return [PopupID.add_to_favorites(), PopupID.remove_from_favorites()]

static func get_ids_need_handle_folder():
	return [PopupID.rename(), PopupID.expand_folder(), PopupID.expand_hierarchy(), PopupID.collapse_hierarchy()]

static func get_ids_need_handle_file():
	return [PopupID.rename()]
