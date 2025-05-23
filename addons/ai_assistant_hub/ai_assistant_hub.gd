@tool
class_name AIAssistantHub
extends Control

signal models_refreshed(models:Array[String])
signal new_api_loaded()

const NEW_AI_ASSISTANT_BUTTON = preload("res://addons/ai_assistant_hub/new_ai_assistant_button.tscn")

@onready var models_http_request: HTTPRequest = %ModelsHTTPRequest
@onready var url_txt: LineEdit = %UrlTxt
@onready var api_class_txt: LineEdit = %ApiClassTxt
@onready var models_list: RichTextLabel = %ModelsList
@onready var no_assistants_guide: Label = %NoAssistantsGuide
@onready var assistant_types_container: HFlowContainer = %AssistantTypesContainer
@onready var tab_container: TabContainer = %TabContainer
@onready var llm_provider_option: OptionButton = %LLMProviderOption
@onready var url_label: Label = %UrlLabel
@onready var openrouter_key_container: HBoxContainer = %OpenRouterKeyContainer
@onready var openrouter_api_key: LineEdit = %OpenRouterAPIKey

var _plugin:EditorPlugin
var _tab_bar:TabBar
var _model_names:Array[String] = []
var _models_llm: LLMInterface
var _current_provider_id: String = ""
var _api_key_label: Label  # Will be found at runtime


func _tab_changed(tab_index: int) -> void:
	if tab_index > 0:
		_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	else:
		_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_NEVER


func _close_tab(tab_index: int) -> void:
	var chat = tab_container.get_tab_control(tab_index)
	models_refreshed.disconnect(chat.refresh_models)
	chat.queue_free()


func initialize(plugin:EditorPlugin) -> void:
	_plugin = plugin
	_models_llm = _plugin.new_llm_provider()
	
	await ready
	
	# Find the API key label in the OpenRouter container
	for child in openrouter_key_container.get_children():
		if child is Label:
			_api_key_label = child
			break
	
	url_txt.text = ProjectSettings.get_setting(AIHubPlugin.CONFIG_BASE_URL)
	api_class_txt.text = ProjectSettings.get_setting(AIHubPlugin.CONFIG_LLM_API)
	_current_provider_id = api_class_txt.text
	
	# Load OpenRouter API key
	if _current_provider_id == "openrouter_api":
		_load_openrouter_api_key()
	elif ProjectSettings.has_setting(AIHubPlugin.CONFIG_OPENROUTER_API_KEY):
		openrouter_api_key.text = ProjectSettings.get_setting(AIHubPlugin.CONFIG_OPENROUTER_API_KEY)
	
	# Load Custom API settings - base URL goes to url_txt for now
	if _current_provider_id == "custom_api":
		var custom_api = load("res://addons/ai_assistant_hub/llm_apis/custom_api.gd").new()
		var base_url = custom_api.get_base_url()
		if not base_url.is_empty():
			url_txt.text = base_url
	
	# Initialize LLM provider dropdown
	_initialize_llm_provider_options()
	
	_on_assistants_refresh_btn_pressed()
	_on_refresh_models_btn_pressed()
	
	_tab_bar = tab_container.get_tab_bar()
	_tab_bar.tab_changed.connect(_tab_changed)
	_tab_bar.tab_close_pressed.connect(_close_tab)


# Initialize LLM provider options
func _initialize_llm_provider_options() -> void:
	llm_provider_option.clear()
	var providers = _plugin.get_available_llm_providers()
	
	for i in range(providers.size()):
		var provider = providers[i]
		llm_provider_option.add_item(provider.name)
		llm_provider_option.set_item_metadata(i, provider.id)
		
		# Select currently used provider
		if provider.id == _current_provider_id:
			llm_provider_option.select(i)
	
	# Update UI state
	_update_provider_ui()


