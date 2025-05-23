@tool
class_name CustomAPI
extends LLMInterface

# Custom API configuration
const API_KEY_SETTING := "plugins/ai_assistant_hub/custom_api_key"
const BASE_URL_SETTING := "plugins/ai_assistant_hub/custom_base_url"
const DEFAULT_BASE_URL := "https://api.openai.com/v1"
const DEFAULT_MODEL := ""
const API_KEY_FILE := "res://addons/ai_assistant_hub/llm_apis/custom_api_key.gd"
const BASE_URL_FILE := "res://addons/ai_assistant_hub/llm_apis/custom_base_url.gd"

# HTTP headers required for every request
var _headers := PackedStringArray([
	"Content-Type: application/json",
	"Authorization: Bearer {api_key}",  # Will be dynamically replaced before the request
])

# Get model list
func send_get_models_request(http_request: HTTPRequest) -> bool:
	var api_key := _get_api_key()
	if api_key.is_empty():
		push_error("Custom API key not set. Please configure the API key in project settings.")
		return false
	
	var base_url := _get_base_url()
	if base_url.is_empty():
		push_error("Custom API base URL not set. Please configure the base URL in project settings.")
		return false
	
	var headers := _get_headers_with_api_key(api_key)
	var url := "%s/models" % base_url
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_error("Custom API request failed: %s" % url)
		return false
	return true

# Parse model list response
func read_models_response(body: PackedByteArray) -> Array[String]:
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		push_error("Failed to parse Custom API response JSON: %s" % json.get_error_message())
		return [INVALID_RESPONSE]
	
	var response := json.get_data()
	
	if response.has("data") and response.data is Array:
		var model_names: Array[String] = []
		for model in response.data:
			if model.has("id"):
				model_names.append(model.id)
		model_names.sort()
		return model_names
	elif response.has("models") and response.models is Array:
		# Support alternative format
		var model_names: Array[String] = []
		for model in response.models:
			if model.has("id"):
				model_names.append(model.id)
			elif model.has("name"):
				model_names.append(model.name)
		model_names.sort()
		return model_names
	else:
		push_error("Failed to get model list from Custom API: %s" % JSON.stringify(response))
		return [INVALID_RESPONSE]

# Send chat request
func send_chat_request(http_request: HTTPRequest, content: Array) -> bool:
	var api_key := _get_api_key()
	if api_key.is_empty():
		push_error("Custom API key not set. Please configure the API key in project settings.")
		return false
	
	var base_url := _get_base_url()
	if base_url.is_empty():
		push_error("Custom API base URL not set. Please configure the base URL in project settings.")
		return false
	
	# Ensure model is set
	if model.is_empty():
		model = DEFAULT_MODEL
		push_warning("Model not set, using default model: %s" % model)
	
	# Build request body
	var body_dict := {
		"model": model,
		"messages": content
	}
	
	# Add temperature setting (if needed)
	if override_temperature:
		body_dict["temperature"] = temperature
	
	var body := JSON.stringify(body_dict)
	var headers := _get_headers_with_api_key(api_key)
	var url := "%s/chat/completions" % base_url
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error("Custom API chat request failed.\nURL: %s\nRequest body: %s" % [url, body])
		return false
	return true

# Parse chat response
func read_response(body: PackedByteArray) -> String:
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		push_error("Failed to parse Custom API response JSON: %s" % json.get_error_message())
		return INVALID_RESPONSE
	
	var response := json.get_data()
	
	# Handle error responses
	if response.has("error"):
		push_error("Custom API Error: %s" % JSON.stringify(response.error))
		return INVALID_RESPONSE
	
	if response.has("choices") and response.choices.size() > 0:
		if response.choices[0].has("message") and response.choices[0].message.has("content"):
			return response.choices[0].message.content
	
	push_error("Failed to parse Custom API response: %s" % JSON.stringify(response))
	return INVALID_RESPONSE

# Helper method: Get API key - tries to load from file first, then falls back to ProjectSettings
func _get_api_key() -> String:
	# First try to load from file
	var api_key := _load_api_key_from_file()
	
	# If not found in file, try ProjectSettings
	if api_key.is_empty() and ProjectSettings.has_setting(API_KEY_SETTING):
		api_key = ProjectSettings.get_setting(API_KEY_SETTING)
		# If we found a key in ProjectSettings, save it to file for next time
		if not api_key.is_empty():
			_save_api_key_to_file(api_key)
	
	return api_key

