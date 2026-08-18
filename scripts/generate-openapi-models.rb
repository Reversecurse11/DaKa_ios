#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "optparse"
require "yaml"

EXPECTED_SHA256 = "853e7f5efadb10dcbbe0f446c4c60962ce2fd864360a156343b5740d0c1761a4"
ROOT = File.expand_path("..", __dir__)
DEFAULT_INPUT = File.join(ROOT, "Contracts", "openapi.snapshot.yaml")
DEFAULT_OUTPUT = File.join(ROOT, "BNBUStudentApp", "Backend", "Generated", "APIV1Models.generated.swift")

options = { input: DEFAULT_INPUT, output: DEFAULT_OUTPUT, check: false }
OptionParser.new do |parser|
  parser.on("--input PATH") { |value| options[:input] = File.expand_path(value) }
  parser.on("--output PATH") { |value| options[:output] = File.expand_path(value) }
  parser.on("--check") { options[:check] = true }
end.parse!

abort("error: OpenAPI snapshot not found: #{options[:input]}") unless File.file?(options[:input])

actual_hash = Digest::SHA256.file(options[:input]).hexdigest
unless actual_hash == EXPECTED_SHA256
  abort("error: OpenAPI SHA-256 mismatch: expected #{EXPECTED_SHA256}, got #{actual_hash}")
end

document = YAML.safe_load(File.read(options[:input]), aliases: true)
schemas = document.fetch("components").fetch("schemas")
http_methods = %w[get post put patch delete head options trace].freeze
operations = []
document.fetch("paths").each do |path, path_item|
  path_item.each do |method, operation|
    operations << operation.merge("x-path" => path, "x-method" => method.upcase) if http_methods.include?(method)
  end
end

unless document.dig("info", "version") == "2.0.2-contract" &&
       document.fetch("paths").length == 109 &&
       operations.length == 126 &&
       schemas.length == 288
  abort("error: OpenAPI 2.0.2 structural baseline mismatch")
end

intentionally_disabled_operations = operations
  .select { |operation| operation["x-enabled-by-default"] == false }
  .sort_by { |operation| operation.fetch("operationId") }
system_mode_unsupported_operations = intentionally_disabled_operations.select do |operation|
  operation["x-default-deny-error"] == "SYSTEM_MODE_UNSUPPORTED"
end
expected_intentionally_disabled_operation_ids = %w[
  appendExerciseLocationSamples
  createExport
  createExportDownloadUrl
  finalizeExerciseLocationTrack
  getActivityConversionRules
  getExerciseRecordLocationSummary
  getExport
  getLocationPrivacyPolicy
  getSportCatalog
  ignoreRosterAlignmentResult
  listExports
  openStudentScoreCorrection
  startExerciseLocationTrack
  updateLocationPrivacyPolicy
  updateStudent
  withdrawEnrollment
  withdrawExerciseRecord
].freeze
unless intentionally_disabled_operations.map { |operation| operation.fetch("operationId") } ==
       expected_intentionally_disabled_operation_ids &&
       system_mode_unsupported_operations.length == 13 &&
       operations.length - intentionally_disabled_operations.length == 109
  abort("error: OpenAPI 2.0.2 operation completion matrix changed")
end

client_capability_operations = operations.select do |operation|
  Array(operation["tags"]).include?("Client Capabilities")
end
client_capability_operations.sort_by! { |operation| operation.fetch("operationId") }
unless client_capability_operations.length == 31 && client_capability_operations.all? { |operation|
         operation.dig("x-access-policy", "defaultDeny") == true
       }
  abort("error: Client capability access-policy invariants changed")
end

default_denied_client_capability_operations = client_capability_operations.select do |operation|
  operation["x-enabled-by-default"] == false &&
    operation["x-default-deny-error"] == "SYSTEM_MODE_UNSUPPORTED" &&
    !operation["x-business-blocker"].to_s.empty?
end
local_integration_client_capability_operations =
  client_capability_operations - default_denied_client_capability_operations

