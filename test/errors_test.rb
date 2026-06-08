# frozen_string_literal: true

require_relative "test_helper"

# Testes do mapeamento de status HTTP para exceções tipadas.
class ErrorsTest < Minitest::Test
  include FluvPayTestHelpers

  def error_body(code:, message:, details: nil, trace_id: "01JTRACE")
    { "error" => { "code" => code, "message" => message, "details" => details, "trace_id" => trace_id } }
  end

  def test_422_vira_validation_error_com_details
    body = error_body(
      code: "VALIDATION_ERROR",
      message: "Dados inválidos",
      details: [{ "field" => "amount_cents", "message" => "muito baixo", "type" => "greater_than_equal" }]
    )
    stub_request(:post, "#{BASE_URL}/charges/")
      .to_return(status: 422, body: JSON.generate(body), headers: json_headers)

    client = build_client
    error = assert_raises(FluvPay::ValidationError) do
      client.charges.create(amount_cents: 1)
    end
    assert_equal "VALIDATION_ERROR", error.code
    assert_equal 422, error.status_code
    assert_equal "01JTRACE", error.trace_id
    assert_equal "amount_cents", error.details.first["field"]
    assert_kind_of FluvPay::Error, error
  end

  def test_401_vira_authentication_error
    stub_request(:get, "#{BASE_URL}/charges/chg_1")
      .to_return(status: 401, body: JSON.generate(error_body(code: "AUTHENTICATION_REQUIRED", message: "Faça login")),
                 headers: json_headers)

    client = build_client
    error = assert_raises(FluvPay::AuthenticationError) { client.charges.retrieve("chg_1") }
    assert_equal "AUTHENTICATION_REQUIRED", error.code
  end

  def test_403_vira_permission_error
    stub_request(:post, "#{BASE_URL}/withdrawals/")
      .to_return(status: 403,
                 body: JSON.generate(error_body(code: "SANDBOX_NOT_SUPPORTED_FOR_WITHDRAWALS", message: "Indisponível no sandbox")),
                 headers: json_headers)

    client = build_client
    error = assert_raises(FluvPay::PermissionError) do
      client.withdrawals.create(amount_cents: 1000, pix_key: "x@y.com", pix_key_type: "email")
    end
    assert_equal "SANDBOX_NOT_SUPPORTED_FOR_WITHDRAWALS", error.code
  end

  def test_404_vira_not_found_error
    stub_request(:get, "#{BASE_URL}/charges/chg_inexistente")
      .to_return(status: 404, body: JSON.generate(error_body(code: "NOT_FOUND", message: "Não encontrado")),
                 headers: json_headers)

    client = build_client
    assert_raises(FluvPay::NotFoundError) { client.charges.retrieve("chg_inexistente") }
  end

  def test_409_vira_conflict_error
    stub_request(:post, "#{BASE_URL}/charges/")
      .to_return(status: 409, body: JSON.generate(error_body(code: "IDEMPOTENCY_CONFLICT", message: "Chave reutilizada")),
                 headers: json_headers)

    client = build_client
    error = assert_raises(FluvPay::ConflictError) { client.charges.create(amount_cents: 100) }
    assert_equal "IDEMPOTENCY_CONFLICT", error.code
  end

  def test_429_vira_rate_limit_error_com_retry_after
    stub_request(:get, "#{BASE_URL}/charges/chg_1")
      .to_return(status: 429,
                 body: JSON.generate(error_body(code: "RATE_LIMITED", message: "Devagar")),
                 headers: json_headers.merge("Retry-After" => "7"))

    # max_retries: 0 garante que o 429 sobe como erro em vez de virar retry.
    client = build_client(max_retries: 0)
    error = assert_raises(FluvPay::RateLimitError) { client.charges.retrieve("chg_1") }
    assert_equal "RATE_LIMITED", error.code
    assert_in_delta 7.0, error.retry_after, 0.001
  end

  def test_500_vira_server_error
    stub_request(:get, "#{BASE_URL}/charges/chg_1")
      .to_return(status: 500, body: JSON.generate(error_body(code: "SERVER_ERROR", message: "Falha interna")),
                 headers: json_headers)

    client = build_client(max_retries: 0)
    assert_raises(FluvPay::ServerError) { client.charges.retrieve("chg_1") }
  end

  def test_timeout_vira_connection_error
    stub_request(:get, "#{BASE_URL}/charges/chg_1").to_timeout

    client = build_client(max_retries: 0)
    assert_raises(FluvPay::ConnectionError) { client.charges.retrieve("chg_1") }
  end
end
