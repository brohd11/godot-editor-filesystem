@tool
extends VBoxContainer

#! import_p DataKeys,UControl

const ATTEMPT_RENAME = true

const RightClickHandler = FSUtil.RightClickHandler
const UFile = FSUtil.UFile
const GetFilesAsync = FSUtil.GetFilesAsync
const UControl = FSUtil.UControl
const EditorIcons = FSUtil.EditorIcons
const CacheHelper = FSUtil.CacheHelper

const FSClasses = preload("res://addons/addon_lib/editor_filesystem/src/util/fs_classes.gd")
const FileSystemTab = FSClasses.FileSystemTab
const FileSystemPathBar = FSClasses.FileSystemPathBar
const FileSystemTree = FSClasses.FileSystemTree
const FileSystemItemList = FSClasses.FileSystemItemList
const FileSystemPlaces = FSClasses.FileSystemPlaces
const FileSystemMiller = FSClasses.FileSystemMiller

const FSPopupHelper = FSClasses.FSPopupHelper
const FSPopupHandler = FSClasses.FSPopupHandler
const FSFilter = FSClasses.FSFilter
const FilterMode = FSFilter.FilterMode
const FSUtil = FSClasses.FSUtil
const NonResHelper = FSClasses.NonResHelper

const FILTER_DELAY = 0.15
const FAVORITES_META = "FAVORITES"


enum BrowserState {
	BROWSE,
	SEARCH
}
enum ViewMode {
	TREE,
	PLACES,
	MILLER
}
enum SplitMode {
	NONE,
	VERTICAL,
	HORIZONTAL
}
enum SearchView{
	AUTO,
	ITEM_LIST,
}


var filesystem_singleton:FileSystemSingleton
var fs_popup_handler:FSPopupHandler
var right_click_handler:RightClickHandler
var non_res_helper:NonResHelper

var max_history_size:int = 20
var _recent_files:= []
var _history:= []
var _history_index:int = -1
var current_path:String = "res://" #^ setting - d
var current_dir:String = "res://"
var current_selected_paths:= PackedStringArray()
var _path_in_res:=true

var togglable_elements:= []
var _toolbar_debounce_timer:Timer
var tool_bar_hbox:HBoxContainer

var path_bar:FileSystemPathBar
var search_label:Label
var tool_bar_spacer:Control

var search_hbox:HBoxContainer
var main_split_container:SplitContainer
var tree_item_split:SplitContainer
var tree: FileSystemTree
var places:FileSystemPlaces

var right_side_vbox:VBoxContainer
var miller:FileSystemMiller
var item_list:FileSystemItemList

var preview_panel:FSClasses.PreviewPanel

var _history_back_button:Button
var _history_forward_button:Button
var _toggle_places_button:Button
var _toggle_path_button:Button
var _navigate_up_button:Button
var _tree_button:Button
var _places_button:Button
var _miller_button:Button
var _search_button:Button
var options_button:Button

var _search_scope_button:Button

var _async_search:GetFilesAsync
var _search_tick:int = 1
var _async_is_searching:= false
var _current_search_dir:= ""

var filters:= []
var _filter_timer:Timer

var _search_bar_spacer:Control
var file_type_filter:OptionButton
const _NO_FILTER_NAME = "Type"

var _filtered_paths:= PackedStringArray()
var _type_filtered_paths:= PackedStringArray()
var _last_prefix_filters:= PackedStringArray()

var _last_browser_state:=BrowserState.BROWSE
var _current_browser_state:= BrowserState.BROWSE


var _current_search_view:SearchView=SearchView.AUTO #^ setting - dd

var _search_whole_filesystem:bool=true #^ setting - dd
var _search_select_path:bool=true #^ setting - dd
var _search_tree_list_dir:bool=false #^ setting - dd
var _current_filter_mode:FSFilter.FilterMode = FSFilter.FilterMode.AUTO #^ setting - dd
var _filter_mode_follow_view_mode:= true  #^ setting - dd

var _places_toggled:=true #^ setting - dd - this is in both view data and dock data
var _places_follow_view_mode:=true  #^ setting - dd
var _alt_list_color:=false #^ setting - dd

var _current_view_mode:ViewMode = ViewMode.TREE #^ setting - dd
var _current_split_mode:SplitMode = SplitMode.NONE #^ setting - dd

var _signal_busses:Array[StringName] = [&"rt_send_asset"] # default for ray tool

var _show_preview:=false

var _view_data:Dictionary = {}


var plugin_tab_container
var _dock_data:Dictionary = {}

var _initialized:=false

signal new_plugin_tab(control)

func can_be_freed() -> bool:
	var tabs = plugin_tab_container.get_all_tab_controls()
	return not tabs.size() == 1

func get_tab_title():
	if tree.root_dir == "res://":
		return "FileSystem"
	else:
		return tree.root_dir.trim_suffix("/").get_file()

func set_dir(target_dir:String):
	tree.set_dir(target_dir)
	item_list.tree_root = target_dir

func _ready() -> void:
	if is_part_of_edited_scene():
		return
	
	EditorInterface.get_file_system_dock().folder_moved.connect(_on_folder_moved)
	filesystem_singleton = FileSystemSingleton.get_instance()
	filesystem_singleton.filesystem_changed.connect(_on_scan_files_complete, 1)
	
	_build_nodes()
	
	var fresh_instance = _dock_data.is_empty()
	_set_data_on_ready()
	if fresh_instance:
		_set_editor_defaults()
	
	_set_draw_list_lines(_alt_list_color)
	_update_history_buttons()
	_set_view_data() #^ must ensure root dir is set before calling
	visibility_changed.connect(_on_visibilty_changed, 1)
	_set_current_path(self, current_path)
	
	tree.scroll_to_path(current_path)
	
	# used to stop filter text signal from firing
	_initialized = true
	
	#_check_toolbar_elements() #^ this doesn't set the search label?

func _exit_tree() -> void:
	FileSystemSingleton.reset_dialogs(self)

func get_split_options() -> RightClickHandler.Options:
	var options = RightClickHandler.Options.new()
	
	var msg_text = "Hide Tool Bar" if tool_bar_hbox.visible else "Show Tool Bar"
	var icon = EditorIcons.get_visibility_icon(tool_bar_hbox.visible)
	var val = not tool_bar_hbox.visible
	options.add_option(msg_text, _toggle_element.bind(tool_bar_hbox, val), [icon])
	
	return options

func set_dock_data(data:Dictionary):
	_build_nodes()
	
	_dock_data = data
	
	current_path = _dock_data.get(DataKeys.CURRENT_PATH, "res://")
	_recent_files = _dock_data.get(DataKeys.RECENT_FILES, [])
	_current_view_mode = _dock_data.get(DataKeys.VIEW_MODE, ViewMode.TREE)
	_view_data = _dock_data.get(DataKeys.VIEW_DATA, {})
	
	_places_toggled = _dock_data.get(DataKeys.PLACES_TOGGLED, false)
	_places_follow_view_mode = _dock_data.get(DataKeys.PLACES_TOGGLED_FOLLOW, true)
	_current_filter_mode = _dock_data.get(DataKeys.FILTER_MODE, FilterMode.AUTO)
	_filter_mode_follow_view_mode = _dock_data.get(DataKeys.FILTER_MODE_FOLLOW, true)
	
	_search_select_path = _dock_data.get(DataKeys.SEARCH_SELECT_PATH, true)
	_search_whole_filesystem = _dock_data.get(DataKeys.SEARCH_WHOLE_FS, false)
	_current_search_view = _dock_data.get(DataKeys.SEARCH_VIEW, SearchView.AUTO)
	_alt_list_color = _dock_data.get(DataKeys.LIST_ALT_COLOR, false)
	
	_set_signal_busses(_dock_data.get(DataKeys.SIGNAL_BUSSES, PackedStringArray()))
	
	_search_tree_list_dir = _dock_data.get(DataKeys.TREE_SEARCH_LIST_DIR, false)


