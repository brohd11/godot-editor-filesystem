
#const FSClasses = preload("res://addons/addon_lib/editor_filesystem/src/util/fs_classes.gd")
#const FSUtil = preload("uid://c7yf322tn6f0b") #! resolve FSClasses.FSUtil

const UFile = preload("uid://bl33psa06nv1e") #! resolve ALibRuntime.Utils.UFile.Methods
const UResourceMethods = preload("uid://brjrqxh2smivn") #! resolve ALibRuntime.Utils.UResource.Methods
const GDFileRead = preload("uid://ms6j4bx7vbdr") #! resolve ALibRuntime.Utils.UGDScript.FileRead
const UPackedScene = preload("uid://44xrh5kbrpaa") #! resolve ALibRuntime.Utils.UResource.UPackedScene
const ImageSize = preload("uid://d0ld4o3cihtgv") #! resolve ALibRuntime.Utils.UResource.ImageSize
const Audio = preload("uid://dpo6b8yu8xpy2") #! resolve ALibRuntime.Utils.UResource.Audio


static func get_custom_tooltip(path: String) -> Object:
	var container = HBoxContainer.new()
	var label = Label.new()
	container.add_child(label)
	var _name = path.trim_suffix("/").get_file()
	if path.ends_with("/"):
		label.text = "%s\n%s" % [_name, path]
		var files_text = "\nFiles: %s Dirs: %s"
		var dir_contents = UFile.get_dir_contents(path)
		var raw_files = dir_contents.get("files", [])
		var files = []
		for f in raw_files:
			if not f.ends_with(".uid"):
				files.append(f)
		var dirs = dir_contents.get("dirs", [])
		if files.is_empty() and dirs.is_empty():
			files_text = ""
		else:
			files_text = files_text % [files.size(), dirs.size()]
		label.text += files_text
		# get other metadata? files
		return container
	
	if not FileSystemSingleton.is_path_valid_res(path):
		label.text = _get_non_res_details(path)
		return container
	
	var ext = _name.get_extension()
	
	var _size = UFile.get_file_size(path)
	var type = FileSystemSingleton.get_file_type_static(path)
	
	var label_text = "%s\nSize: %s\nType: %s" % [_name, _size, type]
	
	var uid = UFile.path_to_uid(path)
	if uid != path:
		label_text += "\n%s" % uid
	
	var file_specific = _get_file_specific_details(path)
	if file_specific:
		label_text += file_specific
	
	var type_specific = _get_type_specific_details(path, type)
	if type_specific:
		label_text += type_specific
	
	var preview = FileSystemSingleton.get_preview(path)
	if preview:
		var texture_rect = TextureRect.new()
		texture_rect.texture = preview.preview
		texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		texture_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		
		var texture_dimension = _get_texture_dimensions(path, type)
		if texture_dimension != Vector2i(-1, -1) and texture_dimension < Vector2i(64, 64):
			texture_rect.custom_minimum_size = Vector2(texture_dimension)
		else:
			texture_rect.custom_minimum_size = FileSystemSingleton.get_thumbnail_size()
		
		container.add_child(texture_rect)
		container.move_child(texture_rect, 0)
	
	label_text += _get_dependencies(path)
	
	label.text = label_text
	return container




static func _get_file_specific_details(path:String):
	var label_text = ""
	var ext = path.get_extension()
	if ext == "tres":
		var custom_type = UResourceMethods.get_resource_script_class(path)
		if custom_type:
			label_text += "\nScript Class: %s" % custom_type
		
	elif ext == "tscn":
		var root = UPackedScene.ReadFile.get_root_type(path)
		if root:
			var inh = root.begins_with("res://")
			var inh_text = ""
			if inh:
				inh_text = "\nInherits: %s" % root
				root = UPackedScene.ReadFile.get_root_type(path, true)
			label_text += "\nScene Root: %s" % root
			label_text += inh_text
		
	elif ext == "gd":
		var _class = GDFileRead.get_class_name(path)
		if _class:
			label_text += "\nClass Name: %s" % _class
		
		var _extends = GDFileRead.get_extends(path)
		if not _extends:
			_extends = "RefCounted"
		label_text += "\nExtends: %s" % _extends
		
		if GDFileRead.get_is_tool(path):
			label_text += "\nTool Script"
		
	
	return label_text

static func _get_type_specific_details(path:String, type:String):
	var label_text = ""
	if ClassDB.is_parent_class(type, "Texture"):
		var texture_dimension = _get_texture_dimensions(path, type)
		if texture_dimension != Vector2i(-1,-1):
			label_text += "\nDimensions: %s x %s" % [texture_dimension.x, texture_dimension.y]
	elif ClassDB.is_parent_class(type, "AudioStream"):
		var length = Audio.get_audio_duration(path)
		length = Audio.format_duration(length)
		label_text += "\nLength: %s" % length
		pass
	
	return label_text

static func _get_texture_dimensions(path:String, type:String):
	if ClassDB.is_parent_class(type, "Texture"):
		return ImageSize.get_image_size(path)
	return Vector2i(-1,-1)


static func _get_dependencies(path:String, show_paths:=true):
	var deps = ResourceLoader.get_dependencies(path)
	var dep_string = "\nDependencies: %s" % deps.size()
	if deps.size() == 0:
		return dep_string
	var force_show_deps = Input.is_key_pressed(KEY_SHIFT)
	if deps.size() <= 5 or force_show_deps:
		for d in deps:
			dep_string += "\n%s" % d.get_slice("::", 2)
	elif deps.size() > 5:
		dep_string = "\nDependencies: %s\nHold shift when hovering to list." % deps.size()
	
	return dep_string



static func _get_non_res_details(path:String):
	var _name = path.trim_suffix("/").get_file()
	var _size = UFile.get_file_size(path)
	
	var label_text = "%s\nSize: %s" % [_name, _size]
	
	var ext = path.get_extension()
	var image_exts = ["jpg", "svg", "png", "dds"]
	if ext in image_exts:
		var image_size = ImageSize.get_image_size(path)
		if image_size != Vector2i(-1, -1):
			label_text += "\nDimensions: %s x %s" % [image_size.x, image_size.y]
	
	return label_text
