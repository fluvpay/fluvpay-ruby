# frozen_string_literal: true

require_relative "lib/fluvpay/version"

Gem::Specification.new do |spec|
  spec.name = "fluvpay"
  spec.version = FluvPay::VERSION
  spec.authors = ["FluvPay"]
  spec.summary = "SDK oficial em Ruby para a API de pagamentos PIX da FluvPay."
  spec.description = "Cliente idiomático da FluvPay: cobranças PIX, saques, " \
                     "transferências internas, sandbox e verificação de webhooks. " \
                     "Idempotência automática, retries seguros e erros tipados, " \
                     "usando apenas a biblioteca padrão (net/http)."
  spec.homepage = "https://docs.fluvpay.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => "https://fluvpay.com",
    "documentation_uri" => "https://docs.fluvpay.com",
    "source_code_uri" => "https://github.com/fluvpay/fluvpay-ruby",
    "changelog_uri" => "https://github.com/fluvpay/fluvpay-ruby/releases",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.glob("lib/**/*.rb") + %w[README.md LICENSE]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
