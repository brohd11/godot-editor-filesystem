extends Node

const PopupHelper = preload("uid://ba5x2r7gyvmej") #! resolve UtilR.Nodes.PopupMenus.PathHelper
const FSClasses = preload("res://addons/_lib/editor_filesystem/src/util/fs_classes.gd")
const FileSystemTab = FSClasses.FileSystemTab
const FileSystemTree = FSClasses.FileSystemTree

const FileSystemItemList = FSClasses.FileSystemItemList
const FileSystemPlaces = FSClasses.FileSystemPlaces

const FSPopupHelper = FSClasses.FSPopupHelper

const FSUtil = FSClasses.FSUtil
const EditorIcons = FSUtil.EditorIcons

const PopupID = FSUtil.PopupID

const FSGenericPopupHandler = FileSystemSingleton.FSGenericPopupHandler

const ITEM_LIST_EMPTY_HIDE = ["Rename..."]

const NEW_WINDOW = "New/Window"
const CREATE_NEW_TAB = "New/Tab"
const _NEW_SPLIT = "New/Split/"
const NEW_SPLIT_LEFT = _NEW_SPLIT + "Left"
const NEW_SPLIT_RIGHT = _NEW_SPLIT + "Right"
const NEW_SPLIT_UP = _NEW_SPLIT + "Up"
const NEW_SPLIT_DOWN = _NEW_SPLIT + "Down"
const ADD_TO_PLACES = "Add to Places"
const SET_ROOT = "Set Root"
const RESET_ROOT = "Reset Root"

signal new_tab(path)
signal add_to_places(path)

var filesystem_singleton:FileSystemSingleton


var current_browser_state:FileSystemTab.BrowserState=FileSystemTab.BrowserState.BROWSE

var filesystem_tab:FileSystemTab
var tree:FileSystemTree
var item_list:FileSystemItemList
var places:FileSystemPlaces

var _clicked_node_local:Node
var _selected_path:String

func _init() -> void:
	filesystem_singleton = FileSystemSingleton.get_instance()


func right_clicked_empty_item_list(clicked_node:Node, selected_item_path:String):
	_clicked_node_local = clicked_node
	_selected_path = selected_item_path
	
	var hide_names = FSPopupHelper.MenuItems.TO_HIDE_ITEM_LIST_EMPTY
	FileSystemSingleton.show_right_click_menu(self, selected_item_path, [selected_item_path], hide_names)
	#gen_handler.right_clicked(self, selected_item_path, [selected_item_path], hide_names)

func right_clicked(clicked_node:Node, selected_item_path:String, selected_paths:Array):
	
	_clicked_node_local = clicked_node
	_selected_path = selected_item_path
	
	var hide_names = []
	if clicked_node is FileSystemItemList:
		hide_names = FSPopupHelper.MenuItems.TO_HIDE_ITEM_LIST
	FileSystemSingleton.show_right_click_menu(self, selected_item_path, selected_paths, hide_names)
	#gen_handler.right_clicked(self, selected_item_path, selected_paths, hide_names)
	


func _rc_new_tab():
	var selected_path = _selected_path
	if selected_path and selected_path.ends_with("/"):
		new_tab.emit(selected_path)

func _new_split(id_text:String):
	var selected_path = _selected_path
	var fs_data = filesystem_tab.get_dock_data()
	if filesystem_tab._current_view_mode == FileSystemTab.ViewMode.TREE:
		fs_data[FileSystemTab.DataKeys.ROOT] = selected_path
	fs_data[FileSystemTab.DataKeys.CURRENT_PATH] = selected_path
	EditorGlobalSignals.signal_emitv(FileSystemTab.DataKeys.GLOBAL_NEW_SPLIT_SIGNAL, [filesystem_tab, id_text, fs_data])

func _add_to_places(meta:Dictionary):
	var selected_path = _selected_path
	var place_list = meta.get("place_list")
	places.add_place_item(selected_path, place_list)
	add_to_places.emit(selected_path)

# Customs handlers

func custom_right_click_menu(items:Dictionary, selected:String, selected_paths:Array):
	var clicked = _clicked_node_local
	var selected_is_dir = selected.ends_with("/")
	if clicked is FileSystemTree:
		if selected == clicked.root_dir:
			items["pre"][RESET_ROOT] = {
				PopupHelper.ParamKeys.ICON:["Clear"]
			}
		elif selected != "res://" and selected_is_dir:
			items["pre"][SET_ROOT] = {
				PopupHelper.ParamKeys.ICON:["NewRoot"]
			}
	if selected_is_dir and selected_paths.size() == 1:# and not tree_helper.is_item_in_favorites(selected_item):
		items["pre"][NEW_WINDOW] = {PopupHelper.ParamKeys.ICON:["New", "Window"]}
		items["pre"][CREATE_NEW_TAB] = {PopupHelper.ParamKeys.ICON:["New", EditorIcons.get_icon_white("TabContainer")]}
		var split_icon = EditorIcons.get_icon_white("SplitContainer", 1)
		for direction in [NEW_SPLIT_LEFT, NEW_SPLIT_RIGHT, NEW_SPLIT_UP, NEW_SPLIT_DOWN]:
			items["pre"][direction] = {PopupHelper.ParamKeys.ICON:["New", split_icon, null]}
		
		var places_options = places.get_add_to_places_options(_selected_path).get_options()
		for option in places_options.keys():
			items["pre"][option] = places_options[option]
			items["pre"][option].erase(PopupHelper.ParamKeys.CALLABLE)
	pass

func handle_fs_popup_id(id:int, popup:PopupMenu):
	var clicked = _clicked_node_local
	var queue_rescan = false
	var is_dir = _selected_path.ends_with("/")
	if id in FSGenericPopupHandler.get_ids_need_rescan():
		queue_rescan = true
	if id == PopupID.rename():
		clicked.start_edit()
		return
	if is_dir and id in FSGenericPopupHandler.get_ids_need_handle_folder():
		if clicked is FileSystemTree:
			if id == PopupID.expand_folder():
				clicked.rc_expand_folder()
			if id == PopupID.expand_hierarchy():
				clicked.rc_hierarchy(true)
			if id == PopupID.collapse_hierarchy():
				clicked.rc_hierarchy(false)
				
		elif clicked is FileSystemItemList:
			pass
		if queue_rescan:
			filesystem_singleton.rebuild_files()

func handle_custom_popup_id(id:int, popup:PopupMenu):
	var selected_path = _selected_path
	var id_text = PopupHelper.parse_menu_path(id, popup)
	if id_text == CREATE_NEW_TAB:
		_rc_new_tab()
	elif id_text == NEW_WINDOW:
		var fs_data = filesystem_tab.get_dock_data()
		if filesystem_tab._current_view_mode == FileSystemTab.ViewMode.TREE:
			fs_data[FileSystemTab.DataKeys.ROOT] = selected_path
		fs_data[FileSystemTab.DataKeys.CURRENT_PATH] = selected_path
		EditorGlobalSignals.signal_emit(FileSystemTab.DataKeys.GLOBAL_NEW_WINDOW_SIGNAL, fs_data)
	elif id_text.begins_with(ADD_TO_PLACES):
		_add_to_places(PopupHelper.get_metadata(id, popup))
	elif id_text == SET_ROOT:
		tree.set_dir(selected_path, true)
		item_list.tree_root = selected_path
		filesystem_tab.refresh_current_path()
	elif id_text == RESET_ROOT:
		tree.set_dir("res://", true)
		item_list.tree_root = "res://"
		filesystem_tab.refresh_current_path()
	elif id_text.begins_with(_NEW_SPLIT):
		_new_split(id_text)
