# frozen_string_literal: true

require_relative "test_helper"

# Testes da política de retry: só GET e POSTs idempotentes, em 429/5xx/conexão.
class RetryTest < Minitest::Test
  include FluvPayTestHelpers

  def setup
    # Neutraliza o backoff para os testes não dormirem de verdade.
    @client = build_client(max_retries: 2, backoff_factor: 0)
    @client.define_singleton_method(:sleep_backoff) { |*| nil }
  end

  def test_get_repete_apos_429_e_sucede
    stub_request(:get, "#{BASE_URL}/charges/chg_1")
      .to_return(status: 429, headers: json_headers.merge("Retry-After" => "0"))
      .then
      .to_return(status: 200, body: JSON.generate({ "id" => "chg_1", "status" => "paid" }), headers: json_headers)

    result = @client.charges.retrieve("chg_1")
    assert_equal "paid", result["status"]
  end

  def test_get_repete_apos_500_e_sucede
    stub_request(:get, "#{BASE_URL}/transactions/tx_1")
      .to_return(status: 500, headers: json_headers)
      .then
      .to_return(status: 200, body: JSON.generate({ "id" => "tx_1" }), headers: json_headers)

    result = @client.transactions.retrieve("tx_1")
    assert_equal "tx_1", result["id"]
  end

  def test_post_com_idempotency_key_repete
    stub_request(:post, "#{BASE_URL}/charges/")
      .to_return(status: 503, headers: json_headers)
      .then
      .to_return(status: 201, body: JSON.generate({ "id" => "chg_novo", "status" => "pending" }), headers: json_headers)

    result = @client.charges.create(amount_cents: 100, idempotency_key: "fixa-123")
    assert_equal "chg_novo", result["id"]
  end

  def test_429_persistente_estoura_retries_e_lanca
    stub_request(:get, "#{BASE_URL}/charges/chg_1")
      .to_return(status: 429, headers: json_headers.merge("Retry-After" => "0"))

    error = assert_raises(FluvPay::RateLimitError) { @client.charges.retrieve("chg_1") }
    assert_equal 429, error.status_code
    # 1 tentativa inicial + 2 retries = 3 chamadas.
    assert_requested(:get, "#{BASE_URL}/charges/chg_1", times: 3)
  end

  def test_400_nao_repete
    stub_request(:get, "#{BASE_URL}/charges/chg_1")
      .to_return(status: 400, body: JSON.generate({ "error" => { "code" => "VALIDATION_ERROR", "message" => "x" } }),
                 headers: json_headers)

    assert_raises(FluvPay::ValidationError) { @client.charges.retrieve("chg_1") }
    # Erro não-retentável: apenas 1 chamada.
    assert_requested(:get, "#{BASE_URL}/charges/chg_1", times: 1)
  end
end
