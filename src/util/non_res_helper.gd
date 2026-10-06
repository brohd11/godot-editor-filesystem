
const FSClasses = preload("res://addons/addon_lib/editor_filesystem/src/util/fs_classes.gd")
const FileSystemPlaces = FSClasses.FileSystemPlaces

const FSUtil = FSClasses.FSUtil
const RightClickHandler = FSUtil.RightClickHandler
const Options = FSUtil.Options

var places:FileSystemPlaces

func get_right_click_options(path:String, selected_paths:Array) -> Options:
	var options = Options.new()
	
	if FileAccess.file_exists(path):
		options.add_option("Open File", open_file.bind(path), ["Load"])
		options.add_option("Open Dir", open_file.bind(path.get_base_dir()),["Load"])
	elif DirAccess.dir_exists_absolute(path):
		options.add_option("Open Dir", open_file.bind(path),["Load"])
		var places_options = places.get_add_to_places_options(path)
		options.merge(places_options)
	
	
	return options


static func open_file(path:String):
	var global = ProjectSettings.globalize_path(path)
	OS.shell_open(global)
