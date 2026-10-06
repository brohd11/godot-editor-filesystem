const FSClasses = preload("res://addons/addon_lib/editor_filesystem/src/util/fs_classes.gd")
const FSUtil = FSClasses.FSUtil
const UResourceMethods = FSUtil.UResourceMethods
const ReadTres = UtilR.Resources.Read.Tres
const Filter = FSUtil.UStringFilter

enum FilterMode {
	AUTO,
	EXACT,
	EXACT_SORT,
	SUBSEQUENCE,
	SUBSEQUENCE_SORT,
}



static func filter_custom(to_filter:PackedStringArray, filter_text_array:PackedStringArray, callable_data:Dictionary):
	return Filter.filter_array(to_filter, filter_text_array, callable_data)

static func create_callable_data(match_callable:Callable, sort_callable=null) -> Dictionary:
	return Filter.get_search_callable_dict(match_callable, sort_callable)



static func filter_subseq(to_filter:PackedStringArray, filter_text_array:PackedStringArray, file_name:=false) -> PackedStringArray:
	return Filter.subsequence(to_filter, filter_text_array, file_name)

static func filter_subseq_sorted(to_filter:PackedStringArray, filter_text_array:PackedStringArray, file_name:=false) -> PackedStringArray:
	return Filter.subsequence_sorted(to_filter, filter_text_array, file_name)

static func filter_exact_match(to_filter:PackedStringArray, filter_text_array:PackedStringArray, file_name:=false) -> PackedStringArray:
	return Filter.exact(to_filter, filter_text_array, file_name)

static func filter_exact_match_sorted(to_filter:PackedStringArray, filter_text_array:PackedStringArray, file_name:=false) -> PackedStringArray:
	return Filter.exact_sorted(to_filter, filter_text_array, file_name)



static func filter_with_prefixes(to_filter:PackedStringArray, filter_text_array:PackedStringArray) -> PackedStringArray:
	to_filter = filter_ext(to_filter, filter_text_array)
	to_filter = filter_type(to_filter, filter_text_array)
	return to_filter


static func filter_type(to_filter:PackedStringArray, filter_text_array:PackedStringArray) -> PackedStringArray:
	var callable_data = Filter.get_search_callable_dict(_type_match)
	return Filter.filter_array(to_filter, filter_text_array, callable_data)



static func _type_match(to_filter:PackedStringArray, filter_text_array:PackedStringArray):
	var has_category:= false
	var selected_category = ""
	var selected_category_base = ""
	var selected_category_types = []
	var selected_category_exts = []
	
	var categories = Types.DATA.keys()
	var lower_cats = {}
	for c in categories:
		lower_cats[c.to_lower()] = c
	
	var type_search_raw_filters = {}
	for text in filter_text_array:
		var prefix_data = Prefix.get_prefix(text)
		if not prefix_data:
			continue
		var prefix = prefix_data.get("prefix")
		var string = prefix_data.get("string")
		if prefix == Prefix.TYPE:
			if string.to_lower() in lower_cats.keys():
				prefix = Prefix.CATEGORY
				string = lower_cats[string]
			else:
				type_search_raw_filters[string] = true
		if prefix == Prefix.CATEGORY:
			if selected_category != "":
				type_search_raw_filters[string] = true # if a category is selected just search
			else:
				var category = string
				if category == "All":
					return to_filter
				var base = Types.get_base(category)
				has_category = true
				selected_category = category
				selected_category_base = base
				selected_category_types = Types.get_types(selected_category)
				selected_category_exts = Types.get_extensions(selected_category)
				continue
	
	if not has_category and type_search_raw_filters.is_empty():
		return to_filter
	
	var non_resource_filters = {}
	var resource_exact_match = ""
	var resource_matches = []
	var custom_resource_exact_match = ""
	var custom_resource_matches = {}
	var search_type_array = []
	if not type_search_raw_filters.is_empty(): # case: there is text entered that is not a category
		var resource_types:Array
		var custom_resource_types:Dictionary
		var non_resource_categories:= []
		if has_category: # if category, only search category types
			resource_types = selected_category_types
			custom_resource_types = FileSystemSingleton.FileTypes.get_custom_resource_types(selected_category_base)
		else: # no category
			resource_types = FileSystemSingleton.FileTypes.get_resource_list()
			custom_resource_types = FileSystemSingleton.FileTypes.get_custom_resource_types()
			non_resource_categories = Types.get_non_resource_categories() # if no selected category can search for non_res
		
		for text in type_search_raw_filters:
			if text in resource_types:
				resource_exact_match = text
				search_type_array.clear()
				break
			elif custom_resource_types.has(text):
				var base = custom_resource_types[text].base
				if base:
					custom_resource_matches[text] = base
					custom_resource_exact_match = text
					search_type_array.clear()
					break
			else: # if no exact match, continue to search with the string
				search_type_array.append(text)
		
		if not search_type_array.is_empty():
			for res_type in resource_types:
				if Filter.Check.subsequence_n(res_type, search_type_array):
					resource_matches.append(res_type)
			for res_type in custom_resource_types:
				if Filter.Check.subsequence_n(res_type, search_type_array):
					var base = custom_resource_types[res_type].base
					if base:
						custom_resource_matches[res_type] = base
			for category in non_resource_categories:
				var base = Types.get_base(category)
				if Filter.Check.subsequence_n(base, search_type_array):
					non_resource_filters[category] = true
	
	#print("FINAL SEARCH: ", search_type_array, custom_resource_matches, resource_exact_match, custom_resource_exact_match,"!")
	var valid_types = {}
	if resource_exact_match != "":
		if not has_category or resource_exact_match in selected_category_types:
			valid_types[resource_exact_match] = true
		
	elif custom_resource_exact_match != "":
		var base = custom_resource_matches[custom_resource_exact_match]
		if not has_category or base in selected_category_types:
			valid_types[base] = true
	
	if valid_types.is_empty():
		for type in selected_category_types:
			valid_types[type] = true
		
		for type in resource_matches:
			if not has_category or type in selected_category_types:
				valid_types[type] = true
		
		for c_match in custom_resource_matches.keys():
			var custom_base = custom_resource_matches[c_match]
			if not has_category or custom_base in selected_category_types:
				valid_types[custom_base] = true
	
	
	var valid_extensions = selected_category_exts
	if not has_category:
		valid_extensions = FileSystemSingleton.FileTypes.get_recognized_file_extensions(valid_types.keys(), true)
		for category in non_resource_filters: # checks for types that are not able to get est form resource system
			valid_types[Types.get_base(category)] = true # ie. TextFile
			var extensions = Types.get_extensions(category)
			for ext in extensions:
				valid_extensions[ext] = true
	
	var has_search_types = not search_type_array.is_empty()
	var valid_paths = {}
	for path in to_filter:
		var ext = path.get_extension()
		if not valid_extensions.has(ext):
			continue
		var type = FileSystemSingleton.get_file_type_static(path)
		if not valid_types.has(type):
			continue
		var is_tres = ext == "tres"
		if not custom_resource_exact_match.is_empty() and is_tres:
			if not _check_custom_resource(path, [custom_resource_exact_match]):
				continue
		elif has_search_types:
			if not Filter.Check.subsequence_n(type, search_type_array):
				if not is_tres:
					continue
				if not _check_custom_resource(path, search_type_array):
					continue
		
		valid_paths[path] = true
	
	return valid_paths

