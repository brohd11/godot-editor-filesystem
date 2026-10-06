const UTree = preload("uid://1gwputufojp6") #! resolve UtilR.Nodes.Trees.UTree
const FSTreeHelper = preload("res://addons/addon_lib/editor_filesystem/src/util/fs_tree_helper.gd")

var original_file_name = ""
var _file_tree:Tree

func set_file_tree(file_tree:Tree):
	_file_tree = file_tree
	_file_tree.item_edited.connect(_on_item_edited)


func start_edit():
	var item = _file_tree.get_selected()
	
	original_file_name = item.get_text(0)
	_file_tree.edit_selected(true)
	var line_edit = UTree.get_line_edit(_file_tree) as LineEdit
	var ext_idx = line_edit.text.find(".")
	if ext_idx > -1:
		line_edit.select(0, ext_idx)

func _on_item_edited():
	var item = _file_tree.get_edited()
	var new_name = item.get_text(0)
	
	if not FileSystemSingleton.is_new_name_valid(original_file_name, new_name):
		item.set_text(0, original_file_name)
		original_file_name = ""
		return
	
	var old_path = FSTreeHelper.get_path_from_item(item)
	await FileSystemSingleton.rename_path(old_path, new_name)