expected_default_denied_operation_ids = %w[
  appendExerciseLocationSamples
  finalizeExerciseLocationTrack
  getActivityConversionRules
  getExerciseRecordLocationSummary
  getLocationPrivacyPolicy
  getSportCatalog
  startExerciseLocationTrack
  updateLocationPrivacyPolicy
].freeze
unless default_denied_client_capability_operations.map { |operation| operation.fetch("operationId") } ==
       expected_default_denied_operation_ids &&
       local_integration_client_capability_operations.length == 23 &&
       local_integration_client_capability_operations.all? { |operation|
         operation["x-enabled-by-default"].nil? &&
           operation["x-default-deny-error"].nil? &&
           operation["x-business-blocker"].nil?
       }
  abort("error: OpenAPI 2.0.2 client capability readiness split changed")
end

required_202_operations = %w[
  getAdminHealth
  getExerciseRecordEvidenceContext
  listStructuredExemptionApplications
].freeze
unless required_202_operations.all? { |operation_id|
         operations.any? { |operation| operation["operationId"] == operation_id }
       }
  abort("error: OpenAPI 2.0.2 additive operations are missing")
end

submit_record_operation = operations.find { |operation| operation["operationId"] == "submitExerciseRecord" }
unless submit_record_operation&.fetch("summary", "")&.include?("system VALID ReviewRecord") &&
       schemas.dig("ReviewRecord", "properties", "teacherId", "description")&.include?("initial system VALID")
  abort("error: OpenAPI 2.0.2 default-VALID review semantics changed")
end

runtime_query_parameters = {}
runtime_unsupported_query_parameters = []
operations.each do |operation|
  Array(operation["parameters"]).each do |parameter|
    next unless parameter.is_a?(Hash) && parameter["name"]

    key = "#{operation.fetch("operationId")}.#{parameter.fetch("name")}"
    runtime_query_parameters[key] = parameter.fetch("x-runtime-enum") if parameter["x-runtime-enum"]
    if parameter["x-runtime-unsupported"] == true
      runtime_unsupported_query_parameters << key
      unless parameter["deprecated"] == true
        abort("error: Runtime-unsupported query parameter must remain deprecated: #{key}")
      end
    end
  end
end
expected_runtime_query_parameters = {
  "listAuditLogs.sort" => %w[occurredAt -occurredAt],
  "listClassSections.status" => %w[UPCOMING ACTIVE CLOSED ARCHIVED],
  "listEnrollments.sort" => %w[joinedAt -joinedAt],
  "listExerciseRecordReviews.sort" => %w[reviewVersion -reviewVersion],
  "listExerciseRecords.sort" => %w[businessDate -businessDate],
  "listExports.sort" => %w[requestedAt -requestedAt],
  "listRosterAlignmentResults.sort" => %w[createdAt -createdAt],
  "listRosterEntries.sort" => %w[sourceRowNumber -sourceRowNumber],
  "listRosterImports.sort" => %w[versionNumber -versionNumber],
  "listStudents.sort" => %w[fullName -fullName studentNumber -studentNumber createdAt -createdAt]
}.freeze
expected_runtime_unsupported_query_parameters = %w[
  listScoreAdjustments.sort
  listScoreRules.sort
  listStudentScores.sort
].freeze
unless runtime_query_parameters == expected_runtime_query_parameters &&
       runtime_unsupported_query_parameters.sort == expected_runtime_unsupported_query_parameters
  abort("error: OpenAPI 2.0.2 query errata constraints changed")
end

runtime_property_enums = {
  ["InitiateMediaUploadRequest", "captureSource"] =>
    schemas.dig("InitiateMediaUploadRequest", "properties", "captureSource", "x-runtime-enum"),
  ["MediaAccessRequest", "purpose"] =>
    schemas.dig("MediaAccessRequest", "properties", "purpose", "x-runtime-enum")
}.freeze
unless runtime_property_enums == {
  ["InitiateMediaUploadRequest", "captureSource"] => %w[IN_APP_CAMERA FILE_PICKER],
  ["MediaAccessRequest", "purpose"] => %w[VIEW_ORIGINAL]
}
  abort("error: OpenAPI 2.0.2 media runtime constraints changed")
end
runtime_property_type_names = {
  ["InitiateMediaUploadRequest", "captureSource"] => "APIV1InitiateMediaUploadCaptureSource",
  ["MediaAccessRequest", "purpose"] => "APIV1MediaAccessPurpose"
}.freeze

