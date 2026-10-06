
const _COMMON_TYPES = [
	"Script",
	"Resource",
	"PackedScene",
	"Texture2D",
	"AudioStream",
	"Font",
	"Shader",
	"StandardMaterial3D",
	"ORMMaterial3D",
	"Mesh"
]


static func get_recognized_file_extensions(type_array:=_COMMON_TYPES, flatten:=true):
	var extensions = {}
	var type_data = {}
	for type in type_array:
		# Get extensions for this specific type
		var type_exts = ResourceLoader.get_recognized_extensions_for_type(type)
		if not type_exts.is_empty():
			if not flatten:
				type_data[type] = type_exts
			else:
				for e in type_exts:
					extensions[e] = true
	
	if flatten:
		type_data = extensions
	return type_data


static func get_custom_resource_types(inherits:="Resource"):
	var resources = {}
	var class_list = ProjectSettings.get_global_class_list()
	for data in class_list:
		var base = data.base
		if base == "":
			continue
		if ClassDB.is_parent_class(base, inherits):
			resources[data.class] = data
			continue
	return resources

static func get_custom_resource_base(script_class:String):
	var class_list = ProjectSettings.get_global_class_list()
	for data in class_list:
		if data.class == script_class:
			return data.base
	return ""

static func get_resource_list(include_custom:=false):
	var resources = ClassDB.get_inheriters_from_class("Resource")
	if include_custom:
		resources.append_array(get_custom_resource_types())
	return resources

static func get_file_type_list():
	return _COMMON_TYPES