# Update UI based on current provider selection
func _update_provider_ui() -> void:
	var provider_id = _current_provider_id
	
	# Hide all containers first
	url_txt.visible = false
	openrouter_key_container.visible = false
	
	# Show appropriate UI based on provider
	if provider_id == "ollama_api":
		url_label.text = "Server URL"
		url_txt.placeholder_text = "Example: http://127.0.0.1:11434"
		url_txt.tooltip_text = "URL of the host running the LLM.\n\nDefault value uses Ollama's default port."
		url_txt.visible = true
	elif provider_id == "openrouter_api":
		url_label.text = "OpenRouter Settings"
		# Update the label for OpenRouter
		if _api_key_label:
			_api_key_label.text = "OpenRouter API Key:"
		openrouter_api_key.placeholder_text = "Enter your OpenRouter API key"
		openrouter_api_key.tooltip_text = "Get your API key from https://openrouter.ai/keys"
		openrouter_key_container.visible = true
	elif provider_id == "custom_api":
		url_label.text = "Custom API Settings"
		# Use url_txt for Custom API base URL
		url_txt.visible = true
		url_txt.placeholder_text = "Custom API Base URL (e.g., https://api.openai.com/v1)"
		url_txt.tooltip_text = "Enter the base URL for your custom API endpoint"
		
		# Reuse the OpenRouter key container for Custom API key
		if _api_key_label:
			_api_key_label.text = "Custom API Key:"
		openrouter_api_key.placeholder_text = "Enter your Custom API key"
		openrouter_api_key.tooltip_text = "API key for your custom endpoint"
		openrouter_key_container.visible = true
		
		# Load existing Custom API key
		var custom_api = load("res://addons/ai_assistant_hub/llm_apis/custom_api.gd").new()
		var api_key = custom_api._get_api_key()
		if not api_key.is_empty():
			openrouter_api_key.text = api_key
	elif provider_id == "jan_api":
		url_label.text = "Server URL"
		url_txt.placeholder_text = "Example: http://127.0.0.1:1337"
		url_txt.tooltip_text = "URL of the Jan API server."
		url_txt.visible = true
	elif provider_id == "gemini_api":
		url_label.text = "Gemini Settings"
		url_txt.visible = true
		url_txt.placeholder_text = "Note: Configure API key in Project Settings"
		url_txt.tooltip_text = "Gemini uses a fixed endpoint. Configure your API key in Project Settings -> Plugins -> ai_assistant_hub -> gemini_api_key"
	else:
		url_label.text = "Server URL"
		url_txt.visible = true


func _on_settings_changed(_x) -> void:
	ProjectSettings.set_setting(AIHubPlugin.CONFIG_BASE_URL, url_txt.text)
	ProjectSettings.set_setting(AIHubPlugin.CONFIG_LLM_API, api_class_txt.text)
	
	# Save OpenRouter API key
	if _current_provider_id == "openrouter_api":
		ProjectSettings.set_setting(AIHubPlugin.CONFIG_OPENROUTER_API_KEY, openrouter_api_key.text)
		var openrouter_api = load("res://addons/ai_assistant_hub/llm_apis/openrouter_api.gd").new()
		openrouter_api.save_api_key(openrouter_api_key.text)
	
	# Save Custom API settings
	if _current_provider_id == "custom_api":
		ProjectSettings.set_setting(AIHubPlugin.CONFIG_CUSTOM_BASE_URL, url_txt.text)
		ProjectSettings.set_setting(AIHubPlugin.CONFIG_CUSTOM_API_KEY, openrouter_api_key.text)
		var custom_api = load("res://addons/ai_assistant_hub/llm_apis/custom_api.gd").new()
		custom_api.save_base_url(url_txt.text)
		custom_api.save_api_key(openrouter_api_key.text)
	
	ProjectSettings.save()


func _on_refresh_models_btn_pressed() -> void:
	models_list.text = ""
	_models_llm.send_get_models_request(models_http_request)


func _on_models_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == 0:
		var models_returned: Array = _models_llm.read_models_response(body)
		if models_returned.size() == 0:
			models_list.text = "No models found. Download at least one model and try again."
		else:
			if models_returned[0] == LLMInterface.INVALID_RESPONSE:
				models_list.text = "Error while trying to get the models list. Response: %s" % _models_llm.get_full_response(body)
			else:
				_model_names = models_returned
				for model in _model_names:
					models_list.text += "%s\n" % model
				models_refreshed.emit(_model_names) #for existing chats
	else:
		push_error("HTTP response: Result: %s, Response Code: %d, Headers: %s, Body: %s" % [result, response_code, headers, body])
		models_list.text = "Something went wrong querying for models, is the Server URL correct?"