wall_time_properties = %w[ClassSection UpdateClassSectionRequest].product(%w[dailyStartTime dailyEndTime])
unless wall_time_properties.all? { |schema_name, property_name|
         choices = schemas.dig(schema_name, "properties", property_name, "oneOf")
         Array(choices).length == 3 &&
           choices.any? { |choice| choice["type"] == "null" } &&
           choices.any? { |choice| choice["type"] == "string" && choice["format"] == "time" } &&
           choices.any? { |choice| choice["type"] == "string" && choice["pattern"] }
       }
  abort("error: OpenAPI 2.0.2 organization-local wall-time compatibility changed")
end

student_score_status_parameter = operations
  .find { |operation| operation["operationId"] == "listStudentScores" }
  &.fetch("parameters", [])
  &.find { |parameter| parameter["name"] == "status" }
unless student_score_status_parameter&.fetch("description", "")&.include?("Mutually exclusive")
  abort("error: OpenAPI 2.0.2 StudentScore status precedence is missing")
end

location_sample = schemas.fetch("LocationSample").fetch("properties")
raw_location_fields = %w[latitude longitude accuracyMeters altitudeMeters speedMillimetersPerSecond]
unless raw_location_fields.all? { |field| location_sample.fetch(field)["writeOnly"] == true }
  abort("error: Raw location fields must remain write-only")
end
location_summary_fields = schemas.fetch("LocationSummary").fetch("properties").keys
unless (location_summary_fields & raw_location_fields).empty?
  abort("error: Public location summary exposes raw location fields")
end

push_platforms = schemas.dig("PushDeviceRegistrationRequest", "properties", "platform", "enum")
push_projection_platforms = schemas.dig("PushDevice", "properties", "platform", "enum")
release_policy_platforms = schemas.dig("AppReleasePolicy", "properties", "platform", "enum")
feedback_platforms = schemas.dig(
  "CreateFeedbackRequest", "properties", "clientContext", "properties", "platform", "enum"
)
release_policy_operation = operations.find { |operation| operation["operationId"] == "getAppReleasePolicy" }
release_policy_query_platforms = Array(release_policy_operation&.fetch("parameters", []))
  .find { |parameter| parameter["name"] == "platform" }
  &.dig("schema", "enum")
unless [
  push_platforms,
  push_projection_platforms,
  release_policy_platforms,
  release_policy_query_platforms,
  feedback_platforms
].all? { |values|
         values == %w[ANDROID WEB IOS]
       }
  abort("error: IOS must remain a legal platform across every iOS-facing contract surface")
end

SWIFT_KEYWORDS = %w[
  associatedtype break case catch class continue default defer deinit do else enum
  extension fallthrough false fileprivate for func guard if import in init inout internal
  is let nil open operator private precedencegroup protocol public repeat rethrows return
  self Self static struct subscript super switch throw throws true try typealias var where while
].freeze

def upper_camel(value)
  pieces = value.to_s.gsub(/([a-z0-9])([A-Z])/, '\\1_\\2').split(/[^A-Za-z0-9]+/).reject(&:empty?)
  name = pieces.map { |piece| piece[0].upcase + piece[1..].to_s.downcase }.join
  name = "Value#{name}" if name.match?(/\A\d/)
  name.empty? ? "Value" : name
end

def lower_camel(value)
  name = upper_camel(value)
  name[0].downcase + name[1..].to_s
end

def swift_property_name(value)
  name = lower_camel(value)
  name = "value#{upper_camel(name)}" if name.match?(/\A\d/)
  SWIFT_KEYWORDS.include?(name) ? "`#{name}`" : name
end

def model_name(reference)
  "APIV1#{upper_camel(reference.to_s.split("/").last)}"
end

def nullable?(schema)
  Array(schema["type"]).include?("null") || Array(schema["oneOf"]).any? { |entry| entry["type"] == "null" }
end

def swift_type(schema)
  return model_name(schema["$ref"]) if schema["$ref"]

  if schema["oneOf"]
    choices = schema["oneOf"].reject { |entry| entry["type"] == "null" }
    choice_types = choices.map { |choice| swift_type(choice) }.uniq
    return choice_types.first if choice_types.length == 1
    return "APIV1JSONValue"
  end

  types = Array(schema["type"]).reject { |value| value == "null" }
  type = types.first
  case type
  when "string"
    "String"
  when "integer"
    "Int"
  when "number"
    "Decimal"
  when "boolean"
    "Bool"
  when "array"
    "[#{swift_type(schema.fetch("items", { "type" => "object" }))}]"
  when "object"
    additional = schema["additionalProperties"]
    if additional.is_a?(Hash)
      "[String: #{swift_type(additional)}]"
    else
      "[String: APIV1JSONValue]"
    end
  when "null"
    "APIV1JSONValue"
  else
    "APIV1JSONValue"
  end
