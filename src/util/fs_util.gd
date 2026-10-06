
const RightClickHandler = preload("uid://mmtkf4h8er3m") #! resolve ClickHandlers.RightClickHandler
const Options = RightClickHandler.Options

const EditorIcons = preload("uid://viocyrti6wce") #! resolve ALibEditor.Singleton.EditorIcons

const Dialog = preload("uid://bccd38qwc47vu") #! resolve ALibRuntime.Dialog
const LineSubmit = Dialog.Handlers.LineSubmit

const UEditorTheme = preload("uid://q4pcebn4vhsr") #! resolve ALibEditor.Utils.UEditorTheme
const ThemeColor = UEditorTheme.ThemeColor

const EditorColors = preload("uid://cpw0fsrs38esk") #! resolve UtilE.Colors
const FileSystem = preload("uid://dagr353kjvdrc") #! resolve EditorNodeRef.Refs.FileSystem
const PopupID = preload("uid://co1fsmkihc4cg") #! resolve EditorNodeRef.Refs.FileSystem.PopupID

const UVersion = preload("uid://dn156lc18d1vt") #! resolve UtilR.UVersion
const UFile = preload("uid://bqfy5cvhth0m1") #! resolve UtilR.Files.UFile
const GetFilesAsync = preload("uid://r6odl3pgmbp8") #! resolve UtilR.Files.GetFilesAsync
const UOs = preload("uid://dppsxjnth11uc") #! resolve UtilR.UOs
const UTree = preload("uid://1gwputufojp6") #! resolve UtilR.Nodes.Trees.UTree
const TreeAltColor = preload("uid://bgfj0lf3e1btg") #! resolve UtilR.Nodes.Trees.AltLineColor
const UString = preload("uid://dce8d0wuh35gs") #! resolve UtilR.Strings.UString
const UStringFilter = preload("uid://d10l2rjus6c3k") #! resolve UtilR.Strings.Filter
const UWindow = preload("uid://d1yl3cuumcudy") #! resolve UtilR.Nodes.UWindow
const CacheHelper = preload("uid://c70cjcnys60ud") #! resolve UtilR.Files.CacheHelper
const UControl = preload("uid://cdo8rcof3ilt1") #! resolve UtilR.Nodes.UControl
const UResource = preload("uid://xwy6i4dlbtvs") #! resolve UtilR.Resources.UResource
const UResourceMethods = UResource
const ReadTres = preload("uid://b63khouggaars") #! resolve UtilR.Resources.Read.Tres

const UGDScript = preload("uid://bqwb564jwff43") #! resolve ALibRuntime.Utils.UGDScript
const NUItemList = preload("uid://cjls86v1v4242") #! resolve ALibRuntime.NodeUtils.NUItemList
const NUTree = preload("uid://coqq638olix8k") #! resolve ALibRuntime.NodeUtils.NUTree

const SettingHelperEditor = preload("uid://dnov6vp7pjnbb") #! resolve SettingHelper.Editor
const SettingHelperSingleton = preload("uid://60187tsv40mq") #! resolve SettingHelper.Singleton
const SettingHelperJson = SettingHelperSingleton.SHJson

const ColumnDragger = preload("res://addons/_lib/brohd/alib_runtime/ui/column/dragger.gd")



#^ THESE ARE MOVED TO SINGLETON
static func is_path_valid_res(path:String) -> bool:
	if not path.begins_with("res://"):
		return false
	return FileSystemSingleton.is_path_valid(path)

static func is_root_folder(path:String):
	if path.ends_with("://") or path == "/":
		return true
	return false

static func paths_have_same_root(path:String, path_2:String):
	if path.begins_with("res://"):
		if path_2.begins_with("res://"):
			return true
		return false
	elif path.begins_with("user://"):
		if path_2.begins_with("user://"):
			return true
		return false
	elif path.begins_with("/"):
		if path_2.begins_with("/"):
			return true
		return false

#^ THESE ARE MOVED TO SINGLETON