func _set_data_on_ready():
	
	set_dir(_dock_data.get(DataKeys.ROOT, "res://"))
	tree.tree_helper.data_dict = _dock_data.get(DataKeys.TREE_ITEM_META, {})
	tree.show_item_preview = _dock_data.get(DataKeys.TREE_PREVIEW_ICONS, false)
	
	
	var path_bar_view_mode = _dock_data.get(DataKeys.PATH_BAR_MODE, 0)
	path_bar.set_view_mode(path_bar_view_mode)
	var path_bar_visible = _dock_data.get(DataKeys.PATH_BAR_TOGGLED, true)
	if not path_bar_visible:
		_toggle_element(path_bar, false)
	var hidden_elements = _dock_data.get(DataKeys.TOGGLED_ELEMENTS, [])
	for element in togglable_elements:
		if not element.name in hidden_elements:
			continue
		_toggle_element(element, false)
	
	_set_search_visible(_dock_data.get(DataKeys.SEARCH_VISIBLE, false))

func _set_editor_defaults():
	var ed_settings = EditorInterface.get_editor_settings()
	_alt_list_color = ed_settings.get_setting(EditorSet.LIST_ALT_COLOR)
	_current_view_mode = ed_settings.get_setting(EditorSet.VIEW_MODE) as ViewMode

func get_dock_data() -> Dictionary:
	_get_view_data()
	var data = {}
	data[DataKeys.ROOT] = tree.root_dir
	
	var item_meta = {}
	for path in tree.tree_helper.data_dict.keys():
		var path_data = tree.tree_helper.data_dict.get(path)
		var collapsed = path_data.get(tree.tree_helper.Keys.METADATA_COLLAPSED)
		if collapsed:
			continue
		item_meta[path] = {tree.tree_helper.Keys.METADATA_COLLAPSED:false}
	
	#data[DataKeys.TREE_SCROLL_OFFSET] = tree.get_scroll()
	data[DataKeys.TREE_ITEM_META] = item_meta
	data[DataKeys.TREE_PREVIEW_ICONS] = tree.show_item_preview
	data[DataKeys.TREE_SEARCH_LIST_DIR] = _search_tree_list_dir
	data[DataKeys.SEARCH_VISIBLE] = search_hbox.visible
	data[DataKeys.SEARCH_SELECT_PATH] = _search_select_path
	data[DataKeys.SEARCH_WHOLE_FS] = _search_whole_filesystem
	data[DataKeys.SEARCH_VIEW] = _current_search_view
	
	data[DataKeys.CURRENT_PATH] = current_path
	data[DataKeys.RECENT_FILES] = _recent_files
	data[DataKeys.LIST_ALT_COLOR] = _alt_list_color
	data[DataKeys.TOGGLED_ELEMENTS] = _get_hidden_element_names()
	data[DataKeys.PATH_BAR_MODE] = path_bar.get_view_mode()
	data[DataKeys.PATH_BAR_TOGGLED] = path_bar.visible
	data[DataKeys.PLACES_TOGGLED] = _places_toggled
	data[DataKeys.PLACES_TOGGLED_FOLLOW] = _places_follow_view_mode
	data[DataKeys.FILTER_MODE] = _current_filter_mode
	data[DataKeys.FILTER_MODE_FOLLOW] = _filter_mode_follow_view_mode
	
	data[DataKeys.SIGNAL_BUSSES] = _signal_busses
	
	data[DataKeys.VIEW_MODE] = _current_view_mode
	data[DataKeys.VIEW_DATA] = _view_data
	
	return data


func _on_scan_files_complete():
	# this should trigger a rebuild I think
	_set_filesystem_dirty_flag()
	_set_current_path(self, current_path, false)
	refresh()

func _on_folder_moved(old_path:String, new_path:String):
	pass # needs tree helper refactor to new base
	#var rename = FSTreeHelper.update_root(root_dir, old_path, new_path)
	#if rename != "":
		#root_dir = rename
	#if tree.root_dir == old_path:
		#pass

func _set_filesystem_dirty_flag():
	tree.filesystem_dirty = true
	places.on_filesystem_changed()
	miller.on_filesystem_changed()

func refresh(full:=false):
	if full:
		tree.queue_force_refresh()
		item_list.queue_force_refresh()
		miller.queue_force_refresh()
	if tree.active:
		tree.refresh()
	if item_list.active:
		item_list.refresh()
	if miller.active:
		miller.refresh()


func _on_visibilty_changed():
	_set_active()
	refresh(true)

func _set_active():
	if visible:
		var tree_act = _current_view_mode == ViewMode.TREE
		await tree.set_active(tree_act)
		var item_act = _current_view_mode == ViewMode.PLACES
		if _tree_view_with_split_mode():
			item_act = true
		item_list.set_active(item_act)
		miller.set_active(_current_view_mode == ViewMode.MILLER)
		places.set_active(places.visible)
	else:
		tree.set_active(false)
		item_list.set_active(false)
		miller.set_active(false)
		places.set_active(false)

func _on_filter_type_selected(idx:int):
	if idx == 0:
		_last_prefix_filters.clear()
	_start_filter_debounce()

func _on_filter_text_changed(_new_text:String):
	_start_filter_debounce()

func _start_filter_debounce():
	if not _initialized:
		return
	_filter_timer.start(FILTER_DELAY)

func _restart_search():
	_last_browser_state = BrowserState.BROWSE
	_last_prefix_filters.clear()
	_set_filter_texts()

func _set_filter_texts():
	if _is_filtering():
		_current_browser_state = BrowserState.SEARCH
	else:
		_current_browser_state = BrowserState.BROWSE
	
	if _async_is_searching:
		if _current_browser_state == BrowserState.BROWSE:
			if is_instance_valid(_async_search):
				_async_search.cancel()
		_filter_timer.start(FILTER_DELAY)
		return
	
	_set_browser_states()
	
	#^c SEARCH
	if _current_browser_state == BrowserState.SEARCH:
		_set_filter_text_search()
	elif _current_browser_state == BrowserState.BROWSE:
		_set_filter_text_browse()
	
	_last_browser_state = _current_browser_state

func _set_filter_text_search():
	var is_tree = _current_view_mode == ViewMode.TREE
	if _last_browser_state != _current_browser_state:
		if (_path_in_res or is_tree) and _search_whole_filesystem:
			if is_tree:
				_current_search_dir = tree.root_dir
			else:
				_current_search_dir = "res://"
		else:
			_current_search_dir = current_dir
		_get_view_data() #^ save current view data when switching state
		
		tree.select_paths([], false)
		if is_tree:
			tree.select_paths.call_deferred([_current_search_dir], false)
		item_list.deselect_all()
	
	path_bar.hide()
	search_label.show()
	var display = _current_search_dir.trim_suffix("/").get_file()
	if FSUtil.is_root_folder(_current_search_dir):
		display = _current_search_dir
	search_label.text = 'Searching "%s"' % display
	search_label.tooltip_text = _current_search_dir
	
	if _current_search_view == SearchView.AUTO:
		_set_search_view_auto()
	elif _current_search_view == SearchView.ITEM_LIST:
		_set_search_view_item_list()

func _set_filter_text_browse():
	_toggle_element_respect_meta(path_bar, true)
	search_label.hide()
	
	path_bar.set_current_dir(current_dir)
	
	tree.set_filtered_paths([])
	tree.update_filter()
	
	item_list.set_filtered_paths([])
	
	miller.set_filtered_paths([])
	miller.clear_columns()
	miller.set_current_dir(current_dir)
	
	if _last_browser_state != _current_browser_state:
		_async_search = null
		_current_search_dir = current_dir
		_set_view_data() #^ reset layout to current view data on switching state
		if _current_view_mode == ViewMode.TREE and _search_select_path:
			tree.select_paths([current_path], false, true)




