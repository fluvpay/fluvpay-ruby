# frozen_string_literal: true

require_relative "test_helper"

# Testes do recurso de cobranças: body correto, headers e parsing da resposta.
class ChargesTest < Minitest::Test
  include FluvPayTestHelpers

  def test_create_envia_body_correto_e_headers
    charge = {
      "id" => "chg_01J9X8K2P3Q4R5S6T7U8V9W0XY",
      "merchant_id" => "mer_01J0000000000000000000000",
      "amount_cents" => 4990,
      "currency" => "BRL",
      "status" => "pending",
      "payment_method" => "pix",
      "pix_copy_paste" => "00020126...",
      "fee_processor_cents" => 25,
      "fee_platform_cents" => 10,
      "metadata" => {},
      "created_at" => "2026-06-08T12:00:00Z",
      "updated_at" => "2026-06-08T12:00:00Z"
    }

    captured = nil
    stub = stub_request(:post, "#{BASE_URL}/charges/")
           .with do |req|
             captured = req
             true
           end
           .to_return(status: 201, body: JSON.generate(charge), headers: json_headers)

    client = build_client
    result = client.charges.create(amount_cents: 4990, description: "Pedido #1042")

    assert_requested(stub)
    assert_equal "Bearer #{TEST_KEY}", captured.headers["Authorization"]
    assert_equal "application/json", captured.headers["Content-Type"]
    assert_equal "fluvpay-ruby/#{FluvPay::VERSION}", captured.headers["User-Agent"]
    refute_nil captured.headers["Idempotency-Key"]

    sent = JSON.parse(captured.body)
    assert_equal 4990, sent["amount_cents"]
    assert_equal "Pedido #1042", sent["description"]
    # A API rejeita campos extras: confirma que não mandamos currency nem method.
    refute sent.key?("currency")
    refute sent.key?("payment_method")
    refute sent.key?("method")
    # Valores nil são removidos do corpo (não enviamos customer vazio).
    refute sent.key?("customer")

    assert_equal "pending", result["status"]
    assert_equal "pix", result["payment_method"]
    assert_equal 4990, result["amount_cents"]
  end

  def test_create_respeita_idempotency_key_informada
    stub_request(:post, "#{BASE_URL}/charges/")
      .with(headers: { "Idempotency-Key" => "minha-chave-fixa" })
      .to_return(status: 201, body: JSON.generate({ "id" => "chg_x", "status" => "pending" }),
                 headers: json_headers)

    client = build_client
    result = client.charges.create(amount_cents: 100, idempotency_key: "minha-chave-fixa")
    assert_equal "chg_x", result["id"]
  end

  def test_create_inclui_customer_limpo
    captured = nil
    stub_request(:post, "#{BASE_URL}/charges/")
      .with { |req| captured = req; true }
      .to_return(status: 201, body: JSON.generate({ "id" => "chg_y", "status" => "pending" }),
                 headers: json_headers)

    client = build_client
    client.charges.create(
      amount_cents: 5000,
      customer: { name: "Maria Souza", email: "maria@exemplo.com", phone: nil }
    )

    sent = JSON.parse(captured.body)
    assert_equal "Maria Souza", sent["customer"]["name"]
    assert_equal "maria@exemplo.com", sent["customer"]["email"]
    refute sent["customer"].key?("phone")
  end

  def test_retrieve_faz_get_no_id
    stub_request(:get, "#{BASE_URL}/charges/chg_123")
      .to_return(status: 200, body: JSON.generate({ "id" => "chg_123", "status" => "paid" }),
                 headers: json_headers)

    client = build_client
    result = client.charges.retrieve("chg_123")
    assert_equal "chg_123", result["id"]
    assert_equal "paid", result["status"]
  end
end