static func _check_custom_resource(path:String, search_array:Array):
	var _class_name = ReadTres.get_resource_script_class(path)
	if _class_name == "":
		return false
	return Filter.Check.subsequence_n(_class_name, search_array)


static func filter_ext(to_filter:PackedStringArray, filter_text_array:PackedStringArray) -> PackedStringArray:
	var callable_data = Filter.get_search_callable_dict(_ext_match)
	return Filter.filter_array(to_filter, filter_text_array, callable_data)

static func _ext_match(to_filter:PackedStringArray, filter_text_array:PackedStringArray):
	var prefix_strings = Prefix.get_prefix_strings(filter_text_array, Prefix.EXT)
	#print(prefix_strings)
	if prefix_strings.is_empty():
		return to_filter
	var valid_paths = {}
	for path in to_filter:
		var ext = path.get_extension()
		if ext in prefix_strings:
			valid_paths[path] = true
	return valid_paths









class Types:
	
	const DATA = {
		"Resource":{
			"base":"Resource",
			"icon":"Object",
			"inherits": false,
		},
		"Script":{
			"base":"Script",
			"icon":"Script",
		},
		"Scene":{
			"base":"PackedScene",
			"icon":"PackedScene",
		},
		"TextFile":{
			"base":"TextFile",
			"icon":"TextFile",
			"is_resource": false,
			"extensions": ["cfg", "md", "ini", "txt", "xml", "yml"],
		},
		"Texture":{
			"base":"Texture",
			"icon":"Texture2D",
		},
		"Audio":{
			"base":"AudioStream",
			"icon":"AudioStream",
		},
		"Material":{
			"base":"Material",
			"icon":"StandardMaterial3D",
		},
		"Mesh":{
			"base":"Mesh",
			"icon":"Mesh",
		}
	}
	
	static func get_categories():
		return DATA.keys()
	
	static func get_base(category:String):
		return DATA[category].base
	
	static func get_icon(category:String):
		return DATA[category].icon
	
	static func get_inherits(category:String):
		return DATA.get(category, {}).get("inherits", true)
	
	static func get_is_resource(category:String):
		return DATA.get(category, {}).get("is_resource", true)
	
	static func get_extensions(category:String):
		if get_is_resource(category):
			return FileSystemSingleton.FileTypes.get_recognized_file_extensions(get_types(category), true)
		return DATA.get(category, {}).get("extensions", [])
	
	static func get_types(category:String):
		var base = get_base(category)
		var types = [base]
		if not get_is_resource(category):
			return types
		if get_inherits(category):
			types.append_array(ClassDB.get_inheriters_from_class(base))
		return types
	
	static func get_non_resource_categories():
		var categories = []
		for cat in DATA.keys():
			if not get_is_resource(cat):
				categories.append(cat)
		return categories


class Prefix:
	const CATEGORY = "category:"
	const TYPE = "t:"
	const EXT = "e:"
	
	static func text_is_prefix(text:String):
		var prefixes = [CATEGORY, TYPE, EXT]
		for p in prefixes:
			if p == text:
				return true
		return false
		
	
	static func get_prefix(text:String):
		if text.begins_with(CATEGORY):
			return _get_prefix(text, CATEGORY)
		if text.begins_with(TYPE):
			return _get_prefix(text, TYPE)
		if text.begins_with(EXT):
			return _get_prefix(text, EXT)
	
	static func _get_prefix(text:String, prefix:String):
		if not text.begins_with(prefix):
			return null
		var slice = text.get_slice(prefix, 1)
		if slice.is_empty():
			return null
		return {"prefix":prefix, "string": slice}
	
	static func get_prefix_strings(array:PackedStringArray, prefix:String):
		var strings = []
		for text in array:
			var prefix_data = _get_prefix(text, prefix)
			if not prefix_data:
				continue
			strings.append(prefix_data.string)
		return strings
