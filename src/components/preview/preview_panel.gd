extends Control

#! import_p UControl

const UControl = preload("uid://cdo8rcof3ilt1") #! resolve UtilR.Nodes.UControl
const PluginButton = preload("uid://redtm8tuamgm") #! resolve UIPlugin.PluginButton
const TextViewer = preload("uid://pkyepa1hmp4") #! resolve ResourceView.TextViewer
const MaterialViewer = preload("uid://bmf1icbgkjsjx") #! resolve ResourceView.MaterialViewer
const SceneViewer = preload("uid://crni663ngyj7x") #! resolve ResourceView.SceneViewer


const TEXT_FILE_TYPES = [
	"txt", "md", "cfg", "ini", "log", "json", "yml", "yaml", "toml", "xml", # std text types
	"gdsh", # editor console
	"gd", "cs", # script types too
	]

# Scenes and models wait for the Instance button unless their auto-instance option is on.
const SCENE_TYPES = ["tscn", "scn"]
const MODEL_TYPES = ["glb", "gltf", "fbx", "obj"]
const MODELS_OPTION = "Models"
## Offered as "Preview/Instance <option>". Root types match scenes of or inheriting them.
const AUTO_INSTANCE_OPTIONS = ["Node3D", "Control", MODELS_OPTION]

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
var _scene_preview:SceneViewer
var _scene_instance_prompt:VBoxContainer
var _instance_button:Button
var _pending_root_type:String
var _pending_kind:SceneViewer.Kind = SceneViewer.Kind.NONE
var _pending_is_model:bool
var _material_preview:MaterialViewer
var _texture_preview:TextureRect
var _audio_preview

# Session-only, per tab: never written to dock data.
var _auto_instance:Dictionary = {MODELS_OPTION: true}


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

	_scene_preview = SceneViewer.new()
	_init_viewer(_scene_preview)
	_scene_preview.activate_path_callable = FileSystemSingleton.activate_path
	_scene_preview.navigate_path_callable = FileSystemSingleton.navigate_to_path
	_scene_preview.tooltip_callable = FileSystemSingleton.get_custom_tooltip

	_scene_instance_prompt = VBoxContainer.new()
	_init_viewer(_scene_instance_prompt)
	var prompt_icon = TextureRect.new()
	_scene_instance_prompt.add_child(prompt_icon)
	UControl.expand(prompt_icon)
	prompt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prompt_icon.texture = EditorInterface.get_editor_theme().get_icon(&"FileBigThumb", &"EditorIcons")
	var instance_button_builder = PluginButton.new(&"PackedScene", _instance_pending_scene)
	instance_button_builder.theme_type_variation = &"" # not flat; it's the primary action here
	_instance_button = instance_button_builder.get_button()
	_instance_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_scene_instance_prompt.add_child(_instance_button)


func clear():
	hide()
	active_preview_path = ""
	_remove_current_viewer()

func _remove_current_viewer():
	if _preview_vbox.get_child_count() > 0:
		for c in _preview_vbox.get_children():
			_preview_vbox.remove_child(c)
	# Free the instanced scene rather than keep it alive while detached.
	_scene_preview.clear()

func preview_file(path:String):
	if path == active_preview_path:
		return
	active_preview_path = path
	var file_type = "Folder" if path.ends_with("/") else FileSystemSingleton.get_file_type_static(path)
	_details_vbox.set_file(path, file_type)
	_remove_current_viewer()
	_get_viewer(path, file_type)


func is_auto_instance(option:String) -> bool:
	return _auto_instance.get(option, false)

func toggle_auto_instance(option:String) -> void:
	_auto_instance[option] = not is_auto_instance(option)
	# Enabling an option while its prompt is showing instances that file right away.
	if _scene_instance_prompt.is_inside_tree() and _should_auto_instance():
		_instance_pending_scene()


func _get_viewer(path:String, file_type:String):
	_texture_preview.modulate = Color.WHITE # reset if folder changed it
	var ext = path.get_extension()
	if ext in TEXT_FILE_TYPES:
		_add_viewer(_text_preview)
		_text_preview.set_path(path)
	elif ext in SCENE_TYPES or ext in MODEL_TYPES:
		_pending_is_model = ext in MODEL_TYPES
		if _pending_is_model:
			_pending_root_type = ""
			_pending_kind = SceneViewer.Kind.SCENE_3D
		else:
			_pending_root_type = SceneViewer.get_root_type(path)
			_pending_kind = SceneViewer.get_kind(_pending_root_type)
		if _should_auto_instance():
			_instance_pending_scene()
		else:
			_show_instance_prompt()
	elif ClassDB.is_parent_class(file_type, "Mesh"):
		_add_viewer(_scene_preview)
		_scene_preview.show_3d([path])
	elif file_type in TEXTURE_FILE_TYPES:
		_add_viewer(_texture_preview)
		var texture = load(path)
		_texture_preview.texture = texture
	elif file_type in MATERIAL_FILE_TYPES:
		_add_viewer(_material_preview)
		_material_preview.set_material_path(path)
	else:
		_show_file_icon(path)

func _show_file_icon(path:String):
	_add_viewer(_texture_preview)
	if path.ends_with("/"):
		_texture_preview.texture = EditorInterface.get_editor_theme().get_icon(&"FolderBigThumb", &"EditorIcons")
		_texture_preview.modulate = FileSystemSingleton.get_instance().get_folder_color(path)
	else:
		_texture_preview.texture = EditorInterface.get_editor_theme().get_icon(&"FileBigThumb", &"EditorIcons")

func _add_viewer(control:Control):
	_preview_vbox.add_child(control)

func _instance_pending_scene():
	_remove_current_viewer()
	# Added first: the 2D view only instances while inside the tree.
	_add_viewer(_scene_preview)
	_scene_preview.show_scene(active_preview_path, _pending_kind)

# Unpreviewable roots still get the button, disabled, so the root type explains why.
func _show_instance_prompt():
	var label = "Model" if _pending_is_model else _pending_root_type
	if label.is_empty():
		label = "Unknown" # binary .scn, or no root node found
	var can_instance = _pending_kind != SceneViewer.Kind.NONE
	_instance_button.text = "Instance (%s)" % label
	_instance_button.disabled = not can_instance
	_instance_button.tooltip_text = "" if can_instance else "%s roots can't be previewed." % label
	_add_viewer(_scene_instance_prompt)

func _should_auto_instance() -> bool:
	if _pending_kind == SceneViewer.Kind.NONE:
		return false
	if _pending_is_model:
		return is_auto_instance(MODELS_OPTION)
	for option in _auto_instance:
		if option != MODELS_OPTION and _auto_instance[option] and ClassDB.is_parent_class(_pending_root_type, option):
			return true
	return false

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
