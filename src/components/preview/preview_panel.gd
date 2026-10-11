extends Control

#! import_p UControl

const SceneReadFile = preload("uid://dr3oreheg7dr0") #! resolve ALibRuntime.Utils.UResource.UPackedScene.ReadFile
const UControl = preload("uid://brio73mirr5e6") #! resolve ALibRuntime.Utils.UControl

const PluginButton = preload("uid://redtm8tuamgm") #! resolve UIPlugin.PluginButton

const TextViewer = preload("res://addons/_lib/editor_filesystem/src/components/preview/viewers/text.gd")
const MaterialViewer = preload("res://addons/_lib/editor_filesystem/src/components/preview/viewers/material_3d.gd")


const SceneViewer = preload("res://addons/_lib/brohd/alib_editor/misc/scene_viewer/scene_viewer.gd")


const TEXT_FILE_TYPES = [
	"txt", "md", "cfg", "ini", "log", "json", "yml", "yaml", "toml", "xml", # std text types
	"gdsh", # editor console
	"gd", "cs", # script types too
	]

const PACKED_SCENE_TYPES = [
	"tscn", "scn", "fbx", "gltf", "glb",
	"obj", # not scene but could be display somehow
]
const PACKED_SCENE_3D_ROOTS = [
	"Node3D", "MeshInstance3D", "StaticBody3D"
]

const TEXTURE_FILE_TYPES = [
	"CompressedTexture2D"
]

const MATERIAL_FILE_TYPES = [
	"StandardMaterial3D",
	"ORMMaterial3D",
	"ShaderMaterial",
]

var _main_vbox:VBoxContainer
var _preview_vbox:VBoxContainer
var _details_vbox:DetailsPanel


var active_preview_path:String

# content specific
var _text_preview:TextViewer
var _packed_scene_preview_3d:SceneViewer
var _material_preview:MaterialViewer
var _texture_preview:TextureRect
var _audio_preview


func _ready() -> void:
	# for header
	
	clip_contents = true
	
	_main_vbox = VBoxContainer.new()
	add_child(_main_vbox)
	_main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	_preview_vbox = VBoxContainer.new()
	_main_vbox.add_child(_preview_vbox)
	UControl.expand(_preview_vbox)
	
	_details_vbox = DetailsPanel.new()
	_main_vbox.add_child(_details_vbox)
	_details_vbox.close_button_pressed.connect(clear)
	
	_text_preview = TextViewer.new()
	_init_viewer(_text_preview)
	
	_material_preview = MaterialViewer.new()
	_init_viewer(_material_preview)
	
	_texture_preview = TextureRect.new()
	_init_viewer(_texture_preview)
	_texture_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	_packed_scene_preview_3d = SceneViewer.new()
	_init_viewer(_packed_scene_preview_3d)
	_packed_scene_preview_3d.set_panel_mode(SceneViewer.PanelMode.SINGLE)
	

func clear():
	hide()
	active_preview_path = ""
	_remove_current_viewer()

func _remove_current_viewer():
	if _preview_vbox.get_child_count() > 0:
		for c in _preview_vbox.get_children():
			_preview_vbox.remove_child(c)

func preview_file(path:String):
	if path == active_preview_path:
		return
	active_preview_path = path
	var file_type = "Folder" if path.ends_with("/") else FileSystemSingleton.get_file_type_static(path)
	_details_vbox.set_file(path, file_type)
	_remove_current_viewer()
	_get_viewer(path, file_type)




func _get_viewer(path:String, file_type:String):
	_texture_preview.modulate = Color.WHITE # reset if folder changed it
	print(file_type)
	var ext = path.get_extension()
	if ext in TEXT_FILE_TYPES:
		_add_viewer(_text_preview)
		_text_preview.set_path(path)
	elif ext in PACKED_SCENE_TYPES:
		if SceneReadFile.get_root_type(path) in PACKED_SCENE_3D_ROOTS:
			_add_viewer(_packed_scene_preview_3d)
			_packed_scene_preview_3d.set_scene_paths([path])
	elif ClassDB.is_parent_class(file_type, "Mesh"):
		_add_viewer(_packed_scene_preview_3d)
		_packed_scene_preview_3d.set_scene_paths([path])
	elif file_type in TEXTURE_FILE_TYPES:
		_add_viewer(_texture_preview)
		var texture = load(path)
		_texture_preview.texture = texture
	elif file_type in MATERIAL_FILE_TYPES:
		_add_viewer(_material_preview)
		_material_preview.set_material_path(path)
	else: # fallback
		_add_viewer(_texture_preview)
		if path.ends_with("/"):
			_texture_preview.texture = EditorInterface.get_editor_theme().get_icon(&"FolderBigThumb", &"EditorIcons")
			_texture_preview.modulate = FileSystemSingleton.get_instance().get_folder_color(path)
		else:
			_texture_preview.texture = EditorInterface.get_editor_theme().get_icon(&"FileBigThumb", &"EditorIcons")

func _add_viewer(control:Control):
	_preview_vbox.add_child(control)

class DetailsPanel extends VBoxContainer:
	
	var title_label:= Label.new()
	var file_type_label:= Label.new()
	var modified_label:= Label.new()
	var close_button:Button
	signal close_button_pressed
	
	func _ready() -> void:
		add_child(HSeparator.new())
		var title_hbox = HBoxContainer.new()
		add_child(title_hbox)
		title_hbox.add_child(title_label)
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		
		close_button = PluginButton.new("Close", func(): close_button_pressed.emit()).get_button()
		close_button.flat = true
		title_hbox.add_child(close_button)
		
		add_child(file_type_label)
		add_child(modified_label)
	
	func set_file(path:String, file_type:String):
		title_label.text = path.trim_suffix("/").get_file()
		
		file_type_label.text = file_type
		
		var mtime = Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path), true)
		modified_label.text = "Modified: %s" % mtime
		modified_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		pass

func _init_viewer(control:Control):
	UControl.expand(control)
	_preview_vbox.add_child(control)
	_preview_vbox.remove_child(control)