func _set_search_view_auto():
	var filter_mode = _current_filter_mode
	if _current_view_mode == ViewMode.TREE and (_current_split_mode == SplitMode.NONE or _search_tree_list_dir):
		if filter_mode == FilterMode.AUTO:
			filter_mode = FilterMode.EXACT
		tree.set_filtered_paths(await _get_filtered_paths(true, false, filter_mode))
		tree.update_filter() #^ this mode filters tree items. Selected dirs displayed in item list if list_dir setting is true
		refresh_current_path() #^ this refreshes item list if active
	elif _current_view_mode == ViewMode.MILLER:
		if filter_mode == FilterMode.AUTO:
			filter_mode = FilterMode.SUBSEQUENCE_SORT
		miller.set_filtered_paths(await _get_filtered_paths(true, true, filter_mode))
		miller.update_filter()
	elif _current_view_mode == ViewMode.PLACES or _current_split_mode != SplitMode.NONE:
		if tree.visible and tree.active:
			tree.set_filtered_paths(await _get_filtered_paths(true, false, FilterMode.EXACT))
			tree.update_filter()
		if miller.visible:
			miller.hide()
			item_list.show()
		if filter_mode == FilterMode.AUTO:
			filter_mode = FilterMode.SUBSEQUENCE_SORT
		item_list.set_filtered_paths(await _get_filtered_paths(false, true, filter_mode))
		item_list.update_filter()


func _set_search_view_item_list():
	if _current_split_mode == SplitMode.NONE:
		_set_split_mode(SplitMode.HORIZONTAL)
	item_list.show()
	if places.visible and _current_view_mode == ViewMode.TREE:
		tree_item_split.split_offset = int(places.size.x)
	tree.hide()
	miller.hide()
	_check_main_split_vis()
	
	var filter_mode = _current_filter_mode
	if filter_mode == FilterMode.AUTO:
		filter_mode = FilterMode.SUBSEQUENCE_SORT
	item_list.set_filtered_paths(await _get_filtered_paths(false, true, filter_mode))
	item_list.update_filter()


func _is_filtering():
	return not _get_filter_text_array().is_empty()

func _get_filter_text_array():
	var filter_data = {}
	var filter_array = []
	var prefix_array = PackedStringArray()
	if file_type_filter.selected != 0:
		var category = file_type_filter.get_item_text(file_type_filter.selected)
		prefix_array.append(FSFilter.Prefix.CATEGORY + category)
	
	for f in filters:
		var text = f.text
		if text == "":
			continue
		var prefix_data = FSFilter.Prefix.get_prefix(text)
		if not prefix_data:
			if not FSFilter.Prefix.text_is_prefix(text):
				filter_array.append(text)
		else:
			prefix_array.append(text)
	
	if not filter_array.is_empty():
		filter_data["filter"] = filter_array
	if not prefix_array.is_empty():
		filter_data["prefix"] = prefix_array
	
	return filter_data


func _get_filtered_paths(include_dirs:=false, use_file_name:=true, filter_mode:=_current_filter_mode):
	var paths:PackedStringArray
	if _current_search_dir == FAVORITES_META:
		paths = FileSystemSingleton.get_filesystem_favorites()
	elif _current_search_dir == "res://":
		if include_dirs:
			paths = filesystem_singleton.file_and_dir_paths.duplicate()
		else:
			paths = filesystem_singleton.file_paths.duplicate()
	elif FSUtil.is_path_valid_res(_current_search_dir):
		paths = filesystem_singleton.get_files_in_dir(_current_search_dir, include_dirs)
	else:
		if is_instance_valid(_async_search):
			paths = _async_search.get_cached_files()
		else:
			_async_is_searching = true
			_async_search = GetFilesAsync.open(_current_search_dir, _search_async_callback)
			_async_search.set_settings(include_dirs)
			paths = await _async_search.get_files(50)
			_async_is_searching = false
			_reset_filter_icons()
			if _async_search.was_cancelled():
				return PackedStringArray()
	
	
	var idx = paths.find(_current_search_dir)
	if idx > -1:
		paths.remove_at(idx)
	
	var filter_text_array = _get_filter_text_array()
	var has_prefix_filter = filter_text_array.has("prefix")
	var string_filters = filter_text_array.get("filter", [])
	var prefix_filters = filter_text_array.get("prefix", [])
	
	if has_prefix_filter:
		if _last_prefix_filters != prefix_filters:
			_last_prefix_filters = prefix_filters
			_type_filtered_paths = FSFilter.filter_with_prefixes(paths, prefix_filters)
		paths = _type_filtered_paths
	
	if filter_mode == FilterMode.EXACT:
		_filtered_paths = FSFilter.filter_exact_match(paths, string_filters, use_file_name)
	elif filter_mode == FilterMode.EXACT_SORT:
		_filtered_paths = FSFilter.filter_exact_match_sorted(paths, string_filters, use_file_name)
	elif filter_mode == FilterMode.SUBSEQUENCE:
		_filtered_paths = FSFilter.filter_subseq(paths, string_filters, use_file_name)
	elif filter_mode == FilterMode.SUBSEQUENCE_SORT:
		_filtered_paths = FSFilter.filter_subseq_sorted(paths, string_filters, use_file_name)
	
	return _filtered_paths


func _search_async_callback():
	_search_tick += 1
	if _search_tick > 90:
		_search_tick = 1
	
	var _search_icon_num = _search_tick / 10
	_search_icon_num = clampi(_search_icon_num, 1, 8)
	var icon = EditorInterface.get_editor_theme().get_icon("Progress" + str(_search_icon_num), "EditorIcons")
	_set_filter_icons(icon, false)

func _reset_filter_icons():
	var icon = EditorInterface.get_editor_theme().get_icon("Search", "EditorIcons")
	_set_filter_icons(icon, true)

func _set_filter_icons(icon, clear_enabled:=true):
	for f:LineEdit in filters:
		f.clear_button_enabled = clear_enabled
		f.right_icon = icon


func _set_browser_states(browser_state:=_current_browser_state):
	tree.current_browser_state = browser_state
	item_list.current_browser_state = browser_state
	miller.current_browser_state = browser_state
	fs_popup_handler.current_browser_state = browser_state

func _set_path_in_res(path_in_res:=_path_in_res):
	item_list.path_in_res = path_in_res
	miller.path_in_res = path_in_res
	path_bar.path_in_res = path_in_res


func navigate_to_path(path:String):
	_set_current_path(self, path, true, true)

func refresh_current_path(_refresh:=true):
	_set_current_path(self, current_path, _refresh)


## Path coming must be file or dir with trailing slash. If dir doesn't have slash, will treat as file.
func _set_current_path(who:Control, path:String, _refresh:=true, force_navigate:=false):
	var dir = path
	if not dir.ends_with("/"):
		dir = UFile.get_dir(dir)
	
	#if dir == current_dir: #^ this will stop repeats, but does this need a force flag? for refresh
		#return
	#print(dir)
	if _who_is_node(who, [tree, item_list, miller]):
		_item_path_selection(path)
	
	var navigation_selection = who != self and _who_is_node(who, [path_bar, places, _navigate_up_button, _history_back_button, _history_forward_button])
	if _current_view_mode == ViewMode.TREE:
		if not navigation_selection and who == item_list:
			navigation_selection = true
	if force_navigate:
		navigation_selection = true
	
	if _current_browser_state == BrowserState.SEARCH:
		if not _search_select_path:
			_set_current_path_search_mode(who, dir, navigation_selection)
			return
	
	current_path = path
	current_dir = dir
	
	if not visible: # all will be inactive
		return
	if current_path == FAVORITES_META:
		current_dir = FAVORITES_META
		if item_list.active:
			item_list.set_current_dir(FAVORITES_META, true)
		_path_in_res = true
		_set_path_in_res()
		return
	
	_path_in_res = FSUtil.is_path_valid_res(current_path)
	_set_path_in_res()
	
	miller.current_path = current_path
	var item_list_refresh = _current_browser_state == BrowserState.BROWSE and not _who_is_node(who, [self, item_list])
	item_list.set_current_dir(current_dir, item_list_refresh) #^ limit refresh
	path_bar.set_current_dir(current_dir)
	
	if _path_in_res and who != self:
		_select_current_paths_in_fs()
		#^r this may need some more coordination
	
	var add_to_history = who != self and not _who_is_node(who, [_history_back_button, _history_forward_button])
	if _current_browser_state == BrowserState.SEARCH:
		_set_current_path_search_mode(who, dir, navigation_selection)
		if add_to_history:
			_add_to_history(current_path)
		return
	else:
		_set_current_path_browse_mode(who, navigation_selection)
		if add_to_history:
			_add_to_history(current_path)
	
	if _refresh:
		refresh()