end

def enum_case_name(raw_value, used)
  base = lower_camel(raw_value)
  base = "value#{upper_camel(base)}" if base.match?(/\A\d/)
  base = "#{base}Value" if SWIFT_KEYWORDS.include?(base)
  candidate = base
  suffix = 2
  while used.include?(candidate)
    candidate = "#{base}#{suffix}"
    suffix += 1
  end
  used << candidate
  candidate
end

def runtime_query_enum_name(key)
  operation_id, parameter_name = key.split(".", 2)
  "APIV1#{upper_camel(operation_id)}#{upper_camel(parameter_name)}RuntimeValue"
end

def runtime_query_case_name(raw_value, directional, used)
  base = lower_camel(raw_value.to_s.delete_prefix("-"))
  if directional
    base = "#{base}#{raw_value.to_s.start_with?("-") ? "Descending" : "Ascending"}"
  end
  candidate = base
  suffix = 2
  while used.include?(candidate)
    candidate = "#{base}#{suffix}"
    suffix += 1
  end
  used << candidate
  candidate
end

lines = []
lines << "// Generated by scripts/generate-openapi-models.rb. DO NOT EDIT."
lines << "// Source SHA-256: #{EXPECTED_SHA256}"
lines << ""
lines << "import Foundation"
lines << ""
lines << "enum APIV1ContractMetadata {"
lines << "    static let openAPIVersion = \"#{document.fetch("openapi")}\""
lines << "    static let contractVersion = \"#{document.dig("info", "version")}\""
lines << "    static let sourceSHA256 = \"#{EXPECTED_SHA256}\""
lines << "    static let apiPrefix = \"/api/v1\""
lines << "    static let pathCount = #{document.fetch("paths").length}"
lines << "    static let operationCount = #{operations.length}"
lines << "    static let schemaCount = #{schemas.length}"
lines << "    static let implementedOperationCount = #{operations.length - intentionally_disabled_operations.length}"
lines << "    static let intentionallyDisabledOperationCount = #{intentionally_disabled_operations.length}"
lines << "    static let systemModeUnsupportedOperationCount = #{system_mode_unsupported_operations.length}"
lines << "    static let clientCapabilityCount = #{client_capability_operations.length}"
lines << "    static let localIntegrationClientCapabilityCount = #{local_integration_client_capability_operations.length}"
lines << "    static let defaultDeniedClientCapabilityCount = #{default_denied_client_capability_operations.length}"
lines << "}"
lines << ""
lines << "enum APIV1JSONValue: Codable, Equatable {"
lines << "    case string(String)"
lines << "    case number(Decimal)"
lines << "    case boolean(Bool)"
lines << "    case object([String: APIV1JSONValue])"
lines << "    case array([APIV1JSONValue])"
lines << "    case null"
lines << ""
lines << "    init(from decoder: Decoder) throws {"
lines << "        let container = try decoder.singleValueContainer()"
lines << "        if container.decodeNil() { self = .null }"
lines << "        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }"
lines << "        else if let value = try? container.decode(Decimal.self) { self = .number(value) }"
lines << "        else if let value = try? container.decode(String.self) { self = .string(value) }"
lines << "        else if let value = try? container.decode([APIV1JSONValue].self) { self = .array(value) }"
lines << "        else { self = .object(try container.decode([String: APIV1JSONValue].self)) }"
lines << "    }"
lines << ""
lines << "    func encode(to encoder: Encoder) throws {"
lines << "        var container = encoder.singleValueContainer()"
lines << "        switch self {"
lines << "        case .string(let value): try container.encode(value)"
lines << "        case .number(let value): try container.encode(value)"
lines << "        case .boolean(let value): try container.encode(value)"
lines << "        case .object(let value): try container.encode(value)"
lines << "        case .array(let value): try container.encode(value)"
lines << "        case .null: try container.encodeNil()"
lines << "        }"
lines << "    }"
lines << "}"
lines << ""
[
  [
    "All operations formally classified as intentionally disabled in the 1.5 release.",
    "APIV1IntentionallyDisabledOperation",
    intentionally_disabled_operations
  ],
  [
    "Disabled operations whose stable fail-closed error is SYSTEM_MODE_UNSUPPORTED.",
    "APIV1SystemModeUnsupportedOperation",
    system_mode_unsupported_operations
  ],
  [
    "All 31 client-capability routes in the 2.0.2 contract. Membership does not imply remote readiness.",
    "APIV1ClientCapability",
    client_capability_operations
  ],
  [
    "Routes with backend local-integration evidence. Staging and production readiness remain separate.",
    "APIV1LocalIntegrationClientCapability",
    local_integration_client_capability_operations
  ],
  [
    "Routes that intentionally return SYSTEM_MODE_UNSUPPORTED after earlier request checks pass.",
    "APIV1DefaultDeniedClientCapability",
    default_denied_client_capability_operations
  ]
].each do |comment, enum_name, enum_operations|
  lines << "/// #{comment}"
  lines << "enum #{enum_name}: String, CaseIterable {"
  used_client_capability_cases = []
  enum_operations.each do |operation|
    operation_id = operation.fetch("operationId")
    lines << "    case #{enum_case_name(operation_id, used_client_capability_cases)} = #{operation_id.inspect}"
  end
  lines << "}"
  lines << ""