# Helper method: Get base URL - tries to load from file first, then falls back to ProjectSettings
func _get_base_url() -> String:
	# First try to load from file
	var base_url := _load_base_url_from_file()
	
	# If not found in file, try ProjectSettings
	if base_url.is_empty() and ProjectSettings.has_setting(BASE_URL_SETTING):
		base_url = ProjectSettings.get_setting(BASE_URL_SETTING)
		# If we found a URL in ProjectSettings, save it to file for next time
		if not base_url.is_empty():
			_save_base_url_to_file(base_url)
	
	# If still empty, use default
	if base_url.is_empty():
		base_url = DEFAULT_BASE_URL
	
	# Remove trailing slash if present
	if base_url.ends_with("/"):
		base_url = base_url.substr(0, base_url.length() - 1)
	
	return base_url

# Save API key to file
func _save_api_key_to_file(api_key: String) -> void:
	var file_content := """@tool
extends Resource

# This file is auto-generated. Do not edit manually.
# It stores the Custom API key for the AI Assistant Hub plugin.

const API_KEY := "%s"
"""
	file_content = file_content % api_key
	
	var file := FileAccess.open(API_KEY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(file_content)
		file.close()
	else:
		push_error("Failed to save Custom API key to file: %s" % API_KEY_FILE)

# Save base URL to file
func _save_base_url_to_file(base_url: String) -> void:
	var file_content := """@tool
extends Resource

# This file is auto-generated. Do not edit manually.
# It stores the Custom API base URL for the AI Assistant Hub plugin.

const BASE_URL := "%s"
"""
	file_content = file_content % base_url
	
	var file := FileAccess.open(BASE_URL_FILE, FileAccess.WRITE)
	if file:
		file.store_string(file_content)
		file.close()
	else:
		push_error("Failed to save Custom API base URL to file: %s" % BASE_URL_FILE)

# Load API key from file
func _load_api_key_from_file() -> String:
	if not FileAccess.file_exists(API_KEY_FILE):
		return ""
		
	var file := FileAccess.open(API_KEY_FILE, FileAccess.READ)
	if not file:
		push_error("Failed to open Custom API key file: %s" % API_KEY_FILE)
		return ""
		
	var content := file.get_as_text()
	file.close()
	
	var regex := RegEx.new()
	regex.compile('const API_KEY := "([^"]*)"')
	var result := regex.search(content)
	
	if result and result.get_group_count() > 0:
		return result.get_string(1)
	
	return ""

# Load base URL from file
func _load_base_url_from_file() -> String:
	if not FileAccess.file_exists(BASE_URL_FILE):
		return ""
		
	var file := FileAccess.open(BASE_URL_FILE, FileAccess.READ)
	if not file:
		push_error("Failed to open Custom API base URL file: %s" % BASE_URL_FILE)
		return ""
		
	var content := file.get_as_text()
	file.close()
	
	var regex := RegEx.new()
	regex.compile('const BASE_URL := "([^"]*)"')
	var result := regex.search(content)
	
	if result and result.get_group_count() > 0:
		return result.get_string(1)
	
	return ""

# Helper method: Get request headers with API key
func _get_headers_with_api_key(api_key: String) -> PackedStringArray:
	var headers := []
	for header in _headers:
		if header.begins_with("Authorization:"):
			headers.append("Authorization: Bearer %s" % api_key)
		else:
			headers.append(header)
	return PackedStringArray(headers)

# Public method to save API key - called when user changes the key in UI
func save_api_key(api_key: String) -> void:
	_save_api_key_to_file(api_key)
	# Also update ProjectSettings for backward compatibility
	ProjectSettings.set_setting(API_KEY_SETTING, api_key)

# Public method to save base URL - called when user changes the URL in UI
func save_base_url(base_url: String) -> void:
	_save_base_url_to_file(base_url)
	# Also update ProjectSettings for backward compatibility
	ProjectSettings.set_setting(BASE_URL_SETTING, base_url)

# Get current base URL for display in UI
func get_base_url() -> String:
	return _get_base_url() 