func _set_current_path_browse_mode(who, navigation_selection:bool):
	if _current_view_mode == ViewMode.TREE:
		var in_tree_root =  UFile.is_dir_in_or_equal_to_dir(current_dir, tree.root_dir)
		if in_tree_root and navigation_selection:
			tree.select_paths([current_dir], false, navigation_selection)
	elif _current_view_mode == ViewMode.PLACES:
		pass
	elif _current_view_mode == ViewMode.MILLER:
		if current_selected_paths.size() <= 1 or navigation_selection:
			miller.multi_select_dir = ""
		else:
			miller.multi_select_dir = current_dir
		
		miller.set_current_dir(current_dir)
		#if _who_is_node(who, [path_bar, places]):
		if navigation_selection:
			miller.set_current_column_with_path(current_dir)
			miller.show_current_column()
	
	
	if _who_is_node(who, [_history_back_button, _history_forward_button]):
		if _current_view_mode == ViewMode.TREE:
			if UFile.is_dir_in_or_equal_to_dir(current_path, tree.root_dir):
				tree.select_paths([current_path], false, true)
			if item_list.active:
				item_list.deselect_all()
				item_list.set_selected_paths([current_path])
		elif _current_view_mode == ViewMode.PLACES:
			item_list.set_selected_paths([current_path])
		elif _current_view_mode == ViewMode.MILLER:
			miller.current_path = current_path
			miller.select_path_items(current_path)


func _set_current_path_search_mode(who, dir:String, navigation_selection:bool):
	if _current_view_mode == ViewMode.MILLER and who == miller:
		miller.set_current_dir_search(dir)
		
	elif _tree_view_dir_search():
		if who != tree and UFile.is_dir_in_or_equal_to_dir(dir, tree.root_dir):
			tree.select_paths([dir], false, navigation_selection)
		var dir_paths = item_list.get_paths_at_dir(dir)
		item_list.set_filtered_paths(dir_paths)
		#item_list.queue_force_refresh()
		item_list.refresh()


func _select_current_paths_in_fs():
	#filesystem_singleton.select_items_in_fs(current_selected_paths) #^ on start the fs item dict is empty and this fails, below forces rebuild
	var valid_paths = []
	for sel_path in current_selected_paths:
		if FSUtil.is_path_valid_res(sel_path):
			valid_paths.append(sel_path)
	var selected = FileSystemSingleton.ensure_items_selected(valid_paths)
	if not selected:
		printerr("Could not select paths, ensure Editor FileSystem is not in split mode.")
		printerr(valid_paths)

func _emit_global_signals(path):
	for bus_name in _signal_busses:
		EditorGlobalSignals.signal_emitv(bus_name, [current_selected_paths])

func _who_is_node(who:Node, checks:Array):
	for c in checks:
		if c == who:
			return true
	return false

func _on_path_bar_path_selected(path:String):
	_set_current_path(path_bar, path)

func _on_places_path_selected(path:String):
	_set_current_path(places, path)

func _on_miller_path_selected(path:String, selected_paths:Array):
	current_selected_paths = selected_paths
	_set_current_path(miller, path)

func _on_tree_item_selected(path:String, selected_paths:Array):
	current_selected_paths = selected_paths
	_set_current_path(tree, path)

func _on_item_list_item_selected(path:String, selected_paths:Array):
	current_selected_paths = selected_paths
	if _current_browser_state == BrowserState.BROWSE:
		_add_to_history(path)
		_select_current_paths_in_fs()
		_item_path_selection(path)
	elif _current_browser_state == BrowserState.SEARCH:
		if path.ends_with("/") and _tree_view_dir_search():
			var dir = UFile.get_dir(path)
			_set_current_path(item_list, dir) #^ stops dirs from 1 click navigating in search, but also sets the current dir
		else:
			_set_current_path(item_list, path) #^ any other situation or for files just set the path

func _item_path_selection(path:String):
	_send_to_preview_panel(path)
	_emit_global_signals(path)

func _send_to_preview_panel(path:String):
	if not Debounce.start_debounce(&"fs_tree_preview"):
		return
	
	if _show_preview and is_instance_valid(preview_panel):
		preview_panel.preview_file(path)
		preview_panel.show()


#^r Note: This causes noticable lag when selecting a folder that houses many files/assets
#^r This lag is present in the Editor's own dock, unavoidable without complicating when to call
func _select_paths_in_fs():
	return FileSystemSingleton.ensure_items_selected(current_selected_paths)

func _update_history_buttons():
	_history_back_button.disabled = _history_index == 0
	_history_forward_button.disabled = _history_index == _history.size() - 1
	
	if _history_back_button.disabled:
		_history_back_button.tooltip_text = "Navigate to previous location."
	elif _history_index - 1 >= 0: 
		_history_back_button.tooltip_text = "Navigate to previous location: %s" % _history[_history_index - 1]
	
	if _history_forward_button.disabled:
		_history_forward_button.tooltip_text = "Navigate to next location."
	elif _history_index + 1 < _history.size():
		_history_forward_button.tooltip_text = "Navigate to next location: %s" % _history[_history_index + 1]
	

func _add_to_history(new_path:String):
	if _history_index >= 0 and _history[_history_index] == new_path:
		return
	
	if _history_index < _history.size() - 1:
		_history = _history.slice(0, _history_index + 1)
	
	if new_path in _history:
		_history.erase(new_path)
	else:
		_history_index += 1
	_history.append(new_path)
	
	if _history.size() > max_history_size:
		_history.pop_front()
		_history_index -= 1
	
	_update_history_buttons()

func _history_back():
	if _history_index > 0:
		_history_index -= 1
		_set_current_path(_history_back_button, _history[_history_index])
	_update_history_buttons()

func _history_forward():
	if _history_index < _history.size() - 1:
		_history_index += 1
		_set_current_path(_history_forward_button, _history[_history_index])
	_update_history_buttons()

func _add_path_to_recent(path:String):
	if path.ends_with("/"):
		return
	if path in _recent_files:
		_recent_files.erase(path)
	
	_recent_files.push_front(path)
	
	if _recent_files.size() > max_history_size:
		_recent_files.pop_back()

func _on_recent_popup_pressed(id_pressed:int):
	if id_pressed == _recent_files.size():
		_recent_files.clear()
	else:
		var path = _recent_files[id_pressed]
		#_set_current_path(self, path)
		_on_double_clicked(path)


func _on_item_list_double_clicked(path):
	if not path.ends_with("/"):
		_on_double_clicked(path)
		return
	_set_current_path(item_list, path)

func _on_double_clicked(selected_path:String):
	if selected_path == FAVORITES_META:
		return
	current_selected_paths = [selected_path]
	if FSUtil.is_path_valid_res(selected_path):
		if not _select_paths_in_fs():
			return
		FileSystemSingleton.activate_in_fs()
	else:
		NonResHelper.open_file(selected_path)
	_add_path_to_recent(selected_path)

func _on_item_right_clicked(clicked_node:Node, selected_item_path:String, selected_paths:Array):
	current_selected_paths = selected_paths
	if FSUtil.is_path_valid_res(selected_item_path):
		_send_to_preview_panel(selected_item_path) # handles tree/miller as well
		if not _select_paths_in_fs():
			return
		fs_popup_handler.right_clicked(clicked_node, selected_item_path, selected_paths)
	else:
		var options = non_res_helper.get_right_click_options(selected_item_path, selected_paths)
		right_click_handler.display_popup(options)
		

func _on_item_right_clicked_empty(clicked_node:Node, selected_item_path:String):
	current_selected_paths = [selected_item_path]
	if FSUtil.is_path_valid_res(selected_item_path):
		if not _select_paths_in_fs():
			return
		fs_popup_handler.right_clicked_empty_item_list(clicked_node, selected_item_path)
	else:
		var options = non_res_helper.get_right_click_options(selected_item_path, [])
		right_click_handler.display_popup(options)


func _on_places_right_clicked(index:int, place_list:FileSystemPlaces.PlaceList):
	var options = RightClickHandler.Options.new()
	options.add_option("Rename", place_list.rename_item.bind(index), ["Edit"])
	options.add_option("Remove", place_list.remove_item.bind(index), ["Close"])
	right_click_handler.display_popup(options)