end
lines.pop

runtime_query_parameters.sort.each do |key, values|
  lines << ""
  lines << "/// Runtime-accepted values for #{key}; the OpenAPI string remains broad for 1.3 compatibility."
  lines << "enum #{runtime_query_enum_name(key)}: String, Codable, CaseIterable {"
  used = []
  directional = values.any? { |value| value.start_with?("-") }
  values.each do |raw_value|
    lines << "    case #{runtime_query_case_name(raw_value, directional, used)} = #{raw_value.inspect}"
  end
  lines << "}"
end

lines << ""
lines << "/// Query parameters retained only for 1.3 wire compatibility; clients must omit them."
lines << "enum APIV1RuntimeUnsupportedQueryParameter: String, CaseIterable {"
used_runtime_unsupported_cases = []
runtime_unsupported_query_parameters.sort.each do |key|
  lines << "    case #{enum_case_name(key, used_runtime_unsupported_cases)} = #{key.inspect}"
end
lines << "}"

runtime_property_enums.each do |key, values|
  lines << ""
  lines << "enum #{runtime_property_type_names.fetch(key)}: String, Codable, CaseIterable {"
  used = []
  values.each do |raw_value|
    lines << "    case #{enum_case_name(raw_value, used)} = #{raw_value.inspect}"
  end
  lines << "}"
end

schemas.each do |name, schema|
  swift_name = "APIV1#{upper_camel(name)}"
  lines << ""

  if schema["$ref"]
    lines << "typealias #{swift_name} = #{model_name(schema["$ref"])}"
    next
  end

  enum_values = schema["enum"]
  if enum_values&.any?
    lines << "enum #{swift_name}: String, Codable, CaseIterable {"
    used = []
    enum_values.each do |raw_value|
      lines << "    case #{enum_case_name(raw_value, used)} = #{raw_value.to_s.inspect}"
    end
    lines << "}"
    next
  end

  unless schema["type"] == "object" || schema["properties"]
    lines << "typealias #{swift_name} = #{swift_type(schema)}"
    next
  end

  properties = schema.fetch("properties", {})
  required = Array(schema["required"])
  lines << "struct #{swift_name}: Codable, Equatable {"
  if properties.empty?
    lines << "    init() {}"
  else
    properties.each do |property_name, property_schema|
      type = runtime_property_type_names.fetch([name, property_name]) { swift_type(property_schema) }
      optional = !required.include?(property_name) || nullable?(property_schema)
      lines << "    let #{swift_property_name(property_name)}: #{type}#{optional ? "?" : ""}"
    end
  end
  lines << "}"
end

generated = lines.join("\n") + "\n"

if options[:check]
  abort("error: Generated Swift models are missing: #{options[:output]}") unless File.file?(options[:output])
  existing = File.binread(options[:output])
  abort("error: Generated Swift models are stale. Run scripts/generate-openapi-models.rb") unless existing == generated
  puts "OpenAPI generated models are current (#{actual_hash})"
else
  FileUtils.mkdir_p(File.dirname(options[:output])) unless Dir.exist?(File.dirname(options[:output]))
  File.binwrite(options[:output], generated)
  puts "Generated #{schemas.length} Swift schemas from #{actual_hash}"
end
