#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "optparse"
require "yaml"

EXPECTED_SHA256 = "fb040b671e3f25c48279ad6b173ced5f633de1b1a1a9db0cc0f23a11e3fde4d1"
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

unless document.dig("info", "version") == "1.1.0-contract" &&
       document.fetch("paths").length == 104 &&
       operations.length == 122 &&
       schemas.length == 271
  abort("error: OpenAPI 1.1 structural baseline mismatch")
end

client_capability_operations = operations.select do |operation|
  Array(operation["tags"]).include?("Client Capabilities")
end
client_capability_operations.sort_by! { |operation| operation.fetch("operationId") }
unless client_capability_operations.length == 30 && client_capability_operations.all? { |operation|
         operation["x-enabled-by-default"] == false &&
           operation["x-default-deny-error"] == "SYSTEM_MODE_UNSUPPORTED" &&
           operation.dig("x-access-policy", "defaultDeny") == true
       }
  abort("error: Client capability default-deny invariants changed")
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
release_policy_platforms = schemas.dig("AppReleasePolicy", "properties", "platform", "enum")
release_policy_operation = operations.find { |operation| operation["operationId"] == "getAppReleasePolicy" }
release_policy_query_platforms = Array(release_policy_operation&.fetch("parameters", []))
  .find { |parameter| parameter["name"] == "platform" }
  &.dig("schema", "enum")
unless [push_platforms, release_policy_platforms, release_policy_query_platforms].all? { |values|
         values == %w[ANDROID WEB]
       }
  abort("error: Review the iOS platform boundary before accepting new platform enum values")
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
    return swift_type(choices.first) if choices.length == 1
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
lines << "    static let defaultDeniedClientCapabilityCount = #{client_capability_operations.length}"
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
lines << "/// Operations published as real routes but intentionally unavailable until"
lines << "/// their backend business gates are approved. A 503 response must never be"
lines << "/// interpreted as a successful client-side mutation."
lines << "enum APIV1DefaultDeniedClientCapability: String, CaseIterable {"
used_client_capability_cases = []
client_capability_operations.each do |operation|
  operation_id = operation.fetch("operationId")
  lines << "    case #{enum_case_name(operation_id, used_client_capability_cases)} = #{operation_id.inspect}"
end
lines << "}"

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
      type = swift_type(property_schema)
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