func _on_places_title_right_clicked(place_list:FileSystemPlaces.PlaceList) -> void:
	var options = RightClickHandler.Options.new()
	options.add_option("New Category", places.add_place_list.bind(place_list), ["New"])
	options.add_option("Rename", place_list.rename_title, ["Edit"])
	if places.get_place_list_count() > 1:
		options.add_option("Remove", places.remove_place_list.bind(place_list), ["Close"])
		options.add_option("Redistribute Lists", places.set_split_offsets, ["ExpandTree"])
	options.add_option("Create 'Other' List", places.new_other_paths_list, ["Filesystem"])
	right_click_handler.display_popup(options)

func _on_path_bar_right_clicked(path:String):
	var options = places.get_add_to_places_options(path)
	right_click_handler.display_popup(options)


func _on_rc_new_tab(path:String): #^ new window is in fs_popup_id_handler
	var new_instance = new()
	var data = get_dock_data()
	if _current_view_mode == ViewMode.TREE:
		data[DataKeys.ROOT] = path
	data[DataKeys.CURRENT_PATH] = path
	new_instance.set_dock_data(data)
	new_plugin_tab.emit(new_instance)


func _on_options_button_pressed():
	var options = RightClickHandler.Options.new()
	
	options.add_option("Preview", _toggle_preview_panel, ["Info"])
	
	var view_icon = EditorInterface.get_editor_theme().get_icon("TexturePreviewChannels", "EditorIcons")
	var place_bar_icon = EditorInterface.get_editor_theme().get_icon("Favorites", "EditorIcons")
	#^ mode specific
	if _current_view_mode == ViewMode.TREE:
		options.add_option("Split Mode", _change_split_mode, [_get_split_icon()])
		if _current_split_mode == SplitMode.NONE:
			options.add_option("Tree Preview Icons", _set_preview_icons, [ "ImageTexture"])
	
	if _current_view_mode != ViewMode.MILLER and _current_split_mode != SplitMode.NONE:
		var string = _get_display_as_list_string()
		options.add_option(string, _set_display_as_list, _get_display_as_list_icon())
		options.add_option_data(string, [Color(5,5,5), null])
	
	options.add_option("Search", _on_search_pressed, ["Search"])
	
	#^ view mode
	var vm = _current_view_mode
	var mp_tree = "View Mode/Tree"
	var mp_place = "View Mode/Places"
	var mp_miller = "View Mode/Columns"
	options.add_radio_option(mp_tree, _change_view_mode.bind(ViewMode.TREE), vm == ViewMode.TREE, [view_icon, _tree_icon()])
	options.add_radio_option(mp_place, _change_view_mode.bind(ViewMode.PLACES), vm == ViewMode.PLACES, [view_icon, _places_icon()])
	options.add_radio_option(mp_miller, _change_view_mode.bind(ViewMode.MILLER), vm == ViewMode.MILLER, [view_icon, _miller_icon()])
	
	#^ elements
	options.add_option("Element/Toggle Path Bar", _on_path_bar_button_pressed.bind(true), ["GuiVisibilityVisible","CopyNodePath"])
	if _current_view_mode == ViewMode.TREE:
		options.add_option("Element/Toggle Side Bar", _on_places_toggled_pressed, [place_bar_icon])
	
	var element_options = _get_hidden_element_options()
	options.merge(element_options)
	
	#^ settings
	var settings_icon = EditorInterface.get_editor_theme().get_icon("Tools", "EditorIcons")
	
	options.add_option("Settings/Signals", _show_signal_dialog, [settings_icon, _get_modulated_icon("Signal")])
	
	options.add_option("Settings/Alt Line Colors (%s)" % _alt_list_color, _set_draw_list_lines.bind(not _alt_list_color), [settings_icon, "FileList"])
	
	var sb_callable = func(): _places_follow_view_mode = not _places_follow_view_mode
	options.add_option("Settings/Per Mode - Sidebar (%s)" % _places_follow_view_mode, sb_callable, [settings_icon, place_bar_icon])
	var _fm_follow_callable = func():_filter_mode_follow_view_mode = not _filter_mode_follow_view_mode
	options.add_option("Settings/Per Mode - Filter Mode (%s)" % _filter_mode_follow_view_mode, _fm_follow_callable, [settings_icon, "FilenameFilter"])
	
	#^ search
	var _ssp_call = func(): _search_select_path = not _search_select_path
	options.add_option("Settings/Search - Set Current Path (%s)" % _search_select_path, _ssp_call, [settings_icon, "Filesystem"])
	var _stld_call = func():_search_tree_list_dir = not _search_tree_list_dir; _restart_search()
	options.add_option("Settings/Search - Tree Split Dir View (%s)" % _search_tree_list_dir, _stld_call, [settings_icon, "Folder"])
	
	
	var sv = _current_search_view
	options.add_radio_option("Settings/Search - View/Auto", _set_search_view.bind(SearchView.AUTO), sv == SearchView.AUTO, [settings_icon,"ViewportZoom",view_icon])
	options.add_radio_option("Settings/Search - View/Item List", _set_search_view.bind(SearchView.ITEM_LIST), sv == SearchView.ITEM_LIST, [settings_icon,"ViewportZoom",_places_icon()])
	
	for _name in FSFilter.FilterMode.keys():
		var val = FSFilter.FilterMode[_name]
		var icons = [settings_icon, "FilenameFilter", null]
		options.add_radio_option("Settings/Filter Mode/" + _name, func():_current_filter_mode = val, _current_filter_mode == val, icons)
	
	#^c display
	var popup = right_click_handler.display_on_control(options, options_button)
	
	if not _recent_files.is_empty():
		var recents = PopupMenu.new()
		right_click_handler.mouse_helper.connect_node(recents)
		recents.id_pressed.connect(_on_recent_popup_pressed)
		popup.add_submenu_node_item("Recent Files", recents)
		popup.set_item_icon(popup.item_count - 1, EditorInterface.get_editor_theme().get_icon("History", "EditorIcons"))
		for path in _recent_files:
			recents.add_item(path)
		recents.add_item("Clear Recent Files")

func _show_signal_dialog():
	var new_signals = await EditorGlobalSignals.pick_signals_dialog(_signal_busses)
	if new_signals == null:
		return
	_set_signal_busses(new_signals)

func _set_signal_busses(new_busses:PackedStringArray):
	_signal_busses.clear()
	for bus_name in new_busses:
		_signal_busses.append(StringName(bus_name))


func _toggle_preview_panel():
	_show_preview = not _show_preview
	if _show_preview:
		_send_to_preview_panel(current_path)
	else:
		preview_panel.hide()
		preview_panel.clear()

func _change_split_mode():
	_current_split_mode += 1
	if _current_split_mode >= SplitMode.size():
		_current_split_mode = 0
	_set_split_mode()
	refresh_current_path()

func _set_split_mode(split_mode:SplitMode=_current_split_mode, set_active:=true):
	tree.show_files = false
	match split_mode:
		SplitMode.NONE: tree.show_files = true
		SplitMode.HORIZONTAL: tree_item_split.vertical = false
		SplitMode.VERTICAL: tree_item_split.vertical = true
	
	tree.queue_force_refresh()
	if split_mode != SplitMode.NONE:
		item_list.queue_force_refresh()
	_set_view_mode()
	
	if set_active:
		_set_active()

func _get_split_icon():
	match _current_split_mode:
		SplitMode.NONE: return EditorInterface.get_editor_theme().get_icon("Panels1", "EditorIcons")
		SplitMode.HORIZONTAL: return EditorInterface.get_editor_theme().get_icon("Panels2", "EditorIcons")
		SplitMode.VERTICAL: return EditorInterface.get_editor_theme().get_icon("Panels2Alt", "EditorIcons")


func _change_view_mode(view_mode:ViewMode):
	_get_view_data()
	_current_view_mode = view_mode
	_set_view_data()
	refresh_current_path(false) # refresh should be handled in set_active
	if _current_browser_state == BrowserState.SEARCH:
		_restart_search()
	

