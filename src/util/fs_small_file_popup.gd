#! namespace EditorFS.Components class SmallPopup

const UFile = preload("uid://bl33psa06nv1e") #! resolve ALibRuntime.Utils.UFile.Methods
const Options = preload("uid://dxdxq2n3imf4q") #! resolve UtilR.Nodes.PopupMenus.Options

const SCRIPT_TABS_NAME = "ScriptTabSingleton"
const SCRIPT_DOCK_NAME = "ScriptDock"

enum FileStatus {
	VALID,
	INVALID,
	MISSING
}


static func right_click(options:Options, path:String) -> FileStatus:
	if not FileAccess.file_exists(path):
		options.add_separator("Missing File")
		return FileStatus.MISSING
	elif not FileSystemSingleton.is_path_valid(path):
		options.add_separator("Invalid File")
		return FileStatus.INVALID
	
	options.add_option("Open", FileSystemSingleton.activate_path.bind(path), ["Load"])
	
	var script_tabs = _get_singleton(SCRIPT_TABS_NAME)
	if is_instance_valid(script_tabs):
		var valid_containers = script_tabs.get_valid_containers_for_path(path, _open_in_split)
		options._dict.merge(valid_containers)
		options.add_separator()
	
	options.add_option("Copy Script Path", _copy_to_clipboard.bind(path), ["ActionCopy"])
	options.add_option("Copy Script UID", _copy_to_clipboard.bind(path, true))
	options.add_separator()
	if is_instance_valid(_get_singleton(SCRIPT_DOCK_NAME)):
		options.add_option("Show in ScriptDock Tree", _navigate_to.bind(path), ["ShowInFileSystem"])
	options.add_option("Show in File Manager", _navigate_to.bind(path, true), ["Filesystem"])
	
	return FileStatus.VALID

#static func _open_file(path:String):
	#FileSystemSingleton.activate_path(path)

static func _copy_to_clipboard(path:String, uid:=false):
	var to_clip = UFile.path_to_uid(path) if uid else path
	DisplayServer.clipboard_set(to_clip)


static func _open_in_split(path:String, target_tab:int):
	var script_tabs = _get_singleton(SCRIPT_TABS_NAME)
	if not is_instance_valid(script_tabs):
		printerr("No ScriptTab singleton found. How did you get here?")
		return
	script_tabs.open_script(path, target_tab, FileSystemSingleton.get_instance())



static func _navigate_to(path:String, os_file:=false):
	if os_file:
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))
	else:
		var script_dock = _get_singleton(SCRIPT_DOCK_NAME)
		if is_instance_valid(script_dock):
			script_dock.show_in_tree(path)


static func _get_singleton(name:String):
	return Singletons.CheckInstance.get_instance(name)
