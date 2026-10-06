extends CodeEdit

const TextSyntaxHighlighter = preload("res://addons/addon_lib/brohd/alib_runtime/misc/syntax_highlighters/text/text_syntax_highlighter.gd")

func set_path(path:String):
	if path.get_extension() == "gd":
		if not syntax_highlighter is GDScriptSyntaxHighlighter:
			syntax_highlighter = GDScriptSyntaxHighlighter.new()
	else:
		if not syntax_highlighter is TextSyntaxHighlighter:
			syntax_highlighter = TextSyntaxHighlighter.new()
			syntax_highlighter.palette.apply_editor_settings()
		syntax_highlighter.extension = path.get_extension()
	
	text = FileAccess.get_file_as_string(path)