func _get_view_data():
	var data = {
		DataKeys.SPLIT_OFFSET: tree_item_split.split_offset,
		DataKeys.SPLIT_MODE:_current_split_mode,
		DataKeys.ITEM_DISPLAY_LIST: item_list.display_as_list,
		DataKeys.PLACES_TOGGLED: _places_toggled,
		DataKeys.FILTER_MODE: _current_filter_mode,
		DataKeys.SEARCH_WHOLE_FS: _search_whole_filesystem,
		}
	if _current_view_mode == ViewMode.TREE:
		_view_data[DataKeys.VIEW_DATA_TREE] = data
	elif _current_view_mode == ViewMode.PLACES:
		_view_data[DataKeys.VIEW_DATA_PLACES] = data
	elif _current_view_mode == ViewMode.MILLER:
		_view_data[DataKeys.VIEW_DATA_MILLER] = data

func _get_current_view_data():
	if _current_view_mode == ViewMode.TREE:
		return _view_data.get(DataKeys.VIEW_DATA_TREE, {})
	elif _current_view_mode == ViewMode.PLACES:
		return _view_data.get(DataKeys.VIEW_DATA_PLACES, {})
	elif _current_view_mode == ViewMode.MILLER:
		return _view_data.get(DataKeys.VIEW_DATA_MILLER, {})

func _write_view_data_var(key, val):
	_get_current_view_data()[key] = val

func _set_view_data():
	var data = _get_current_view_data()
	
	tree_item_split.split_offset = data.get(DataKeys.SPLIT_OFFSET, 0)
	_current_split_mode = data.get(DataKeys.SPLIT_MODE, SplitMode.NONE)
	if _current_view_mode != ViewMode.TREE:
		if _current_split_mode == SplitMode.NONE:
			_current_split_mode = SplitMode.HORIZONTAL
	
	_search_whole_filesystem = data.get(DataKeys.SEARCH_WHOLE_FS, _current_view_mode != ViewMode.PLACES)
	
	if _places_follow_view_mode:
		_places_toggled = data.get(DataKeys.PLACES_TOGGLED, _current_view_mode != ViewMode.TREE)
	if _filter_mode_follow_view_mode:
		_current_filter_mode = data.get(DataKeys.FILTER_MODE, FilterMode.AUTO)
	
	item_list.set_display_as_list(data.get(DataKeys.ITEM_DISPLAY_LIST, false))
	
	_set_search_scope()
	_set_view_mode()
	_set_split_mode(_current_split_mode, false) #^ do not want to set active twice
	_set_active()

func _set_view_mode():
	if _current_view_mode == ViewMode.TREE:
		tree.show()
		item_list.visible =  _current_split_mode != SplitMode.NONE
		miller.hide()
	elif _current_view_mode == ViewMode.PLACES:
		item_list.show()
		tree.hide()
		miller.hide()
	elif _current_view_mode == ViewMode.MILLER:
		miller.show()
		tree.hide()
		item_list.hide()
	
	places.visible = _places_toggled
	_check_main_split_vis()
	item_list.current_view_mode = _current_view_mode


func _set_display_as_list():
	item_list.set_display_as_list(not item_list.display_as_list)

func _get_display_as_list_string():
	if item_list.display_as_list:
		return "Grid View"
	else:
		return "List View"

func _get_display_as_list_icon():
	var list_icon = null
	if item_list.display_as_list:
		list_icon = EditorInterface.get_editor_theme().get_icon("FileThumbnail", "EditorIcons")
	else:
		list_icon = EditorInterface.get_editor_theme().get_icon("AnimationTrackList", "EditorIcons")
	return [list_icon]

func _set_draw_list_lines(state:bool):
	_alt_list_color = state
	item_list.draw_alternate_line_colors = _alt_list_color
	item_list.queue_redraw()
	tree.draw_alternate_line_colors = _alt_list_color
	tree.queue_redraw()
	miller.set_alt_list_colors(_alt_list_color)


func _set_preview_icons():
	tree.show_item_preview = not tree.show_item_preview
	tree.queue_force_refresh()
	tree.refresh()


func _set_search_view(search_view:SearchView):
	_current_search_view = search_view
	if _current_browser_state == BrowserState.SEARCH:
		_set_filter_texts()

func _tree_view_with_split_mode():
	return _current_view_mode == ViewMode.TREE and _current_split_mode != SplitMode.NONE

func _tree_view_dir_search():
	return _tree_view_with_split_mode() and _search_tree_list_dir

func check_toolbar_elements():
	_toolbar_debounce_timer.start(0.2)

func _on_toolbar_debounce_timeout() -> void:
	_check_toolbar_elements()

func _check_toolbar_elements():
	var elements = [path_bar, search_label]
	var _show_tool_bar = true
	for e in elements:
		if e.visible:
			_show_tool_bar = false
			break
	tool_bar_spacer.visible = _show_tool_bar
	
	var show_sep = false
	for control in tool_bar_hbox.get_children():
		if control is VSeparator:
			control.visible = show_sep
			show_sep = false
			continue
		if control.visible and control != tool_bar_spacer:
			#show_sep = true #^ not sure about the seperators
			pass
	
	if search_hbox.visible:
		var _show_search = false
		for f in filters:
			if f.visible:
				_show_search = true
				break
		_search_bar_spacer.visible = not _show_search
		if file_type_filter.visible:
			_show_search = true
		search_hbox.visible = _show_search
	
	var show_buttons = true
	if size.x < 500 * EditorInterface.get_editor_scale():
		show_buttons = false
	
	_toggle_element_respect_meta(_toggle_places_button, show_buttons)
	#_toggle_element_respect_meta(_toggle_path_button, show_buttons)
	#_toggle_element_respect_meta(_history_back_button, show_buttons)
	#_toggle_element_respect_meta(_history_forward_button, show_buttons)
	#_toggle_element_respect_meta(_search_button, show_buttons)
	_toggle_element_respect_meta(_navigate_up_button, show_buttons)
	_toggle_element_respect_meta(_tree_button, show_buttons)
	_toggle_element_respect_meta(_places_button, show_buttons)
	_toggle_element_respect_meta(_miller_button, show_buttons)

func _on_places_toggled_pressed():
	_places_toggled = not _places_toggled
	places.visible = _places_toggled
	_write_view_data_var(DataKeys.PLACES_TOGGLED, _places_toggled)
	places.set_active(_places_toggled)
	_check_main_split_vis()


func _on_navigate_up():
	if current_path == FAVORITES_META:
		return
	if FSUtil.is_root_folder(current_dir):
		return
	var dir = UFile.get_dir(current_dir)
	_set_current_path(_navigate_up_button, dir)

func _on_path_bar_button_pressed(show_hide:=false):
	if show_hide:
		_toggle_element(path_bar, not path_bar.visible)
	else:
		if not path_bar.visible:
			_toggle_element(path_bar, true)
		else:
			path_bar.toggle_view_mode()
	_check_toolbar_elements()

func _on_search_scope_pressed():
	_search_whole_filesystem = not _search_whole_filesystem
	_set_search_scope()
	if _current_browser_state == BrowserState.SEARCH:
		_restart_search()

func _set_search_scope():
	var icon
	var tooltip = ""
	if _search_whole_filesystem:
		icon = EditorInterface.get_editor_theme().get_icon("Filesystem", "EditorIcons")
		tooltip = "Search whole file system."
	else:
		icon = EditorInterface.get_editor_theme().get_icon("Folder", "EditorIcons")
		tooltip = "Search from current directory."
	_search_scope_button.icon = icon
	_search_scope_button.tooltip_text = tooltip

func _on_search_pressed():
	_set_search_visible(not search_hbox.visible)

func _set_search_visible(state:bool=search_hbox.visible):
	if not state:
		file_type_filter.select(0)
		_on_filter_type_selected(0)
		for f in filters:
			f.clear()
		search_hbox.visible = false
		return
	search_hbox.visible = true
	var has_visible = false
	for f in filters:
		if f.visible:
			has_visible = true
			break
	
	if not has_visible:
		var unhidden_filters = []
		for f in filters:
			var _hidden = _get_hidden_meta(f)
			if not _hidden:
				unhidden_filters.append(f)
		if unhidden_filters.is_empty() and not file_type_filter.visible:
			unhidden_filters = [filters[0]]
		for f in unhidden_filters:
			f.show()
			_set_hidden_meta(f, true)
	
	_check_toolbar_elements()

