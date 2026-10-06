extends RefCounted

const PopupHelper = PopupWrapper.PopupHelper

static func recreate_popup(new_popup:PopupMenu, callable:Callable, hide_names:Array=[], other_items:Dictionary={}):
	#ZyxPopupWrapperSingleton.Enable.filesystem(false, false)
	_zyx_enable(false)
	
	var fs_popup:PopupMenu = EditorNodeRef.get_registered(EditorNodeRef.Nodes.FILESYSTEM_POPUP)
	#if not fs_popup.visible: #^ not sure about this, was needed now it seems not?
		#fs_popup = EditorNodeRef.get_node_ref(EditorNodeRef.Nodes.FILESYSTEM_BOTTOM_POPUP)
	
	new_popup.id_pressed.connect(callable.bind(new_popup, fs_popup))
	new_popup.popup_hide.connect(_on_popup_hide)
	
	var other_pre_items = other_items.get("pre", {})
	var pre_size = other_pre_items.keys().size()
	var other_post_items = other_items.get("post", {})
	var post_size = other_post_items.keys().size()
	var other_items_pre_id = 5000
	var other_items_post_id = 5000 + pre_size
	if pre_size > 0:
		PopupHelper.parse_dict_static(other_pre_items, new_popup, callable, null, other_items_pre_id)
		new_popup.add_separator()
	
	var wrapper_params = PopupWrapper.WrapperParams.new()
	wrapper_params.items_to_skip = hide_names
	wrapper_params.show_shortcuts = false
	wrapper_params.fs_popup_callable = callable
	wrapper_params.connect_callable = false
	PopupWrapper.popup_wrapper(new_popup, fs_popup, wrapper_params)
	
	if post_size > 0:
		if not new_popup.is_item_separator(new_popup.item_count - 1):
			new_popup.add_separator()
		PopupHelper.parse_dict_static(other_post_items, new_popup, callable, null, other_items_post_id)

static func _on_popup_hide():
	#ZyxPopupWrapperSingleton.Enable.filesystem(true, false)
	_zyx_enable(true)

static func _zyx_enable(enable:bool):
	var zyx = Singletons.CheckInstance.get_instance("ZyxPopupWrapperSingleton")
	if is_instance_valid(zyx):
		zyx.Enable.filesystem(enable, false)


class MenuItems:
	const TO_HIDE_ITEM_LIST = ["", EXPAND_FOLDER, EXPAND_HIERARCHY, COLLAPSE_HIERARCHY]
	const TO_HIDE_ITEM_LIST_EMPTY = ["", EXPAND_FOLDER, EXPAND_HIERARCHY, COLLAPSE_HIERARCHY,
	RENAME, DUPLICATE, DELETE, MOVE_DUPLICATE_TO]
	
	const RENAME = "Rename..."
	const EXPAND_FOLDER = "Expand Folder"
	const EXPAND_HIERARCHY = "Expand Hierarchy"
	const COLLAPSE_HIERARCHY = "Collapse Hierarchy"
	
	const DUPLICATE = "Duplicate..."
	const MOVE_DUPLICATE_TO = "Move/Duplicate To..."
	const DELETE = "Delete"
	
