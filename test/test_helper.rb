# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"
require "json"
require "fluvpay"

BASE_URL = "https://api.fluvpay.com/api/v1"
TEST_KEY = "fluv_test_chave_unitaria"

module FluvPayTestHelpers
  # Cria um cliente apontando para a base padrão, sem retries por padrão
  # (cada teste de retry liga explicitamente o que precisa).
  def build_client(max_retries: 0, **kwargs)
    FluvPay::Client.new(api_key: TEST_KEY, max_retries: max_retries, **kwargs)
  end

  def json_headers
    { "Content-Type" => "application/json" }
  end
end
