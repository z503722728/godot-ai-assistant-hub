@tool
class_name AIHubPlugin
extends EditorPlugin

const CONFIG_BASE_URL:= "ai_assistant_hub/base_url"
const CONFIG_LLM_API:= "ai_assistant_hub/llm_api"
const CONFIG_OPENROUTER_API_KEY := "plugins/ai_assistant_hub/openrouter_api_key"

var _hub_dock:AIAssistantHub

func _enter_tree() -> void:
	if ProjectSettings.get_setting(CONFIG_BASE_URL, "").is_empty():
		ProjectSettings.set_setting(CONFIG_BASE_URL, "http://127.0.0.1:11434")
	if ProjectSettings.get_setting(CONFIG_LLM_API, "").is_empty():
		ProjectSettings.set_setting(CONFIG_LLM_API, "ollama_api")
	
	# Setup OpenRouter API key (will be loaded from file if it exists)
	_init_openrouter_api_key()
	
	_hub_dock = load("res://addons/ai_assistant_hub/ai_assistant_hub.tscn").instantiate()
	_hub_dock.initialize(self)
	add_control_to_bottom_panel(_hub_dock, "AI Hub")
	#add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UL, _hub_dock)

# Initialize OpenRouter API key settings
func _init_openrouter_api_key() -> void:
	# First check if we have a key from the file
	var openrouter_api = load("res://addons/ai_assistant_hub/llm_apis/openrouter_api.gd").new()
	var api_key = openrouter_api._load_api_key_from_file()
	
	if api_key.is_empty():
		# If no key in file, check ProjectSettings
		if ProjectSettings.has_setting(CONFIG_OPENROUTER_API_KEY):
			api_key = ProjectSettings.get_setting(CONFIG_OPENROUTER_API_KEY)
			
			# If we have a key in ProjectSettings, save it to file
			if not api_key.is_empty():
				openrouter_api._save_api_key_to_file(api_key)
	else:
		# If we found a key in file, update ProjectSettings
		ProjectSettings.set_setting(CONFIG_OPENROUTER_API_KEY, api_key)
	
	# Add setting if it doesn't exist
	_add_project_setting(CONFIG_OPENROUTER_API_KEY, api_key, TYPE_STRING, PROPERTY_HINT_NONE, 
		"OpenRouter API key - Get it from https://openrouter.ai/keys")

func _exit_tree() -> void:
	remove_control_from_bottom_panel(_hub_dock)
	#remove_control_from_docks(_hub_dock)
	_hub_dock.queue_free()


## Helper function: Add project setting
func _add_project_setting(name: String, default_value, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if ProjectSettings.has_setting(name):
		return
	
	var property_info := {
		"name": name,
		"type": type,
		"hint": hint,
		"hint_string": hint_string
	}
	
	ProjectSettings.set_setting(name, default_value)
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(name, default_value)


## Load the API dinamically based on the script name given in project setting: ai_assistant_hub/llm_api
## By default this is equivalent to: return OllamaAPI.new()
func new_llm_provider() -> LLMInterface:
	return load("res://addons/ai_assistant_hub/llm_apis/%s.gd" % ProjectSettings.get_setting(AIHubPlugin.CONFIG_LLM_API)).new()


## Get available LLM providers list
func get_available_llm_providers() -> Array[Dictionary]:
	var providers: Array[Dictionary] = []
	
	# Add Ollama provider
	providers.append({
		"id": "ollama_api",
		"name": "Ollama",
		"description": "Locally run open source LLM (requires Ollama software)"
	})
	
	# Add OpenRouter provider
	providers.append({
		"id": "openrouter_api",
		"name": "OpenRouter",
		"description": "Unified interface to access various commercial LLMs (requires API key)"
	})
	
	return providers
