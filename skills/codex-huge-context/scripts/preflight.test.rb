#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

SCRIPT = File.expand_path("preflight.rb", __dir__)
MODELS = %w[gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna].freeze
OUTPUT_SENTINEL = "fixture-output-must-not-appear"

def assert(condition, message)
  raise message unless condition
end

def write_fixture(root, helper_body:, config_extra: "", catalog_models: MODELS)
  helper = File.join(root, "fetch-key")
  catalog = File.join(root, "models.json")
  config = File.join(root, "config.toml")

  File.write(helper, "#!/bin/sh\nset -eu\n#{helper_body}\n")
  FileUtils.chmod(0o700, helper)
  File.write(
    catalog,
    JSON.generate(
      "models" => catalog_models.map do |slug|
        { "slug" => slug, "context_window" => 1_050_000, "max_context_window" => 1_050_000 }
      end,
    ),
  )
  File.write(
    config,
    <<~TOML,
      model = "gpt-5.6-sol"
      model_provider = "openai_api_direct"
      model_context_window = 1050000
      model_catalog_json = #{catalog.inspect}
      #{config_extra}

      [model_providers.openai_api_direct]
      name = "OpenAI API direct"
      base_url = "https://api.openai.com/v1"
      wire_api = "responses"
      requires_openai_auth = false

      [model_providers.openai_api_direct.auth]
      command = #{helper.inspect}
      timeout_ms = 5000
      refresh_interval_ms = 300000
    TOML
  )

  config
end

def run_preflight(config)
  Open3.capture3({ "GITHUB_PAT_TOKEN" => nil }, RbConfig.ruby, SCRIPT, "--config", config)
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(root, helper_body: "printf '%s\\n' '#{OUTPUT_SENTINEL}'")
  stdout, stderr, process_status = run_preflight(config)
  assert(process_status.success?, "valid fixture failed: #{stderr}")
  assert(stdout.include?("preflight: ok"), "success message missing")
  assert(stderr.include?("GITHUB_PAT_TOKEN is unset"), "independent GitHub MCP warning missing")
  assert(!"#{stdout}\n#{stderr}".include?(OUTPUT_SENTINEL), "credential leaked on successful preflight")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(
    root,
    helper_body: "printf '%s\\n' '#{OUTPUT_SENTINEL}'; printf '%s\\n' '#{OUTPUT_SENTINEL}' >&2; exit 44",
  )
  stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "failed helper unexpectedly passed")
  assert(stderr.include?("install or repair the dedicated Keychain delivery copy"), "helper failure is not actionable")
  assert(!"#{stdout}\n#{stderr}".include?(OUTPUT_SENTINEL), "credential leaked on failed preflight")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(root, helper_body: "exit 0")
  _stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "empty helper output unexpectedly passed")
  assert(stderr.include?("auth helper returned no credential"), "empty helper failure is unclear")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(root, helper_body: "printf '%s\\n' '#{OUTPUT_SENTINEL}'", config_extra: "model_auto_compact_token_limit = 233000")
  _stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "legacy compaction limit unexpectedly passed")
  assert(stderr.include?("remove model_auto_compact_token_limit"), "legacy compaction failure is unclear")
end

Dir.mktmpdir("codex-huge-context-test") do |root|
  config = write_fixture(root, helper_body: "printf '%s\\n' '#{OUTPUT_SENTINEL}'", catalog_models: MODELS.take(2))
  _stdout, stderr, process_status = run_preflight(config)
  assert(!process_status.success?, "incomplete model catalogue unexpectedly passed")
  assert(stderr.include?("model catalogue is missing gpt-5.6-luna"), "catalogue failure is unclear")
end

puts "codex huge-context preflight tests passed"
