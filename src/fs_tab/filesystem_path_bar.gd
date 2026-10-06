@tool
extends Control

const FSClasses = preload("res://addons/addon_lib/editor_filesystem/src/util/fs_classes.gd")
const FSUtil = FSClasses.FSUtil

const PathBar = preload("uid://bw2knsytgo0vu") #! resolve ALibRuntime.UICustom.PathBar

const UFile = FSUtil.UFile
const UVersion = FSUtil.UVersion

signal path_selected(path:String)
signal right_clicked(path:String)

static var _style_boxes = {}

var path_in_res:=true

var path_bar:PathBar

var tab_bar:TabBar
var scroll_container:ScrollContainer # DEPRECATED ??
var line_edit:LineEdit
var button_hbox:HBoxContainer

var _history_path := ""
var _current_dir := ""

var _bar_view:=0

func _ready() -> void:
	if is_part_of_edited_scene():
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	
	#tab_bar = TabBar.new()
	#add_child(tab_bar)
	#tab_bar.tab_clicked.connect(_on_tab_bar_pressed)
	#tab_bar.tab_rmb_clicked.connect(_on_tab_bar_right_clicked)
	#tab_bar.select_with_rmb = true
	#tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#tab_bar.focus_mode = Control.FOCUS_NONE
	#tab_bar.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	#
	#_set_style_boxes(tab_bar)
	
	path_bar = PathBar.new()
	add_child(path_bar)
	path_bar.section_pressed.connect(_on_section_pressed)
	path_bar.section_right_clicked.connect(_on_section_right_clicked)
	path_bar.select_on_right_click = true
	path_bar.show_arrows = false
	path_bar.custom_minimum_size.y = 24 * EditorInterface.get_editor_scale()
	path_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	
	line_edit = LineEdit.new()
	add_child(line_edit)
	line_edit.text_submitted.connect(_on_line_edit_text_submitted)
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#line_edit.expand_to_text_length = true
	line_edit.custom_minimum_size.y =  24 * EditorInterface.get_editor_scale()
	line_edit.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	line_edit.hide()
	
	set_current_dir("res://")
	
	
	await get_tree().process_frame
	#line_edit.custom_minimum_size.y = tab_bar.size.y

func set_current_path(path:String):
	set_current_dir(path)


func set_current_dir(path:String):
	if path == "FAVORITES":
		return
	if path == _current_dir:
		return
	
	_current_dir = path
	line_edit.text = _current_dir
	var path_to_display = _current_dir
	var current_dir = _current_dir
	if not DirAccess.dir_exists_absolute(current_dir):
		current_dir = current_dir.get_base_dir()
	if not current_dir.ends_with("/"):
		current_dir += "/"
	
	var path_is_ancestor = UFile.is_dir_in_or_equal_to_dir(_history_path, _current_dir)
	if path_is_ancestor and FSUtil.paths_have_same_root(_history_path, _current_dir):
		_select_section_by_path(current_dir)
		return
	else:
		path_bar.clear()
		_history_path = _current_dir
	
	
	
	var path_prefix = path_to_display.get_slice("://", 0)
	var path_parts = path_to_display.get_slice("://", 1)
	var parts = path_parts.split("/", false)
	var working_path = path_prefix + "://"
	
	if path_in_res or path_to_display.find("://") > -1:
		path_bar.add_section(working_path)
		path_bar.set_section_metadata(0, working_path)
	else:
		parts = path_to_display.split("/", false)
		working_path = "/" # this needs an os get root thing?
		path_bar.add_section("/")
		path_bar.set_section_metadata(0, working_path)
	
	var current_tab = 0
	for i in range(parts.size()):
		var part = parts[i]
		working_path = working_path.path_join(part)
		var is_dir = DirAccess.dir_exists_absolute(working_path)
		if not is_dir:
			break
		if is_dir:
			working_path += "/"
		if working_path == current_dir:
			current_tab = i + 1 # due to prefix being 0
		path_bar.add_section(part)
		path_bar.set_section_metadata(i + 1, working_path)
	
	#path_bar.select_section(current_tab)
	path_bar.select_section(path_bar.get_section_count() - 1)

func _select_section_by_path(path:String):
	for i in range(path_bar.get_section_count()):
		var meta_path = path_bar.get_section_metadata(i)
		if meta_path == path:
			path_bar.select_section(i)
			break

func _on_section_pressed(idx:int):
	var path = path_bar.get_section_metadata(idx)
	path_selected.emit(path)

func _on_section_right_clicked(idx) -> void:
	var path = path_bar.get_section_metadata(idx)
	right_clicked.emit(path)

func _on_line_edit_text_submitted(new_text:String):
	if not DirAccess.dir_exists_absolute(new_text) and not FileAccess.file_exists(new_text):
		line_edit.text = _current_dir
		line_edit.grab_focus()
		return
	
	if DirAccess.dir_exists_absolute(new_text):
		if not new_text.ends_with("/"):
			new_text += "/"
		line_edit.text = new_text
	path_selected.emit(new_text)

func toggle_view_mode():
	_bar_view += 1
	#if _bar_view > 2:
	if _bar_view > 1:
		_bar_view = 0
	set_view_mode(_bar_view)

func get_view_mode():
	return _bar_view