func _toggle_element_respect_meta(control:Control, toggled:bool):
	var meta = _get_hidden_meta(control)
	if toggled:
		if meta:
			return
		control.show()
	else:
		control.hide()

func _toggle_element(control:Control, toggled:bool):
	control.visible = toggled
	_set_hidden_meta(control, toggled)
	_check_toolbar_elements()

func _set_hidden_meta(control:Control, is_vis:bool):
	if is_vis:
		control.set_meta(&"hidden_element", null)
	else:
		control.set_meta(&"hidden_element", true)

func _get_hidden_meta(control:Control):
	return control.get_meta(&"hidden_element", false)

func _on_togglable_gui_input(event:InputEvent, control:Control):
	if event is InputEventMouseButton:
		if event.button_mask == 2:
			if control is LineEdit:
				var control_rect = control.get_rect()
				var icon_size
				if control.right_icon:
					icon_size = control.right_icon.get_size()
				else:
					icon_size = Vector2(16, control_rect.size.y)
				var icon_rect = control_rect
				icon_rect.position.x = icon_rect.size.x - icon_size.x
				icon_rect.size.x = icon_size.x
				if not icon_rect.has_point(event.position):
					return
			
			var icon = EditorInterface.get_editor_theme().get_icon("GuiVisibilityHidden", "EditorIcons")
			var options = RightClickHandler.Options.new()
			options.add_option("Hide", _toggle_element.bind(control, false),[icon])
			right_click_handler.display_popup(options)
			if control is LineEdit:
				control.context_menu_enabled = false
				await right_click_handler.popup_hidden
				control.context_menu_enabled = true

func _get_hidden_element_options():
	var options = RightClickHandler.Options.new()
	var element_icon = EditorInterface.get_editor_theme().get_icon("GuiVisibilityVisible", "EditorIcons")
	for element in togglable_elements:
		var meta = _get_hidden_meta(element)
		if not meta:
			continue
		var _class = element.get_class()
		var msg = "Element/Show %s (%s)" % [element.name, _class]
		var class_icon = EditorInterface.get_editor_theme().get_icon(_class, "EditorIcons")
		options.add_option(msg, _toggle_element.bind(element, true), [element_icon, class_icon])
	return options

func _get_hidden_element_names():
	var elements = []
	for element in togglable_elements:
		var meta = _get_hidden_meta(element)
		if not meta:
			continue
		elements.append(element.name)
	return elements

func _check_main_split_vis():
	tree_item_split.visible = tree.visible or places.visible
	right_side_vbox.visible = item_list.visible or miller.visible

func _build_nodes():
	if is_instance_valid(tree):
		return
	
	_toolbar_debounce_timer = Timer.new()
	add_child(_toolbar_debounce_timer)
	_toolbar_debounce_timer.timeout.connect(_on_toolbar_debounce_timeout)
	_toolbar_debounce_timer.one_shot = true
	
	_filter_timer = Timer.new()
	add_child(_filter_timer)
	_filter_timer.timeout.connect(_set_filter_texts)
	_filter_timer.one_shot = true
	
	right_click_handler = RightClickHandler.new()
	add_child(right_click_handler)
	
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	
	tool_bar_hbox = HBoxContainer.new()
	add_child(tool_bar_hbox)
	tool_bar_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_bar_hbox.resized.connect(check_toolbar_elements)
	
	_toggle_places_button = _new_button(true, "Favorites", _on_places_toggled_pressed, "Toggle Side Bar", false, "Toggle side bar.")
	tool_bar_hbox.add_child(_toggle_places_button) #^ not sure about this, dont want to toggle in other modes
	
	var sep_1 = VSeparator.new()
	tool_bar_hbox.add_child(sep_1)
	sep_1.hide()
	
	_history_back_button = _new_button(true, "Back", _history_back, "History Back", false, "Navigate to previous location.")
	tool_bar_hbox.add_child(_history_back_button)
	#_history_back_button.flat = true
	
	_history_forward_button = _new_button(true, "Forward", _history_forward, "History Forward", false, "Navigate to next location.")
	tool_bar_hbox.add_child(_history_forward_button)
	#_history_forward_button.flat = true
	
	_navigate_up_button = _new_button(true, "MoveUp",_on_navigate_up, "Navigate Up", false, "Navigate up one folder level.")
	tool_bar_hbox.add_child(_navigate_up_button)
	
	_toggle_path_button = _new_button(true,"CopyNodePath", _on_path_bar_button_pressed, "Path Toggle", false, "Toggle path bar to line edit or buttons.")
	tool_bar_hbox.add_child(_toggle_path_button)
	
	path_bar = FileSystemPathBar.new()
	tool_bar_hbox.add_child(path_bar)
	path_bar.name = "Path Bar"
	
	search_label = Label.new()
	tool_bar_hbox.add_child(search_label)
	search_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_label.clip_text = true
	search_label.mouse_filter = Control.MOUSE_FILTER_STOP
	#search_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	search_label.hide()
	
	tool_bar_spacer = Control.new()
	tool_bar_hbox.add_child(tool_bar_spacer)
	tool_bar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#tool_bar_spacer.hide()
	
	search_hbox = HBoxContainer.new()
	add_child(search_hbox)
	search_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_hbox.hide()
	
	_search_scope_button = _new_button(true,  "Filesystem", _on_search_scope_pressed, "Search Scope", false, "")
	search_hbox.add_child(_search_scope_button)
	
	_search_bar_spacer = Control.new()
	search_hbox.add_child(_search_bar_spacer)
	_search_bar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_bar_spacer.hide()
	
	var line_edit = LineEdit.new()
	line_edit.clear_button_enabled = true
	search_hbox.add_child(line_edit)
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.name = "Filter 1"
	line_edit.right_icon = EditorInterface.get_base_control().get_theme_icon("Search", "EditorIcons")
	line_edit.placeholder_text = "Filter Files"
	line_edit.text_changed.connect(_on_filter_text_changed)
	
	var line_edit_2  = LineEdit.new()
	line_edit_2.clear_button_enabled = true
	search_hbox.add_child(line_edit_2)
	line_edit_2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit_2.name = "Filter 2"
	line_edit_2.right_icon = EditorInterface.get_base_control().get_theme_icon("Search", "EditorIcons")
	line_edit_2.placeholder_text = "Filter Files"
	line_edit_2.text_changed.connect(_on_filter_text_changed)
	
	filters = [line_edit, line_edit_2] #^r needs to move
	for f:LineEdit in filters:
		f.visibility_changed.connect(func():if not f.visible:f.clear(), 1)
	
	
	
	
	file_type_filter = OptionButton.new()
	search_hbox.add_child(file_type_filter)
	file_type_filter.theme_type_variation = "FlatButton"
	file_type_filter.alignment = HORIZONTAL_ALIGNMENT_CENTER
	file_type_filter.item_selected.connect(_on_filter_type_selected)
	file_type_filter.allow_reselect = true
	file_type_filter.focus_mode = Control.FOCUS_NONE
	file_type_filter.name = "File Type Filter"
	file_type_filter.add_icon_item(EditorInterface.get_editor_theme().get_icon("FilenameFilter", "EditorIcons"), _NO_FILTER_NAME)
	file_type_filter.add_icon_item(EditorInterface.get_editor_theme().get_icon("File", "EditorIcons"), "All")
	for _name in FSFilter.Types.get_categories():
		var icon = EditorInterface.get_editor_theme().get_icon(FSFilter.Types.get_icon(_name), "EditorIcons")
		file_type_filter.add_icon_item(icon, _name)
	
	var sep_2 = VSeparator.new()
	tool_bar_hbox.add_child(sep_2)
	sep_2.hide()
	
	_tree_button = _new_button(true, _tree_icon(), _change_view_mode.bind(ViewMode.TREE), "Tree View", false, "Switch to Tree view.")
	tool_bar_hbox.add_child(_tree_button)
	
	_places_button = _new_button(true, _places_icon(), _change_view_mode.bind(ViewMode.PLACES), "Places View", true, "Switch to Item List view.")
	tool_bar_hbox.add_child(_places_button)
	
	_miller_button = _new_button(true, _miller_icon(), _change_view_mode.bind(ViewMode.MILLER), "Column View", true, "Switch to Column view.")
	tool_bar_hbox.add_child(_miller_button)
	
	_search_button = _new_button(true,"Search", _on_search_pressed, "Search Toggle", false, "Toggle search bar.")
	tool_bar_hbox.add_child(_search_button)
	
	options_button = _new_button(false, "TripleBar", _on_options_button_pressed, "", false, "Display options popup.")
	tool_bar_hbox.add_child(options_button)
	
	#^ split
	main_split_container = SplitContainer.new()
	add_child(main_split_container)
	main_split_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	places = FileSystemPlaces.new()
	main_split_container.add_child(places)
	
	#^ tree side
	tree_item_split = SplitContainer.new()
	tree_item_split.vertical = false
	main_split_container.add_child(tree_item_split)
	UControl.expand(tree_item_split)
	
	
	tree = FileSystemTree.new()
	tree_item_split.add_child(tree)
	
	#^ split side
	right_side_vbox = VBoxContainer.new()
	tree_item_split.add_child(right_side_vbox)
	UControl.expand(right_side_vbox)
	
	item_list = FileSystemItemList.new()
	right_side_vbox.add_child(item_list)
	right_side_vbox.custom_minimum_size = Vector2(100,100)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	miller = FileSystemMiller.new()
	right_side_vbox.add_child(miller)
	
	preview_panel = FSClasses.PreviewPanel.new()
	main_split_container.add_child(preview_panel)
	preview_panel.hide()
	preview_panel.custom_minimum_size = Vector2(64 * EditorInterface.get_editor_scale(), 0)
	
	non_res_helper = NonResHelper.new()
	non_res_helper.places = places
	
	fs_popup_handler = FSPopupHandler.new()
	add_child(fs_popup_handler)
	fs_popup_handler.filesystem_tab = self
	fs_popup_handler.tree = tree
	fs_popup_handler.item_list = item_list
	fs_popup_handler.places = places
	
	fs_popup_handler.new_tab.connect(_on_rc_new_tab)
	
	item_list.navigate_up.connect(_on_navigate_up)
	
	path_bar.path_selected.connect(_on_path_bar_path_selected)
	places.path_selected.connect(_on_places_path_selected)
	
	tree.left_clicked.connect(_on_tree_item_selected)
	item_list.left_clicked.connect(_on_item_list_item_selected)
	miller.left_clicked.connect(_on_miller_path_selected)
	
	tree.double_clicked.connect(_on_double_clicked)
	miller.double_clicked.connect(_on_double_clicked)
	item_list.double_clicked.connect(_on_item_list_double_clicked)
	
	path_bar.right_clicked.connect(_on_path_bar_right_clicked)
	places.right_clicked.connect(_on_places_right_clicked)
	tree.right_clicked.connect(_on_item_right_clicked)
	item_list.right_clicked.connect(_on_item_right_clicked)
	item_list.right_clicked_empty.connect(_on_item_right_clicked_empty)
	miller.right_clicked.connect(_on_item_right_clicked)
	
	places.title_right_clicked.connect(_on_places_title_right_clicked)
	
	togglable_elements.append_array([
		line_edit,
		line_edit_2,
		file_type_filter
	])
	
	line_edit.hide()
	_toggle_element(line_edit_2, false)
	for e in togglable_elements:
		e.gui_input.connect(_on_togglable_gui_input.bind(e))
	
	_deferred_build_nodes.call_deferred()