func _on_assistants_refresh_btn_pressed() -> void:
	var assistants_path = "%s/assistants" % self.scene_file_path.get_base_dir()
	var files = _get_all_resources(assistants_path)
	var found:= false
	
	for child in assistant_types_container.get_children():
		if child != no_assistants_guide:
			assistant_types_container.remove_child(child)
	
	for assistant_file in files:
		var assistant = load(assistant_file)
		if assistant is AIAssistantResource:
			found = true
			var new_bot_btn:NewAIAssistantButton= NEW_AI_ASSISTANT_BUTTON.instantiate()
			new_bot_btn.initialize(_plugin, assistant)
			new_bot_btn.chat_created.connect(_on_new_bot_btn_chat_created)
			assistant_types_container.add_child(new_bot_btn)
	
	if not found:
		no_assistants_guide.text = "You have no assistant types! Create a new AIAssistantResource in the assistants folder, then click the refresh button. The folder is at: %s" % assistants_path
		no_assistants_guide.visible = true
		assistant_types_container.visible = false
	else:
		no_assistants_guide.visible = false
		assistant_types_container.visible = true


func _on_new_bot_btn_chat_created(chat:AIChat, assistant_type:AIAssistantResource) -> void:
	tab_container.add_child(chat)
	tab_container.set_tab_icon(tab_container.get_child_count() - 1, assistant_type.type_icon)
	chat.refresh_models(_model_names)
	models_refreshed.connect(chat.refresh_models)
	new_api_loaded.connect(chat.load_api)
	chat.greet()


func _get_all_resources(path: String) -> Array[String]:  
	var file_paths: Array[String] = []  
	var dir = DirAccess.open(path)  
	dir.list_dir_begin()  
	var file_name = dir.get_next()  
	while not file_name.is_empty():  
		if file_name.ends_with(".tres"):
			var file_path = path + "/" + file_name
			file_paths.append(file_path)  
		file_name = dir.get_next()
	return file_paths


func _on_api_load_btn_pressed() -> void:
	var new_llm:LLMInterface = _plugin.new_llm_provider()
	if new_llm == null:
		push_error("Invalid API class")
		return
	_models_llm = new_llm
	new_api_loaded.emit()


# Called when LLM provider option changes
func _on_llm_provider_option_item_selected(index: int) -> void:
	var provider_id = llm_provider_option.get_item_metadata(index)
	if _current_provider_id != provider_id:
		_current_provider_id = provider_id
		api_class_txt.text = provider_id
		ProjectSettings.set_setting(AIHubPlugin.CONFIG_LLM_API, provider_id)
		
		# Load API key for OpenRouter if we're switching to it
		if provider_id == "openrouter_api":
			_load_openrouter_api_key()
		elif provider_id == "custom_api":
			# Load Custom API settings
			var custom_api = load("res://addons/ai_assistant_hub/llm_apis/custom_api.gd").new()
			var base_url = custom_api.get_base_url()
			if not base_url.is_empty():
				url_txt.text = base_url
			else:
				url_txt.text = ""
			# Load Custom API key
			var api_key = custom_api._get_api_key()
			if not api_key.is_empty():
				openrouter_api_key.text = api_key
			else:
				openrouter_api_key.text = ""
		elif provider_id == "ollama_api" or provider_id == "jan_api":
			# Restore base URL for these providers
			url_txt.text = ProjectSettings.get_setting(AIHubPlugin.CONFIG_BASE_URL)
			# Clear the API key field for providers that don't use it
			openrouter_api_key.text = ""
			
		_update_provider_ui()
		_on_api_load_btn_pressed()


# Load OpenRouter API key from the API class
func _load_openrouter_api_key() -> void:
	var openrouter_api = load("res://addons/ai_assistant_hub/llm_apis/openrouter_api.gd").new()
	var api_key = openrouter_api._get_api_key()
	if not api_key.is_empty():
		openrouter_api_key.text = api_key


# Called when OpenRouter API key changes (now also handles Custom API key)
func _on_openrouter_api_key_text_changed(new_text: String) -> void:
	if _current_provider_id == "openrouter_api":
		# Save OpenRouter API key
		ProjectSettings.set_setting(AIHubPlugin.CONFIG_OPENROUTER_API_KEY, new_text)
		var openrouter_api = load("res://addons/ai_assistant_hub/llm_apis/openrouter_api.gd").new()
		openrouter_api.save_api_key(new_text)
	elif _current_provider_id == "custom_api":
		# Save Custom API key
		ProjectSettings.set_setting(AIHubPlugin.CONFIG_CUSTOM_API_KEY, new_text)
		var custom_api = load("res://addons/ai_assistant_hub/llm_apis/custom_api.gd").new()
		custom_api.save_api_key(new_text)
	
	ProjectSettings.save() 