func set_view_mode(mode:int):
	_bar_view = mode
	if _bar_view == 0:
		path_bar.show()
		line_edit.hide()
	elif _bar_view == 1:
		path_bar.hide()
		line_edit.show()





#func set_current_dir(path:String):
	#if path == "FAVORITES":
		#return
	#if path == _current_dir:
		#return
	#
	#_current_dir = path
	#line_edit.text = _current_dir
	#var path_to_display = _current_dir
	#var current_dir = _current_dir
	#if not DirAccess.dir_exists_absolute(current_dir):
		#current_dir = current_dir.get_base_dir()
	#if not current_dir.ends_with("/"):
		#current_dir += "/"
	#
	#var path_is_ancestor = UFile.is_dir_in_or_equal_to_dir(_history_path, _current_dir)
	#if path_is_ancestor and FSUtil.paths_have_same_root(_history_path, _current_dir):
		#_select_tab_by_path(current_dir)
		#return
	#else:
		#tab_bar.clear_tabs()
		#_history_path = _current_dir
	#
	#
	#
	#var path_prefix = path_to_display.get_slice("://", 0)
	#var path_parts = path_to_display.get_slice("://", 1)
	#var parts = path_parts.split("/", false)
	#var working_path = path_prefix + "://"
	#
	#if path_in_res or path_to_display.find("://") > -1:
		#tab_bar.add_tab(working_path)
		#tab_bar.set_tab_metadata(0, working_path)
	#else:
		#parts = path_to_display.split("/", false)
		#working_path = "/" # this needs an os get root thing?
		#tab_bar.add_tab("/")
		#tab_bar.set_tab_metadata(0, working_path)
	#
	#var current_tab = 0
	#for i in range(parts.size()):
		#var part = parts[i]
		#working_path = working_path.path_join(part)
		#var is_dir = DirAccess.dir_exists_absolute(working_path)
		#if not is_dir:
			#break
		#if is_dir:
			#working_path += "/"
		#if working_path == current_dir:
			#current_tab = i + 1 # due to prefix being 0
		#tab_bar.add_tab(part)
		#tab_bar.set_tab_metadata(i + 1, working_path)
	#
	#tab_bar.current_tab = current_tab
#
#func _select_tab_by_path(path:String):
	#for i in range(tab_bar.tab_count):
		#var meta_path = tab_bar.get_tab_metadata(i)
		#if meta_path == path:
			#tab_bar.current_tab = i
			#break
#
#func _on_tab_bar_pressed(idx:int):
	#var path = tab_bar.get_tab_metadata(idx)
	#path_selected.emit(path)
#
#func _on_tab_bar_right_clicked(idx) -> void:
	#var path = tab_bar.get_tab_metadata(idx)
	#right_clicked.emit(path)
#
#func _on_line_edit_text_submitted(new_text:String):
	#if not DirAccess.dir_exists_absolute(new_text) and not FileAccess.file_exists(new_text):
		#line_edit.text = _current_dir
		#line_edit.grab_focus()
		#return
	#
	#if DirAccess.dir_exists_absolute(new_text):
		#if not new_text.ends_with("/"):
			#new_text += "/"
		#line_edit.text = new_text
	#path_selected.emit(new_text)
#
#func toggle_view_mode():
	#_bar_view += 1
	##if _bar_view > 2:
	#if _bar_view > 1:
		#_bar_view = 0
	#set_view_mode(_bar_view)
#
#func get_view_mode():
	#return _bar_view
#
#func set_view_mode(mode:int):
	#_bar_view = mode
	#if _bar_view == 0:
		#tab_bar.show()
		#line_edit.hide()
	#elif _bar_view == 1:
		#tab_bar.hide()
		#line_edit.show()


func _set_style_boxes(_tab_bar:TabBar):
	var version = UVersion.get_minor_version()
	var sbs = ["tab_selected", "tab_unselected", "tab_hovered", "tab_focus", "tab_disabled"]
	for _name in sbs:
		var sb
		if version < 6:
			sb = _get_style_box_44(_name)
		else: #elif version <= 7:
			sb = _get_style_box_46(_name)
		_tab_bar.add_theme_stylebox_override(_name, sb)
	

func _get_style_box_44(_name:String):
	if _style_boxes == null:
		_style_boxes = {}
	if _style_boxes.has(_name):
		return _style_boxes[_name]
	var sb = tab_bar.get_theme_stylebox(_name).duplicate() as StyleBoxFlat
	sb.border_width_right = 2
	sb.border_color = Color.TRANSPARENT
	if _name == "tab_selected":
		sb.border_width_top = 0
		sb.bg_color = sb.bg_color.darkened(0.5)
	_style_boxes[_name] = sb
	return sb

func _get_style_box_46(_name:String):
	if _style_boxes == null:
		_style_boxes = {}
	if _style_boxes.has(_name):
		return _style_boxes[_name]
	var sb = tab_bar.get_theme_stylebox(_name).duplicate() as StyleBoxFlat
	sb.set_content_margin_all(7)
	sb.content_margin_right += 3
	sb.border_width_right = 3
	sb.border_color = Color.TRANSPARENT
	sb.set_corner_radius_all(0)
	if _name == "tab_selected":
		sb.border_width_top = 0
		sb.bg_color = sb.bg_color.darkened(0.2)
	_style_boxes[_name] = sb
	return sb
