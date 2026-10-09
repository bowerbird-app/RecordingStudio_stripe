# frozen_string_literal: true

RecordingStudioApi.configure do |config|
  config.openapi_title = "Recording Studio API"
  config.layout_name = "recording_studio/default_layout"
  config.rate_limit_oauth_enabled = false
  config.rate_limit_api_pre_auth_enabled = false
  config.rate_limit_api_enabled = false
  config.rate_limit_fail_closed = false
  config.api_management_authorization_required = false
  config.api_request_logging_enabled = false

  config.api :operations do |api|
    api.openapi_title = "Recording Studio Operations API"
    api.openapi_description = "Read-only operational access for trusted administrators and automation."
    api.api_versions = %w[v1]
    api.default_access = :read_only
    api.api_management_authorization_required = false
    api.rate_limit_oauth_enabled = false
    api.rate_limit_api_pre_auth_enabled = false
    api.rate_limit_api_enabled = false
    api.api_request_logging_enabled = false
  end
end

RecordingStudioApi.register_recordable_type_api(
  "AdminRoot",
  api: :operations,
  operations: %i[index show],
  serializer: ->(recordable, **) { { name: recordable.name } },
  output_keys: %i[name]
)
RecordingStudioApi.register_recordable_type_api(
  "Workspace",
  api: :operations,
  operations: %i[index show],
  serializer: ->(recordable, **) { { name: recordable.name } },
  output_keys: %i[name]
)

RecordingStudioMetrics::Api.register!(api: :operations)