func _deferred_build_nodes():
	search_label.custom_minimum_size.y = path_bar.size.y
	tool_bar_hbox.custom_minimum_size.y = path_bar.line_edit.size.y


func _new_button(hideable:=false, icon="", callable=null, _name="", icon_color:=false, tooltip:=""):
	var button = Button.new()
	if _name != "":
		button.name = _name
	if callable != null:
		button.pressed.connect(callable)
	if hideable:
		togglable_elements.append(button)
	if icon is Texture2D:
		button.icon = icon
	elif icon != "":
		var icon_texture
		if icon_color:
			icon_texture = _get_modulated_icon(icon)
		else:
			icon_texture = EditorInterface.get_editor_theme().get_icon(icon, "EditorIcons")
		button.icon = icon_texture
	
	button.tooltip_text = tooltip
	button.theme_type_variation = &"FlatButton"
	button.focus_mode = Control.FOCUS_NONE
	return button

func _tree_icon():
	return "FileTree"
	#return _get_modulated_icon("FileTree")
func _places_icon():
	return _get_modulated_icon("ItemList")
func _miller_icon():
	return _get_modulated_icon("HBoxContainer")


func _get_modulated_icon(text: String, brightness:=0.8) -> Texture2D:
	return EditorIcons.get_icon_white(text, brightness)

class EditorSet:
	const _DEFAULT_SETTINGS:StringName = &"plugin/filesystem_instances/defaults/"
	const LIST_ALT_COLOR = _DEFAULT_SETTINGS + &"alternate_item_colors"
	const VIEW_MODE = _DEFAULT_SETTINGS + &"view_mode"
	
	const _DEFAULTS = {
		LIST_ALT_COLOR: false,
		VIEW_MODE: 0
	}
	
	static func ensure_settings():
		var ed_settings = EditorInterface.get_editor_settings()
		for setting in _DEFAULTS.keys():
			if not ed_settings.has_setting(setting):
				ed_settings.set_setting(setting, _DEFAULTS[setting])
	
		var view_mode = {
			&"name": VIEW_MODE,
			&"type": TYPE_INT, # (2)
			&"hint": PROPERTY_HINT_ENUM, # (2)
			&"hint_string": "Tree,Items,Columns",
		}
		ed_settings.add_property_info(view_mode)
	
	

class DataKeys:
	const ROOT = &"ROOT"
	const CURRENT_PATH = &"CURRENT_PATH"
	const SPLIT_MODE = &"SPLIT_MODE"
	const SPLIT_OFFSET = &"SPLIT_OFFSET"
	
	const TOGGLED_ELEMENTS = &"TOGGLED_ELEMENTS"
	const RECENT_FILES = &"RECENT_FILES"
	
	const SEARCH_VISIBLE = &"SEARCH_VISIBLE"
	const SEARCH_SELECT_PATH = &"SEARCH_SELECT_PATH"
	const SEARCH_WHOLE_FS = &"SEARCH_WHOLE_FS"
	const SEARCH_VIEW = &"SEARCH_VIEW"
	
	#const TREE_SCROLL_OFFSET = &"filesystem_tab.data_keys.tree_scroll_offset"
	const TREE_ITEM_META = &"TREE_ITEM_META"
	const TREE_PREVIEW_ICONS = &"TREE_PREVIEW_ICONS"
	const TREE_SEARCH_LIST_DIR = &"TREE_SEARCH_LIST_DIR"
	
	const ITEM_DISPLAY_LIST = &"ITEM_DISPLAY_LIST"
	
	const PATH_BAR_MODE = &"PATH_BAR_MODE"
	const PATH_BAR_TOGGLED = &"PATH_BAR_TOGGLED"
	const PLACES_TOGGLED = &"PLACES_TOGGLED"
	const PLACES_TOGGLED_FOLLOW = &"PLACES_TOGGLED_FOLLOW"
	const FILTER_MODE = &"FILTER_MODE"
	const FILTER_MODE_FOLLOW = &"FILTER_MODE_FOLLOW"
	const LIST_ALT_COLOR = &"LIST_ALT_COLOR"
	
	const SIGNAL_BUSSES = &"filesystem_tab.data_keys.signal_busses"
	
	const VIEW_MODE = &"VIEW_MODE"
	const VIEW_DATA = &"VIEW_DATA"
	const VIEW_DATA_TREE = &"VIEW_DATA_TREE"
	const VIEW_DATA_PLACES = &"VIEW_DATA_PLACES"
	const VIEW_DATA_MILLER = &"VIEW_DATA_MILLER"
	
	const GLOBAL_NEW_WINDOW_SIGNAL = &"FI_GLOBAL_NEW_WINDOW_SIGNAL"
	const GLOBAL_NEW_SPLIT_SIGNAL = &"FI_GLOBAL_NEW_SPLIT_SIGNAL"
